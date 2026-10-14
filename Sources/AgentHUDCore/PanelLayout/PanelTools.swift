import AgentHUDSupport
import Foundation

/// What Agent HUD's MCP tools do in the running application: read what the hover panel shows, draw a picture of it,
/// propose a layout for it, and drop a proposal.
///
/// Every answer comes from what the application holds: the last report, the settings and the layout store, and the
/// panel's own views, which the host measures and draws off screen through the closures it passes in. Nothing
/// here starts a provider read, opens the panel or writes the agent list, and nothing here saves: a proposal is a
/// draft until a person presses Save in the panel. A proposal is checked as an agent sent it, and one the panel
/// cannot do as asked is refused whole, with every reason, so an agent never believes a change that fell back. What
/// the layout already holds for a block or a row that is away may come back with it, so the layout that was read can
/// be sent again, and a proposal is kept as what it changes, so one that draws what is saved leaves no draft.
@MainActor
public struct PanelTools {
    private let store: UsageStore
    /// The number the revisions an agent is given are counted from.
    private let launch: Int64
    /// Draws the panel as `get_panel_image` returns it; nil where nothing can draw it.
    private let picture: (@MainActor () -> PanelPicture?)?
    /// Measures the panel at the main display's panel width without drawing it; nil where nothing can.
    private let fit: (@MainActor () -> PanelFit?)?

    /// Drawn once a launch. The layout store counts its changes from 0 at every launch, so counted from 0 a revision
    /// an agent read before a relaunch would pass for the current one after it.
    private static let drawnAtLaunch = Int64.random(in: 1...999_999) * 1_000

    /// - picture: draws the hover panel off screen, as the layout in effect draws it, with account names masked,
    ///   session titles left out and what providers and clients wrote as placeholder bars; without it
    ///   `get_panel_image` is refused.
    /// - fit: measures the panel off screen at the main display's panel width; without it `get_panel` leaves out the
    ///   panel's height and whether it scrolls.
    public init(store: UsageStore, picture: (@MainActor () -> PanelPicture?)? = nil,
                fit: (@MainActor () -> PanelFit?)? = nil) {
        self.init(store: store, launch: Self.drawnAtLaunch, picture: picture, fit: fit)
    }

    /// - launch: the number revisions are counted from, where a test names its own.
    init(store: UsageStore, launch: Int64, picture: (@MainActor () -> PanelPicture?)? = nil,
         fit: (@MainActor () -> PanelFit?)? = nil) {
        self.store = store
        self.launch = launch
        self.picture = picture
        self.fit = fit
    }

    private var layout: PanelLayoutStore { store.settings.panelLayout }

    /// The layout's revision as an agent is given it.
    private var revision: Int64 { launch + Int64(layout.revision) }

    public func answer(_ request: MCPToolRequest) -> MCPToolReply {
        switch request.tool {
        case MCPTools.getPanel:
            if let unknown = Self.unknown(request.arguments, taking: []) {
                return .failure("get_panel takes no arguments. \(unknown)")
            }
            return .result(panel())
        case MCPTools.getPanelImage:
            if let unknown = Self.unknown(request.arguments, taking: []) {
                return .failure("get_panel_image takes no arguments. \(unknown)")
            }
            return image()
        case MCPTools.setPanelLayout:
            return propose(request.arguments)
        case MCPTools.discardPanelDraft:
            if let unknown = Self.unknown(request.arguments, taking: []) {
                return .failure("Nothing was changed. discard_panel_draft takes no arguments. \(unknown)")
            }
            layout.discard()
            return .result(panel(note: "There is no draft now. The panel shows the saved layout."))
        default:
            return .failure("Agent HUD has no tool named \"\(request.tool)\".")
        }
    }

    /// Names the arguments a tool was sent and does not take; nil when it takes them all. An argument a tool does not
    /// take is something its caller believes was heeded, so it is refused, not passed over.
    private static func unknown(_ arguments: [String: JSONValue], taking taken: [String]) -> String? {
        let unknown = arguments.keys.filter { !taken.contains($0) }.sorted()
        return unknown.isEmpty ? nil : "Unknown: \(PanelLayout.quoted(unknown))."
    }

    // MARK: Proposing

    private static let layoutKeys = ["blocks", "order", "sections", "hiddenSections", "style"]
    private static let draftNote = "Shown in the panel as an unsaved draft. The user keeps it by hovering the Agent HUD and "
        + "pressing Save in the panel; it is dropped when Agent HUD restarts."
    private static let savedNote = "This is the layout already saved, so there is no draft."

    private func propose(_ arguments: [String: JSONValue]) -> MCPToolReply {
        let taken = Self.layoutKeys + ["from", "revision"]
        if let unknown = Self.unknown(arguments, taking: taken) {
            return .failure("Nothing was changed. \(unknown) It takes: \(PanelLayout.quoted(taken)).")
        }
        if let given = arguments["revision"], given != .null {
            guard case .integer(let read) = given else {
                return .failure("Nothing was changed. revision is the whole number get_panel returned.")
            }
            guard read == revision else {
                return .failure("Nothing was changed. The layout changed since you read it: its revision is now "
                                + "\(revision). Call get_panel again, then propose.")
            }
        }
        if let from = arguments["from"], from != .null {
            // A key given as null is not given, here as everywhere.
            guard Self.layoutKeys.allSatisfy({ (arguments[$0] ?? .null) == .null }) else {
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
        let existing = store.view.panelBlocks
        // Every reason at once: what the reading would forgive, then what the rest of the layout asks that the panel
        // cannot do. What the layout already holds for a block or a row that is away may come back with it.
        var reasons = PanelLayout.misreadings(of: document)
        let proposal = PanelLayout(json: document) ?? PanelLayout()
        reasons += proposal.issues(against: existing, holding: [layout.effective, layout.current])
            .map { "\($0.path): \($0.message)" }
        guard reasons.isEmpty else { return .failure("Nothing was changed. " + reasons.joined(separator: " ")) }
        // A proposal that draws what the saved layout draws is the saved layout, however it is spelled out: it leaves
        // no draft, and nothing a person could save that changes nothing.
        let asked = proposal.reduced(against: existing)
        layout.propose(asked == layout.current.reduced(against: existing) ? layout.current : asked)
        return .result(panel(note: layout.hasDraft ? Self.draftNote : Self.savedNote))
    }

    // MARK: Picture

    /// The picture with what it shows: which layout and its revision, the panel's size in points, whether it scrolls
    /// on the main display, and the pixels a point it is drawn at, with a note that says the same in words.
    private func image() -> MCPToolReply {
        guard let picture else {
            return .failure("This copy of Agent HUD cannot draw the panel, so there is no picture of it here. "
                            + "get_panel reads the same panel as data.")
        }
        guard let drawn = picture() else {
            return .failure("The panel's picture could not be drawn. Try again, or read the panel with get_panel.")
        }
        let fit = drawn.fit, draft = layout.hasDraft
        let drawing = draft ? "the unsaved draft" : "the saved layout"
        var note = "The hover panel as \(drawing) draws it, \(Self.points(drawn.width)) by \(Self.points(fit.height)) points, "
        note += "with account names masked, session titles left out and any reading's reason or client's notice drawn as grey bars."
        if fit.scrolls {
            note += " The main display opens it at most \(Self.points(fit.maximumHeight)) points tall, so a person scrolls to see "
                + "the rest; the picture shows all of it."
        }
        if drawn.isScaledDown {
            note += " It is drawn at \(Self.hundredths(drawn.scale)) pixels a point instead of \(Self.points(PanelPicture.pointScale)) "
                + "to stay within \(PanelPicture.pixelLimit) pixels tall."
        }
        let result: [String: JSONValue] = [
            "revision": .integer(revision), "unsaved": .bool(draft),
            "width": .integer(Int64(drawn.width.rounded())), "height": .integer(Int64(fit.height.rounded())),
            "scrolls": .bool(fit.scrolls), "pixelsPerPoint": .number(Self.hundredths(drawn.scale)), "note": .string(note),
        ]
        return .result(result, images: [MCPImage(mimeType: "image/png", data: drawn.png)])
    }

    // MARK: Reading

    /// The panel as an agent reads it: the layout in effect and the style it sets, the panel's height at the main
    /// display's panel width and whether it scrolls there, whether Settings shows reset countdowns, then every section
    /// and every block the panel has, shown or hidden, with the readings of each block's rows.
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
        let style: [String: JSONValue] = ["spacing": .string(plan.style.spacing.rawValue), "separators": .bool(plan.style.separators)]
        var result: [String: JSONValue] = [
            "revision": .integer(revision),
            "unsaved": .bool(layout.hasDraft),
            "hasPrevious": .bool(layout.canRevert),
            "layout": (try? JSONValue.from(effective)) ?? .object([:]),
            "style": .object(style),
            "countdownOnInSettings": .bool(settings.showResetCountdown),
            "sections": .array(sections.map { section in
                .object(["key": .string(section.rawValue), "shown": .bool(plan.sections.contains(section)),
                         "onInSettings": .bool(switches[section] ?? true)])
            }),
            "blocks": .array(drawn.map { block(of: $0, shown: shown.contains($0.key)) }),
        ]
        if let measured = fit?() {
            result["height"] = .integer(Int64(measured.height.rounded()))
            result["scrolls"] = .bool(measured.scrolls)
        }
        if let note { result["note"] = .string(note) }
        return result
    }

    /// One block as an agent reads it: how it is drawn, what it offers, and its readings. The countdown, the columns
    /// and the ring size are told only where the block has them to set.
    private func block(of plan: PanelBlockPlan, shown: Bool) -> JSONValue {
        var block: [String: JSONValue] = [
            "key": .string(plan.key), "kind": .string(plan.kind.rawValue), "shown": .bool(shown),
            "widget": .string(plan.widget.rawValue),
            "widgets": .array(plan.kind.widgets.map { .string($0.rawValue) }),
            "measures": .array(plan.measures.map { .string($0.rawValue) }),
            "offeredMeasures": .array(plan.kind.measures(under: plan.widget).map { .string($0.rawValue) }),
        ]
        if plan.kind.takesCountdown {
            block["countdown"] = .bool(plan.countdown && store.settings.settings.showResetCountdown)
        }
        if plan.kind.takesColumns(under: plan.widget) { block["columns"] = .integer(Int64(plan.columns)) }
        if plan.kind.takesRingSize(under: plan.widget) { block["ringSize"] = .string(plan.ringSize.rawValue) }
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

    /// One quota window's reading: numbers and times only, with no account name. Its name is the window's as the panel
    /// writes it, in the application's language: its provider worded it when it was read, and it is how the person
    /// who looks at the panel will call the row. A reading that shows no level has no burn rate, run-out time or token
    /// rate, as in the panel.
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
    /// A picture's scale to the hundredth below it, which never reads as more pixels than were drawn.
    private static func hundredths(_ value: Double) -> Double { (value * 100).rounded(.down) / 100 }
    private static func points(_ value: Double) -> String { "\(Int64(value.rounded()))" }
    private static func time(_ date: Date) -> String { date.formatted(.iso8601) }
}

extension PanelLayout {
    /// What reading a layout's JSON would forgive, as sentences for the agent that sent it: a value of the wrong type,
    /// a name this build does not know, columns outside 2 to 6, a property a block or the style does not have. Stored
    /// layouts are read forgivingly so that a newer build's layout still loads; an agent's proposal is told instead,
    /// since a forgiven name is a change that silently did not happen.
    static func misreadings(of json: JSONValue) -> [String] {
        guard let fields = json.objectValue else { return ["The layout is a JSON object."] }
        var found = names(fields["order"], at: "order", among: nil)
        found += names(fields["sections"], at: "sections", among: PanelSection.allCases.map(\.rawValue))
        found += names(fields["hiddenSections"], at: "hiddenSections", among: PanelSection.allCases.map(\.rawValue))
        found += misreadings(ofStyle: fields["style"] ?? .null)
        guard let blocks = fields["blocks"], blocks != .null else { return found }
        guard let blocks = blocks.objectValue else { return found + ["blocks is an object keyed by block key."] }
        for key in blocks.keys.sorted() {
            found += misreadings(ofBlock: blocks[key] ?? .null, at: "blocks.\(key)")
        }
        return found
    }

    private static func misreadings(ofBlock value: JSONValue, at path: String) -> [String] {
        guard let block = value.objectValue else { return ["\(path) is an object."] }
        var found: [String] = []
        for property in block.keys.sorted() {
            let value = block[property] ?? .null
            switch property {
            case "widget":
                found += misnamed(value, at: "\(path).widget", among: PanelWidget.allCases.map(\.rawValue))
            case "measures":
                found += names(value, at: "\(path).measures", among: PanelMeasure.allCases.map(\.rawValue))
            case "hidden", "countdown":
                if value != .null, value.boolValue == nil { found.append("\(path).\(property) is true or false.") }
            case "hiddenRows":
                if value != .null, value.arrayValue?.allSatisfy({ $0.stringValue != nil }) != true {
                    found.append("\(path).hiddenRows is a list of row keys.")
                }
            case "columns":
                if value != .null, value.countValue.map({ Block.columnRange.contains($0) }) != true {
                    found.append("\(path).columns is a whole number from 2 to 6.")
                }
            case "ringSize":
                found += misnamed(value, at: "\(path).ringSize", among: PanelRingSize.allCases.map(\.rawValue))
            default:
                found.append("\(path) has no property \"\(property)\"; a block takes widget, measures, hidden, hiddenRows, "
                             + "countdown, columns and ringSize.")
            }
        }
        return found
    }

    private static func misreadings(ofStyle value: JSONValue) -> [String] {
        if value == .null { return [] }
        guard let style = value.objectValue else { return ["style is an object."] }
        var found: [String] = []
        for property in style.keys.sorted() {
            let value = style[property] ?? .null
            switch property {
            case "spacing":
                found += misnamed(value, at: "style.spacing", among: PanelSpacing.allCases.map(\.rawValue))
            case "separators":
                if value != .null, value.boolValue == nil { found.append("style.separators is true or false.") }
            default:
                found.append("style has no property \"\(property)\"; the style takes spacing and separators.")
            }
        }
        return found
    }

    /// What is wrong with a list of names: not a list, an entry that is not a string, or one that is not `allowed`.
    private static func names(_ value: JSONValue?, at path: String, among allowed: [String]?) -> [String] {
        guard let value, value != .null else { return [] }
        guard let items = value.arrayValue else { return ["\(path) is a list."] }
        var found: [String] = []
        for (index, item) in items.enumerated() {
            guard let name = item.stringValue else { found.append("\(path)[\(index)] is a string."); continue }
            if let allowed, !allowed.contains(name) {
                found.append("\(path)[\(index)]: \"\(name)\" is not one of \(quoted(allowed)).")
            }
        }
        return found
    }

    private static func misnamed(_ value: JSONValue, at path: String, among allowed: [String]) -> [String] {
        if value == .null { return [] }
        guard let name = value.stringValue, allowed.contains(name) else {
            return ["\(path) is one of \(quoted(allowed))."]
        }
        return []
    }
}
