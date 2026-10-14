import AgentHUDSupport
import Foundation

/// What Agent HUD's MCP tools do in the running application: read what the hover panel shows, propose a layout for
/// it, and drop a proposal.
///
/// Every answer comes from what the application holds: the last report, the settings and the layout store. Nothing
/// here starts a provider read, opens the panel or writes the agent list, and nothing here saves: a proposal is a
/// draft until a person presses Save in the panel. A proposal is checked as an agent sent it, and one the panel
/// cannot do as asked is refused whole, with every reason, so an agent never believes a change that fell back.
@MainActor
public struct PanelTools {
    private let store: UsageStore

    public init(store: UsageStore) {
        self.store = store
    }

    private var layout: PanelLayoutStore { store.settings.panelLayout }

    public func answer(_ request: MCPToolRequest) -> MCPToolReply {
        switch request.tool {
        case MCPTools.getPanel:
            return .result(panel())
        case MCPTools.setPanelLayout:
            return propose(request.arguments)
        case MCPTools.discardPanelDraft:
            layout.discard()
            return .result(panel(note: "There is no draft now. The panel shows the saved layout."))
        default:
            return .failure("Agent HUD has no tool named \"\(request.tool)\".")
        }
    }

    // MARK: Proposing

    private static let layoutKeys = ["blocks", "order", "sections", "hiddenSections"]
    private static let draftNote = "Shown in the panel as an unsaved draft. The user keeps it by hovering the Agent HUD and "
        + "pressing Save in the panel; it is dropped when Agent HUD restarts."
    private static let savedNote = "This is the layout already saved, so there is no draft."

    private func propose(_ arguments: [String: JSONValue]) -> MCPToolReply {
        let taken = Self.layoutKeys + ["from", "revision"]
        let unknown = arguments.keys.filter { !taken.contains($0) }.sorted()
        guard unknown.isEmpty else {
            return .failure("Nothing was changed. Unknown: \(Self.quoted(unknown)). It takes: \(Self.quoted(taken)).")
        }
        if let given = arguments["revision"], given != .null {
            guard case .integer(let revision) = given else {
                return .failure("Nothing was changed. revision is the whole number get_panel returned.")
            }
            guard revision == Int64(layout.revision) else {
                return .failure("Nothing was changed. The layout changed since you read it: its revision is now "
                                + "\(layout.revision). Call get_panel again, then propose.")
            }
        }
        if let from = arguments["from"], from != .null {
            guard Self.layoutKeys.allSatisfy({ arguments[$0] == nil }) else {
                return .failure("Nothing was changed. Pass either from or a layout, not both.")
            }
            switch from.stringValue {
            case "default":
                layout.proposeDefault()
            case "previous":
                guard layout.canRevert else {
                    return .failure("Nothing was changed. There is no previous saved layout.")
                }
                layout.proposePrevious()
            default:
                return .failure("Nothing was changed. from is \"default\" or \"previous\".")
            }
            return .result(panel(note: layout.hasDraft ? Self.draftNote : Self.savedNote))
        }
        let document = JSONValue.object(arguments.filter { Self.layoutKeys.contains($0.key) })
        var reasons = PanelLayout.misreadings(of: document)
        if reasons.isEmpty, let proposal = PanelLayout(json: document) {
            reasons = proposal.issues(against: store.view.panelBlocks).map { "\($0.path): \($0.message)" }
            if reasons.isEmpty {
                layout.propose(proposal)
                return .result(panel(note: layout.hasDraft ? Self.draftNote : Self.savedNote))
            }
        }
        return .failure("Nothing was changed. " + reasons.joined(separator: " "))
    }

    // MARK: Reading

    /// The panel as an agent reads it: the layout in effect, then every section and every block the panel has, shown
    /// or hidden, with the readings of each block's rows.
    private func panel(note: String? = nil) -> [String: JSONValue] {
        let effective = layout.effective, existing = store.view.panelBlocks
        let plan = PanelLayoutPlan(layout: effective, blocks: existing)
        let settings = store.settings.settings
        let switches: [PanelSection: Bool] = [.blocks: settings.showIslandQuota, .tokens: settings.showIslandTokens,
                                              .sessions: settings.showIslandSessions]
        let sections = plan.sections + PanelSection.allCases.filter { !plan.sections.contains($0) }
        let shown = Set(plan.blocks.map(\.key))
        let drawn = plan.blocks + existing.filter { !shown.contains($0.key) }
            .map { PanelBlockPlan($0, changed: effective.blocks[$0.key] ?? PanelLayout.Block()) }
        var result: [String: JSONValue] = [
            "revision": .integer(Int64(layout.revision)),
            "unsaved": .bool(layout.hasDraft),
            "hasPrevious": .bool(layout.canRevert),
            "layout": (try? JSONValue.from(effective)) ?? .object([:]),
            "sections": .array(sections.map { section in
                .object(["key": .string(section.rawValue), "shown": .bool(plan.sections.contains(section)),
                         "onInSettings": .bool(switches[section] ?? true)])
            }),
            "blocks": .array(drawn.map { block(of: $0, shown: shown.contains($0.key)) }),
        ]
        if let note { result["note"] = .string(note) }
        return result
    }

    private func block(of plan: PanelBlockPlan, shown: Bool) -> JSONValue {
        var block: [String: JSONValue] = [
            "key": .string(plan.key), "kind": .string(plan.kind.rawValue), "shown": .bool(shown),
            "widget": .string(plan.widget.rawValue), "measure": .string(plan.measure.rawValue),
            "widgets": .array(plan.kind.widgets.map { .string($0.rawValue) }),
            "measures": .array(plan.measures.map { .string($0.rawValue) }),
        ]
        switch plan.kind {
        case .quota:
            block["name"] = .string(VendorCatalog.name(plan.key))
            let rows = store.rowGroups.first { $0.vendor == plan.key }?.rows ?? []
            block["rows"] = .array(rows.map { reading(of: $0, shown: !plan.hiddenRows.contains($0.agent.windowKey)) })
        case .billing:
            let accounts = store.enabledBilling.filter { $0.panelBlockKey == plan.key }
            block["name"] = .string(accounts.first?.displayName ?? plan.key)
            block["balances"] = .array(accounts.flatMap { account in
                account.balances.map { balance -> JSONValue in
                    var entry: [String: JSONValue] = ["currency": .string(balance.currency), "amount": .string("\(balance.total)"),
                                                      "state": .string(Self.state(store.view.assessment(of: account)))]
                    if let level = store.balanceLevel(balance, billing: account) { entry["level"] = .string(level.rawValue) }
                    if let date = balance.runsOutAt { entry["runsOutAt"] = .string(Self.time(date)) }
                    return .object(entry)
                }
            })
        }
        return .object(block)
    }

    /// One quota window's reading: numbers and times only, with no account name. A reading that shows no level has
    /// no burn rate, run-out time or token rate, as in the panel.
    private func reading(of row: AgentRow, shown: Bool) -> JSONValue {
        var reading: [String: JSONValue] = [
            "key": .string(row.agent.windowKey), "name": .string(row.agent.name), "shown": .bool(shown),
            "state": .string(Self.state(row.assessment)),
        ]
        if let used = row.usedPct { reading["usedPercent"] = .number(Self.tenths(used)) }
        if let level = row.level { reading["level"] = .string(level.rawValue) }
        if let reset = row.resetAt { reading["resetsAt"] = .string(Self.time(reset)) }
        if row.assessment.showsLevel, let rate = store.report?.insightsByAgent[row.id]?.burnRatePctPerHour {
            reading["burnPercentPerHour"] = .number(Self.tenths(rate))
        }
        if case .exhausts(let interval, beforeReset: true)? = store.view.outlook(for: row.id) {
            reading["runsOutAt"] = .string(Self.time(store.now.addingTimeInterval(interval)))
        }
        if let tokens = store.quotaTokensPerHour(for: row.id) { reading["tokensPerHour"] = .integer(Int64(tokens)) }
        return .object(reading)
    }

    /// The first thing that holds a reading back, in the order the panel weighs them; "normal" when nothing does.
    private static func state(_ assessment: ReadingAssessment) -> String {
        if !assessment.isCurrentAccount { return "other account" }
        switch assessment.status {
        case .readFailed: return "read failed"
        case .unverified: return "unverified"
        case .normal: break
        }
        if assessment.observedAt == nil { return "not read yet" }
        if !assessment.hasValue { return "no value" }
        if assessment.isResetPending { return "reset pending" }
        return assessment.isStale ? "stale" : "normal"
    }

    private static func tenths(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    private static func time(_ date: Date) -> String { date.formatted(.iso8601) }
    private static func quoted(_ names: [String]) -> String { names.map { "\"\($0)\"" }.joined(separator: ", ") }
}

extension PanelLayout {
    /// What reading a layout's JSON would forgive, as sentences for the agent that sent it: a value of the wrong type,
    /// a name this build does not know, a property a block does not have. Stored layouts are read forgivingly so that
    /// a newer build's layout still loads; an agent's proposal is told instead, since a forgiven name is a change
    /// that silently did not happen.
    static func misreadings(of json: JSONValue) -> [String] {
        guard let fields = json.objectValue else { return ["The layout is a JSON object."] }
        var found: [String] = []
        func names(_ key: String, among allowed: [String]?) {
            guard let value = fields[key], value != .null else { return }
            guard let items = value.arrayValue else { return found.append("\(key) is a list.") }
            for (index, item) in items.enumerated() {
                guard let name = item.stringValue else { found.append("\(key)[\(index)] is a string."); continue }
                if let allowed, !allowed.contains(name) {
                    found.append("\(key)[\(index)]: \"\(name)\" is not one of \(quotedList(allowed)).")
                }
            }
        }
        names("order", among: nil)
        names("sections", among: PanelSection.allCases.map(\.rawValue))
        names("hiddenSections", among: PanelSection.allCases.map(\.rawValue))
        guard let blocks = fields["blocks"], blocks != .null else { return found }
        guard let blocks = blocks.objectValue else { return found + ["blocks is an object keyed by block key."] }
        for key in blocks.keys.sorted() {
            let path = "blocks.\(key)"
            guard let block = blocks[key]?.objectValue else { found.append("\(path) is an object."); continue }
            for property in block.keys.sorted() {
                let value = block[property] ?? .null
                switch property {
                case "widget":
                    found += misnamed(value, at: "\(path).widget", among: PanelWidget.allCases.map(\.rawValue))
                case "measure":
                    found += misnamed(value, at: "\(path).measure", among: PanelMeasure.allCases.map(\.rawValue))
                case "hidden":
                    if value != .null, value.boolValue == nil { found.append("\(path).hidden is true or false.") }
                case "hiddenRows":
                    if value != .null, value.arrayValue?.allSatisfy({ $0.stringValue != nil }) != true {
                        found.append("\(path).hiddenRows is a list of row keys.")
                    }
                default:
                    found.append("\(path) has no property \"\(property)\"; a block takes widget, measure, hidden and hiddenRows.")
                }
            }
        }
        return found
    }

    private static func misnamed(_ value: JSONValue, at path: String, among allowed: [String]) -> [String] {
        if value == .null { return [] }
        guard let name = value.stringValue, allowed.contains(name) else {
            return ["\(path) is one of \(quotedList(allowed))."]
        }
        return []
    }

    private static func quotedList(_ names: [String]) -> String {
        names.map { "\"\($0)\"" }.joined(separator: ", ")
    }
}
