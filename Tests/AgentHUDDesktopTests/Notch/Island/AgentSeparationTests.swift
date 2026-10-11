import AppKit
import XCTest
import AgentHUDCore
@testable import AgentHUDDesktop

final class AgentSeparationTests: XCTestCase {
    @MainActor
    func testMarksAreFoundAlongEveryEdgeAndOnlyOnTheStrip() {
        let centres: [(vendor: String, along: CGFloat)] = [("Claude", 10), ("Codex", 40), ("Grok", 70)]
        let top = CGRect(x: 500, y: 868, width: 80, height: 32)
        let marks = ScreenHUD.agentMarks(centres: centres, strip: top, edge: .top)
        XCTAssertEqual(marks.map(\.anchor), [510, 540, 570])
        XCTAssertEqual(ScreenHUD.mark(at: CGPoint(x: 548, y: 880), among: marks, strip: top, edge: .top)?.vendor, "Codex")
        XCTAssertEqual(ScreenHUD.mark(at: CGPoint(x: 579, y: 880), among: marks, strip: top, edge: .top)?.vendor, "Grok")
        XCTAssertNil(ScreenHUD.mark(at: CGPoint(x: 548, y: 800), among: marks, strip: top, edge: .top),
                     "A pointer in the open panel keeps the agent it came from")

        // A side strip is read from the top down, against the screen's upward coordinates.
        let right = CGRect(x: 1568, y: 400, width: 32, height: 80)
        let side = ScreenHUD.agentMarks(centres: centres, strip: right, edge: .right)
        XCTAssertEqual(side.map(\.anchor), [470, 440, 410])
        XCTAssertEqual(ScreenHUD.mark(at: CGPoint(x: 1580, y: 468), among: side, strip: right, edge: .right)?.vendor, "Claude")
    }

    @MainActor
    func testMarkCentresFollowTheLayoutThatDrawsThem() {
        let items = [SimpleMeterItem(vendor: "Claude", usedPct: 62, level: .ok),
                     SimpleMeterItem(vendor: "Codex", usedPct: 18, level: .ok)]
        for edge in HUDEdge.allCases {
            let meter = SimpleMeterConfig(items: items, placement: ScreenPlacement(mode: .simple, edge: edge))
            let centres = meter.markCentres
            let run = edge.isHorizontal ? meter.panelSize.width : meter.panelSize.height
            XCTAssertEqual(centres.map(\.vendor), ["Claude", "Codex"])
            XCTAssertGreaterThan(centres[0].along, meter.mark / 2 - 0.5)
            XCTAssertGreaterThanOrEqual(centres[1].along - centres[0].along, meter.mark + meter.itemGap - 0.5)
            XCTAssertLessThan(centres[1].along + meter.mark / 2, run, "\(edge): the last mark is inside the panel")
        }
        let queue = LogoQueueConfig(items: [LogoQueueItem(vendor: "Claude", isWorking: false),
                                            LogoQueueItem(vendor: "Codex", isWorking: false)],
                                    placement: ScreenPlacement(logoSize: 20, gapScale: 0.5), settings: Settings())
        XCTAssertEqual(queue.markCentres.map(\.along), [10, 40])
    }

    @MainActor
    func testAnAgentsCardIsCentredOnItsMarkAndKeptOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let strip = CGRect(x: 600, y: 868, width: 400, height: 32)
        let top = NotchGeometry(screenFrame: screen, mode: .logos, edge: .top, hasNotch: false, rect: strip,
                                cornerRadius: 10, backingScale: 2, menuBarHeight: 32)
        XCTAssertEqual(top.expandedFrame(size: CGSize(width: 400, height: 200)).midX, 800)
        XCTAssertEqual(top.expandedFrame(size: CGSize(width: 400, height: 200), around: 650).midX, 650)
        XCTAssertEqual(top.expandedFrame(size: CGSize(width: 400, height: 200), around: 40).minX, 0)
        let side = NotchGeometry(screenFrame: screen, mode: .simple, edge: .right, hasNotch: false,
                                 rect: CGRect(x: 1568, y: 300, width: 32, height: 300),
                                 cornerRadius: 10, backingScale: 2, menuBarHeight: 32)
        let card = side.expandedFrame(size: CGSize(width: 400, height: 200), around: 560)
        XCTAssertEqual(card.midY, 560)
        XCTAssertEqual(card.maxX, 1600)
    }

    @MainActor
    func testHoveringAMarkOpensThatAgentsPanelAndAReminderKeepsTheMarks() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let key = ScreenIdentity.key(for: screen)
        for mode in [HUDMode.simple, .logos] {
            for edge in HUDEdge.allCases {
                let domain = "app.agenthud.tests.separate.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
                defer { defaults.removePersistentDomain(forName: domain) }
                let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.everyAgent)
                settings.update { $0.screens[key] = ScreenPlacement(mode: mode, edge: edge, separatesAgents: true) }
                let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
                store.replace(report: DemoUsageProvider.report(agents: settings.agents,
                    historyHours: UsageStore.historyHours, now: Date()))
                var pointer = CGPoint(x: -10_000, y: -10_000)
                let hud = ScreenHUD(key: key, screen: screen, store: store, settings: settings,
                                    mouseLocation: { pointer })
                defer { hud.close() }
                let strip = hud.geometry.rect
                let run = edge.isHorizontal ? strip.width : strip.height
                XCTAssertGreaterThan(run, 60, "\(mode) \(edge): the demo dock has several marks")

                // Whole, until a mark is hovered.
                hud.forceOpen()
                let whole = try XCTUnwrap(hud.island.rootView.presentationFrame)
                XCTAssertNil(hud.island.rootView.focusVendor)
                hud.forceCollapse()

                // The first mark in reading order: left on a horizontal edge, top on a side.
                pointer = edge.isHorizontal ? CGPoint(x: strip.minX + 6, y: strip.midY)
                                            : CGPoint(x: strip.midX, y: strip.maxY - 6)
                hud.samplePointer()
                hud.forceOpen()
                let first = try XCTUnwrap(hud.island.rootView.focusVendor, "\(mode) \(edge)")
                let card = try XCTUnwrap(hud.island.rootView.presentationFrame)
                XCTAssertLessThan(card.width, whole.width, "\(mode) \(edge): one agent's panel is narrower than the whole")
                XCTAssertTrue(hud.island.panel.frame.insetBy(dx: -1, dy: -1).contains(strip),
                              "\(mode) \(edge): the other marks stay on the canvas")

                // Sliding to the far end of the strip changes agent without closing.
                pointer = edge.isHorizontal ? CGPoint(x: strip.maxX - 6, y: strip.midY)
                                            : CGPoint(x: strip.midX, y: strip.minY + 6)
                hud.samplePointer()
                let last = try XCTUnwrap(hud.island.rootView.focusVendor)
                XCTAssertNotEqual(first, last, "\(mode) \(edge)")
                XCTAssertTrue(hud.island.rootView.isOpen)
                hud.forceCollapse()

                // A reminder from the first agent opens beside its mark and replaces nothing.
                hud.present(.completion(SessionCompletion(
                    sessionID: "separate", vendor: first, turnID: "reply", task: "New reply",
                    model: "test", startedAt: nil, completedAt: Date())))
                XCTAssertEqual(hud.island.rootView.focusVendor.map(AgentArtwork.markKey), AgentArtwork.markKey(first))
                XCTAssertNotNil(hud.island.rootView.alert)
                XCTAssertTrue(hud.island.panel.frame.insetBy(dx: -1, dy: -1).contains(strip),
                              "\(mode) \(edge): a reminder leaves the marks standing")
                XCTAssertTrue(screen.frame.insetBy(dx: -1, dy: -1).contains(hud.island.panel.frame))
            }
        }
    }

    func testSeparationIsOffUnlessStoredAndSurvivesARoundTrip() throws {
        XCTAssertFalse(ScreenPlacement().separatesAgents)
        let old = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"simple","edge":"right"}"#.utf8))
        XCTAssertFalse(old.separatesAgents)
        let on = ScreenPlacement(mode: .simple, separatesAgents: true)
        XCTAssertEqual(try JSONDecoder().decode(ScreenPlacement.self, from: JSONEncoder().encode(on)), on)
    }
}
