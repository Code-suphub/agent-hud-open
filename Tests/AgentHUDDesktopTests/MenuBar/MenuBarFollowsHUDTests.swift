import AppKit
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

/// The menu bar follows the HUD: the status item's figure and colours, and the menu's vendors and balances, are those of
/// the agents a screen's resting HUD shows under its layout's list, a draft included, by the rule the HUD itself keeps
/// (`ScreenAgents`), and a balance's tooltip covers the period its card in that screen's panel covers.
@MainActor
final class MenuBarFollowsHUDTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// A display without a notch whose HUD is a Simple panel, which shows every agent with a row or a balance.
    private let simple = StatusItemController.Screen(key: "menu:simple", hasNotch: false)
    /// A display with a notch that keeps no placement, whose HUD is the island, whose glow shows the agents whose
    /// readings show a level.
    private let notch = StatusItemController.Screen(key: "menu:notch", hasNotch: true)

    /// Claude's two windows, 70 % and 20 % used, Codex's, 90 % used, Kimi's, not read yet, and DeepSeek's balance, whose
    /// estimated cost is 1 in the last hour, 2 three days ago and 4 twenty days ago, all in English, over settings of
    /// their own in which the `simple` display is a Simple panel.
    private func make() throws -> (controller: StatusItemController, store: UsageStore, settings: SettingsStore) {
        _ = NSApplication.shared
        let suite = "MenuBarFollowsHUDTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            L10n.setLanguage(.system)
        }
        // Each row: its vendor, its window and what is left of it.
        let windows: [(vendor: String, model: String, remaining: Double?)] = [
            ("Claude", "5h", 30), ("Claude", "Weekly", 80), ("Codex", "Weekly", 10), ("Kimi", "Weekly", nil),
            ("DeepSeek", "API", nil),
        ]
        let agents = windows.map {
            AgentDescriptor(id: "\($0.vendor):\($0.model)", vendor: $0.vendor, model: $0.model, source: "", enabled: true)
        }
        let settings = SettingsStore(defaults: defaults, defaultAgents: agents)
        let key = simple.key
        settings.update {
            $0.language = .en
            $0.screens[key] = ScreenPlacement(mode: .simple, edge: .top)
        }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        let costs = [(-20 * 86_400.0, 4), (-3 * 86_400.0, 2), (-3_600.0, 1)].map { ago, amount in
            CostBucket(start: now.addingTimeInterval(ago), amounts: ["USD": Decimal(amount)])
        }
        store.replace(report: UsageReport(
            generatedAt: now,
            snapshots: zip(agents, windows).compactMap { agent, window in
                window.remaining.map { .init(agentId: agent.id, remainingPct: $0, resetAt: now.addingTimeInterval(3_600), updatedAt: now) }
            },
            sessions: [], discoveredAgents: agents,
            billing: [APIBilling(vendor: "DeepSeek", balances: [.init(currency: "USD", total: 50, granted: 0, toppedUp: 0)],
                                 isAvailable: true, updatedAt: now, costs: costs, notice: nil)]))
        store.now = now
        return (StatusItemController(store: store, settings: settings), store, settings)
    }

    /// The vendors the menu names, in its order: each vendor's header, a lone row that names its vendor, and each
    /// balance.
    private func vendors(_ entries: [StatusMenuEntry]) -> [String] {
        entries.compactMap { entry in
            guard case .artwork(let vendor) = entry.icon else { return nil }
            return vendor
        }
    }

    /// The windows the menu lists under their vendors' headers, by name, in its order.
    private func windows(_ entries: [StatusMenuEntry]) -> [String] {
        entries.compactMap { entry in
            guard case .dot = entry.icon else { return nil }
            return entry.title
        }
    }

    private func hud(_ agents: [String]) -> PanelLayout {
        PanelLayout(hud: PanelLayout.HUD(agents: agents))
    }

    // MARK: The menu's rows

    /// Without a list the menu lists every vendor and balance, as it always has. A list narrows them to the agents the
    /// HUD of the menu's screen shows, in the list's order, the vendors before the balances as before: the shared
    /// layout's on a screen that draws it, a screen's own on that screen, and a draft at once. With no display the
    /// menu lists everything.
    func testTheMenuListsTheAgentsTheHUDOfItsScreenShows() throws {
        let (controller, _, settings) = try make()
        let everyone = ["Claude", "Codex", "Kimi", "DeepSeek"]
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), everyone)
        XCTAssertEqual(vendors(controller.menuEntries(on: notch)), everyone)
        XCTAssertEqual(vendors(controller.menuEntries()), everyone)

        XCTAssertTrue(settings.panelLayout.propose(hud(["DeepSeek", "Codex"])))
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), ["Codex", "DeepSeek"],
                       "a draft shows at once; the vendors come before the balances")
        XCTAssertEqual(windows(controller.menuEntries(on: simple)), [], "Codex's one window names its vendor, as a lone row does")

        XCTAssertTrue(settings.panelLayout.propose(hud(["Codex", "Claude"])))
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), ["Codex", "Claude"], "in the list's order")
        XCTAssertEqual(windows(controller.menuEntries(on: simple)), ["Weekly", "5h", "Weekly"], "each vendor keeps its windows")

        XCTAssertTrue(settings.panelLayout.propose(.own(hud(["Claude"])), for: notch.key))
        XCTAssertEqual(vendors(controller.menuEntries(on: notch)), ["Claude"], "a screen's own layout")
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), ["Codex", "Claude"], "the shared layout elsewhere")
        XCTAssertEqual(vendors(controller.menuEntries()), everyone, "no display has no HUD to follow")

        settings.panelLayout.discard()
        settings.panelLayout.discard(.screen(notch.key))
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), everyone, "Discard gives the saved layout back")
        XCTAssertEqual(vendors(controller.menuEntries(on: notch)), everyone)
    }

    /// The menu keeps the HUD's own rule: a list that names none of the agents the screen's HUD shows now narrows
    /// nothing. Kimi has no reading yet, so the island's glow, which shows the agents with a level, has no Kimi, while
    /// the Simple panel shows it.
    func testAListTheHUDCannotShowNarrowsNothing() throws {
        let (controller, _, settings) = try make()
        XCTAssertTrue(settings.panelLayout.propose(hud(["Kimi"])))
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), ["Kimi"])
        XCTAssertEqual(vendors(controller.menuEntries(on: notch)), ["Claude", "Codex", "Kimi", "DeepSeek"])
        XCTAssertTrue(settings.panelLayout.propose(hud(["Gemini"])))
        XCTAssertEqual(vendors(controller.menuEntries(on: simple)), ["Claude", "Codex", "Kimi", "DeepSeek"],
                       "an agent the Mac does not have")
    }

    // MARK: The status item

    /// The item's figure is the most used window of the agents the HUD shows whose readings show a level, and its
    /// colours its glow's parts, in its order. Without a list, every agent, as before; a draft shows at once.
    func testTheItemsFigureAndColoursFollowTheAgentsTheHUDShows() throws {
        let (controller, store, settings) = try make()
        let segments = store.view.glowSegments
        func levels(_ vendors: String...) -> [StatusLevel] {
            vendors.flatMap { vendor in segments.filter { $0.vendor == vendor }.map(\.level) }
        }
        XCTAssertEqual(levels("Claude").count, 2)
        XCTAssertEqual(levels("DeepSeek").count, 1)
        let everyone = StatusItemController.Figure(levels: store.levels, usedPct: 90)
        XCTAssertEqual(controller.figure(on: simple), everyone)
        XCTAssertEqual(controller.figure(on: nil), everyone)
        XCTAssertEqual(store.maxUsedPct, 90)

        XCTAssertTrue(settings.panelLayout.propose(hud(["Claude"])))
        XCTAssertEqual(controller.figure(on: simple), .init(levels: levels("Claude"), usedPct: 70))
        XCTAssertEqual(controller.figure(on: nil), everyone)
        XCTAssertEqual(store.maxUsedPct, 90, "the store's own figure counts every agent")

        XCTAssertTrue(settings.panelLayout.propose(hud(["DeepSeek", "Claude"])))
        XCTAssertEqual(controller.figure(on: simple), .init(levels: levels("DeepSeek", "Claude"), usedPct: 70),
                       "the colours in the list's order; a balance has no share used")

        XCTAssertTrue(settings.panelLayout.propose(hud(["Kimi"])))
        XCTAssertEqual(controller.figure(on: simple), .init(levels: [], usedPct: nil), "Kimi has no reading yet")
        XCTAssertEqual(controller.figure(on: notch), everyone, "the island shows no Kimi, so the list narrows nothing")
    }

    // MARK: A balance's tooltip

    /// A balance's tooltip says its estimated cost over the period its card in the panel of the menu's screen covers:
    /// its block's period, else the token chart's, else the last 24 hours, whatever range the statistics window shows.
    func testABalancesTooltipCoversThePeriodOfItsCardOnThatScreen() throws {
        let (controller, store, settings) = try make()
        func tooltip(on screen: StatusItemController.Screen?) -> String? {
            controller.menuEntries(on: screen).first { $0.title == "DeepSeek · Balance" }?.toolTip
        }
        func cost(_ label: String, _ amount: Decimal) -> String {
            "Est. cost · Last \(label): " + MoneyFormat.amount(amount, currency: "USD", estimated: true)
        }
        XCTAssertEqual(tooltip(on: simple), cost("24 h", 1))
        store.setStatsRange(.days30)
        XCTAssertEqual(tooltip(on: simple), cost("24 h", 1), "the statistics window's range changes nothing")

        XCTAssertTrue(settings.panelLayout.propose(PanelLayout(tokens: PanelLayout.Tokens(period: .week))))
        XCTAssertEqual(tooltip(on: simple), cost("7 days", 3), "the token chart's period")
        XCTAssertEqual(tooltip(on: nil), cost("7 days", 3), "the shared layout's without a display")

        XCTAssertTrue(settings.panelLayout.propose(PanelLayout(blocks: ["api:DeepSeek": PanelLayout.Block(period: .day)],
                                                               tokens: PanelLayout.Tokens(period: .month))))
        XCTAssertEqual(tooltip(on: simple), cost("24 h", 1), "the block's period comes first")

        XCTAssertTrue(settings.panelLayout.propose(.own(PanelLayout(blocks: ["api:DeepSeek": PanelLayout.Block(period: .month)])),
                                                   for: notch.key))
        XCTAssertEqual(tooltip(on: notch), cost("30 days", 7), "a screen's own layout")
        XCTAssertEqual(tooltip(on: simple), cost("24 h", 1))
        let layout = settings.panelLayout.effective(for: notch.key)
        XCTAssertEqual(store.enabledBilling.map(layout.costPeriod(of:)), [.month])
    }

    // MARK: On screen

    /// The menu opened from the status item lists what the HUD of the screen it opens on shows, and the item's figure
    /// follows the main display's HUD; each attached display is given the same list, so either is the one asked for.
    func testTheOpenMenuAndTheFigureFollowTheirDisplays() throws {
        let (controller, _, settings) = try make()
        defer { controller.closeMenu() }
        let screens = NSScreen.screens.map(StatusItemController.Screen.init)
        XCTAssertFalse(screens.isEmpty)
        for screen in screens { XCTAssertTrue(settings.panelLayout.propose(.own(hud(["Claude"])), for: screen.key)) }
        XCTAssertEqual(StatusItemController.Screen.primary, screens.first)
        XCTAssertEqual(controller.figure(on: .primary).usedPct, 70)
        controller.openMenu()
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(vendors(panel.model.entries), ["Claude"])
    }
}
