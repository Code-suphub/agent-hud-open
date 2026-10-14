import AgentHUDSupport
import Foundation

/// What `get_panel` and `get_panel_image` tell an agent, and what every other tool answers with.
extension PanelTools {
    // MARK: Picture

    /// The picture with what it shows: which screen and layout and its revision, the panel's size in points, whether it
    /// scrolls on its display, and the pixels a point it is drawn at, with a note that says the same in words.
    func image(_ scope: PanelLayoutScope, among attached: [PanelScreen]) -> MCPToolReply {
        guard let picture else {
            return .failure("This copy of Agent HUD cannot draw the panel, so there is no picture of it here. "
                            + "get_panel reads the same panel as data.")
        }
        guard let drawn = picture(scope) else {
            return .failure("The panel's picture could not be drawn. Try again, or read the panel with get_panel.")
        }
        let fit = drawn.fit
        var note: String
        var display = "The main display"
        switch scope {
        case .shared:
            note = "The hover panel as \(layout.hasDraft ? "the unsaved draft" : "the saved layout") draws it"
        case .screen(let key):
            note = "The hover panel on \(name(of: key, among: attached)) as \(drawing(key)) draws it"
            if attached.contains(where: { $0.key == key }) { display = "That display" }
        }
        note += ", \(Self.points(drawn.width)) by \(Self.points(fit.height)) points, with account names masked, session titles "
            + "left out and any reading's reason or client's notice drawn as grey bars."
        if fit.scrolls {
            note += " \(display) opens it at most \(Self.points(fit.maximumHeight)) points tall, so a person scrolls to see "
                + "the rest; the picture shows all of it."
        }
        if drawn.isScaledDown {
            note += " It is drawn at \(Self.hundredths(drawn.scale)) pixels a point instead of \(Self.points(PanelPicture.pointScale)) "
                + "to stay within \(PanelPicture.pixelLimit) pixels tall."
        }
        let result: [String: JSONValue] = [
            "screen": .string(Self.name(of: scope)), "revision": .integer(revision), "unsaved": .bool(unsaved(scope)),
            "width": .integer(Int64(drawn.width.rounded())), "height": .integer(Int64(fit.height.rounded())),
            "scrolls": .bool(fit.scrolls), "pixelsPerPoint": .number(Self.hundredths(drawn.scale)), "note": .string(note),
        ]
        return .result(result, images: [MCPImage(mimeType: "image/png", data: drawn.png)])
    }

    /// Which layout a screen's panel draws, in words.
    private func drawing(_ key: String) -> String {
        switch layout.draft(of: key) {
        case .own?: return "its own unsaved draft"
        case .shared?: return "the shared layout, in an unsaved draft that has it use the shared layout"
        case nil: break
        }
        if layout.ownLayout(of: key) != nil { return "its own saved layout" }
        return layout.hasDraft ? "the shared layout's unsaved draft" : "the saved shared layout"
    }

    // MARK: Reading

    /// The screen argument that names a scope.
    static func name(of scope: PanelLayoutScope) -> String {
        guard case .screen(let key) = scope else { return "all" }
        return key
    }

    /// Whether the panel of a scope shows a draft: the shared layout's own, or for a screen the one its bar saves.
    private func unsaved(_ scope: PanelLayoutScope) -> Bool {
        guard case .screen(let key) = scope else { return layout.hasDraft }
        return layout.hasDraft(on: key)
    }

    /// The panel as an agent reads it: which screen, the layout in effect there and the style it sets, the panel's
    /// height on that display and whether it scrolls there, whether Settings shows reset countdowns, every section and
    /// every block the panel has, shown or hidden, with the readings of each block's rows, and the attached screens.
    func panel(_ scope: PanelLayoutScope, among attached: [PanelScreen], note: String? = nil) -> [String: JSONValue] {
        let effective = effective(scope), existing = store.view.panelBlocks
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
            "screen": .string(Self.name(of: scope)),
            "revision": .integer(revision),
            "unsaved": .bool(unsaved(scope)),
            "hasPrevious": .bool(layout.canRevert(scope)),
            "layout": (try? JSONValue.from(effective)) ?? .object([:]),
            "style": .object(style),
            "countdownOnInSettings": .bool(settings.showResetCountdown),
            "sections": .array(sections.map { section in
                .object(["key": .string(section.rawValue), "shown": .bool(plan.sections.contains(section)),
                         "onInSettings": .bool(switches[section] ?? true)])
            }),
            "blocks": .array(drawn.map { block(of: $0, shown: shown.contains($0.key)) }),
            "screens": .array(attached.map(listing)),
        ]
        if case .screen(let key) = scope { result["usesSharedLayout"] = .bool(layout.usesShared(key)) }
        if let measured = fit?(scope) {
            result["height"] = .integer(Int64(measured.height.rounded()))
            result["scrolls"] = .bool(measured.scrolls)
        }
        if let note { result["note"] = .string(note) }
        return result
    }

    /// One attached screen as an agent reads it: its key and role, how it presents the HUD, which layout its panel
    /// draws and whether that is a draft, the agents its resting HUD can show now, and those it shows under its layout.
    private func listing(_ screen: PanelScreen) -> JSONValue {
        let order = HUDAgentOrder(listed: layout.effective(for: screen.key).hud.agents, available: screen.agents)
        return .object([
            "key": .string(screen.key), "name": .string(screen.name), "mode": .string(screen.modeName),
            "edge": .string(screen.edge.rawValue), "hasNotch": .bool(screen.hasNotch),
            "layout": .string(layout.usesShared(screen.key) ? "shared" : "own"),
            "unsaved": .bool(layout.hasDraft(on: screen.key)),
            "agents": .array(screen.agents.map(JSONValue.string)),
            "shows": .array(order.arrange(screen.agents) { $0 }.map(JSONValue.string)),
        ])
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
