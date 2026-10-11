import AppKit
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

final class SimpleMeterTests: XCTestCase {
    @MainActor
    func testWindowsThatShareAMarkReportTheMostUsedOne() {
        let now = Date()
        func agent(_ id: String, _ vendor: String) -> AgentDescriptor {
            AgentDescriptor(id: id, vendor: vendor, model: id, source: "test", enabled: true)
        }
        let agents = [agent("claude-5h", "Claude"), agent("codex-5h", "Codex"), agent("claude-week", "Claude"), agent("kimi", "Kimi")]
        let report = UsageReport(generatedAt: now, snapshots: [
            .init(agentId: "claude-5h", remainingPct: 69, resetAt: now.addingTimeInterval(3600), windowDuration: 5.0 * 3600, updatedAt: now),
            .init(agentId: "claude-week", remainingPct: 38, resetAt: now.addingTimeInterval(86400), windowDuration: 7.0 * 86400, updatedAt: now),
            .init(agentId: "codex-5h", remainingPct: 82, resetAt: now.addingTimeInterval(3600), windowDuration: 5.0 * 3600, updatedAt: now),
        ], sessions: [])
        let view = ReportView(report: report, agents: agents, settings: Settings(), now: now)

        let items = SimpleMeterItem.items(rows: view.rows)

        XCTAssertEqual(items.map(\.vendor), ["Claude", "Codex", "Kimi"], "One item per mark, in row order")
        XCTAssertEqual(items.map(\.usedPct), [62, 18, nil], "Claude reports its weekly window, the more used of its two")
        XCTAssertEqual(items.map(\.label), ["62%", "18%", "–"])
        XCTAssertEqual(items[0].level, view.rows.first { $0.id == "claude-week" }?.level)
        XCTAssertNil(items[2].level, "A window with no reading has no level to colour it")
    }

    func testPanelIsSizedFromItsOneLengthAndDropsWhatIsSwitchedOff() {
        let items = [SimpleMeterItem(vendor: "Claude", usedPct: 62, level: .ok),
                     SimpleMeterItem(vendor: "Codex", usedPct: 100, level: .critical)]
        func config(_ edge: HUDEdge, size: Double = 22, rings: Bool = true, numbers: Bool = true) -> SimpleMeterConfig {
            SimpleMeterConfig(items: items, placement: ScreenPlacement(mode: .simple, edge: edge, simpleSize: size,
                                                                      showsRings: rings, showsNumbers: numbers))
        }
        let both = config(.top), ringsOnly = config(.top, numbers: false), numbersOnly = config(.top, rings: false)
        XCTAssertEqual(both.panelSize.height, 22 + both.insets.top + both.insets.bottom, "A ring sets the panel's thickness")
        XCTAssertEqual(ringsOnly.panelSize.width,
                       ringsOnly.insets.left + 2 * 22 + ringsOnly.itemGap + ringsOnly.insets.right,
                       "Without numbers the panel is its rings and the gaps between them")
        XCTAssertLessThan(ringsOnly.panelSize.width, both.panelSize.width)
        XCTAssertLessThan(numbersOnly.panelSize.height, both.panelSize.height, "A mark alone is shorter than its ring")
        XCTAssertEqual(both.labelWidth(items[1]), both.labelColumn, "The widest number sets a side panel's column")

        let side = config(.right)
        XCTAssertEqual(side.panelSize.width, side.insets.left + 22 + side.labelSpacing + side.labelColumn + side.insets.right)
        XCTAssertEqual(side.panelSize.height, side.insets.top + 2 * 22 + side.itemGap + side.insets.bottom)
        XCTAssertEqual(side.stripSize, CGSize(width: side.panelSize.width + SimpleMeterConfig.edgeMargin, height: side.panelSize.height),
                       "The margin is on the axis that meets the screen edge")
        XCTAssertEqual(both.stripSize, CGSize(width: both.panelSize.width, height: both.panelSize.height + SimpleMeterConfig.edgeMargin))

        let large = config(.top, size: 40)
        XCTAssertEqual(large.panelSize.height, 40 + large.insets.top + large.insets.bottom)
        XCTAssertGreaterThan(large.fontSize, both.fontSize, "The numbers scale with the rings")

        let empty = SimpleMeterConfig(items: [], placement: ScreenPlacement(mode: .simple, edge: .left))
        XCTAssertEqual(empty.panelSize.height, SimpleMeterConfig.emptyRun, "A panel with no quota row keeps something to grab")
    }

    func testDraggingASimplePanelKeepsItSimpleAndOnlyTheNotchBecomesADock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = CGPoint(x: screen.maxX - 4, y: 420)
        let simple = NotchGeometry.dragPlacement(at: point, screenFrame: screen, queue: CGSize(width: 120, height: 33),
                                                 placement: ScreenPlacement(mode: .simple, edge: .top, ringWidth: 2.5, showsNumbers: false))
        XCTAssertEqual(simple.mode, .simple)
        XCTAssertEqual(simple.edge, .right)
        XCTAssertEqual(simple.ringWidth, 2.5)
        XCTAssertFalse(simple.showsNumbers)
        let notch = NotchGeometry.dragPlacement(at: point, screenFrame: screen, queue: CGSize(width: 120, height: 33),
                                                placement: ScreenPlacement(mode: .notch, edge: .top))
        XCTAssertEqual(notch.mode, .logos)
    }

    @MainActor
    func testSimpleScreenParksItsPanelOnTheEdgeAndDrawsNoGlow() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let key = ScreenIdentity.key(for: screen)
        let domain = "app.agenthud.tests.simple.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.agents)
        let placement = ScreenPlacement(mode: .simple, edge: .right, offset: 0.3, simpleSize: 26)
        settings.update { $0.screens[key] = placement }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, accessAllowed: { false })
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours, now: Date()))
        let hud = ScreenHUD(key: key, screen: screen, store: store, settings: settings)
        defer { hud.close() }

        let config = SimpleMeterConfig(items: SimpleMeterItem.items(rows: store.rows), placement: placement)
        XCTAssertFalse(config.items.isEmpty)
        XCTAssertEqual(hud.geometry.mode, .simple)
        XCTAssertEqual(hud.geometry.edge, .right)
        XCTAssertEqual(hud.geometry.rect.maxX, screen.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(hud.geometry.rect.size.width, config.stripSize.width, accuracy: 0.001, "The strip is the panel and its margin")
        XCTAssertEqual(hud.geometry.rect.size.height, config.stripSize.height.rounded(), accuracy: 0.001)
        XCTAssertEqual(hud.island.rootView.simpleMeter, config)
        XCTAssertNil(hud.island.rootView.logoQueue, "The panel takes the logo queue's place")
        XCTAssertTrue(hud.island.rootView.hidesSilhouette)
        XCTAssertNil(hud.glow.glowLayer.contents, "Simple mode has no glow behind it")

        settings.update { $0.screens[key]?.showsNumbers = false }
        hud.apply(animated: false)
        XCTAssertLessThan(hud.geometry.rect.width, config.stripSize.width, "Switching the numbers off narrows the strip at once")
    }

    @MainActor
    func testEveryEdgeKeepsItsFiguresInPlaceWhileThePanelOpensInward() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let key = ScreenIdentity.key(for: screen)
        for edge in HUDEdge.allCases {
            let domain = "app.agenthud.tests.simple-open.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.agents)
            settings.update {
                $0.screens[key] = ScreenPlacement(mode: .simple, edge: edge, offset: 0.4)
                $0.collapseDelayMs = 5000
            }
            let store = UsageStore(provider: DemoUsageProvider(), settings: settings, accessAllowed: { false })
            store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours, now: Date()))
            let hud = ScreenHUD(key: key, screen: screen, store: store, settings: settings)
            defer { hud.close() }
            let strip = hud.geometry.rect

            hud.forceOpen()
            let root = hud.island.rootView, canvas = hud.island.panel.frame
            func global(_ local: CGRect) -> CGRect {
                CGRect(x: canvas.minX + local.minX, y: canvas.maxY - local.maxY, width: local.width, height: local.height)
            }
            XCTAssertTrue(root.isOpen, "\(edge)")
            XCTAssertNotNil(root.simpleMeter, "\(edge): the figures stay on the open panel")
            let figures = global(try XCTUnwrap(root.logoQueueFrame))
            XCTAssertEqual(figures.minX, strip.minX, accuracy: 0.5, "\(edge): the figures keep their place on screen")
            XCTAssertEqual(figures.minY, strip.minY, accuracy: 0.5, "\(edge)")
            XCTAssertEqual(figures.size.width, strip.width, accuracy: 0.5, "\(edge)")
            let card = global(try XCTUnwrap(root.presentationFrame))
            XCTAssertGreaterThan(card.width * card.height, strip.width * strip.height, "\(edge): the panel has opened")
            switch edge {
            case .top: XCTAssertEqual(card.maxY, screen.frame.maxY, accuracy: 1)
            case .bottom: XCTAssertEqual(card.minY, screen.frame.minY, accuracy: 1)
            case .left: XCTAssertEqual(card.minX, screen.frame.minX, accuracy: 1)
            case .right: XCTAssertEqual(card.maxX, screen.frame.maxX, accuracy: 1)
            }
            XCTAssertNil(hud.glow.glowLayer.contents, "\(edge): an open Simple HUD draws no glow either")
        }
    }
}
