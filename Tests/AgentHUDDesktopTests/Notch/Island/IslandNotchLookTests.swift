import AgentHUDCore
import AppKit
import XCTest
@testable import AgentHUDDesktop

/// The look the island draws with on its screen (`ScreenHUD`): in Notch mode at a hardware notch it stays dark in the
/// notch's row while it rests there (`HUDLook.inNotchRow`) and takes the screen's whole look once it opens, with the
/// camera housing inked black in any look but the standard one (`NotchInk`); everywhere else, the screen's look always.
@MainActor
final class IslandNotchLookTests: XCTestCase {
    /// The main display's HUD in `placement`, over settings of its own, with the pointer kept off it.
    private func hud(_ placement: ScreenPlacement) throws -> (hud: ScreenHUD, settings: SettingsStore, key: String) {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let key = ScreenIdentity.key(for: screen)
        let domain = "app.agenthud.tests.island-notch-look.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        addTeardownBlock { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.agents)
        settings.update {
            $0.screens[key] = placement
            $0.showIslandTokens = false
            $0.showIslandSessions = false
            $0.collapseDelayMs = 5000
        }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, accessAllowed: { false })
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours, now: Date()))
        let hud = ScreenHUD(key: key, screen: screen, store: store, settings: settings,
                            mouseLocation: { CGPoint(x: screen.frame.minX + 20, y: screen.frame.minY + 20) })
        addTeardownBlock { hud.close() }
        return (hud, settings, key)
    }

    /// Waits for the main run loop to bring `condition` about, for up to two seconds.
    private func poll(_ what: String, line: UInt = #line, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), what, line: line)
    }

    /// The island in a light glass look: at a hardware notch it rests dark glass at the screen's transparency, with the
    /// housing inked, and opens into the light glass panel; on a display without a notch the bar standing in for one
    /// draws the light glass look at rest and open alike, with nothing inked.
    func testTheIslandRestsInTheNotchsRowAndOpensIntoTheLook() throws {
        let (hud, settings, key) = try hud(ScreenPlacement(mode: .notch, appearance: .light, material: .glass,
                                                            glassTransparency: 0.3))
        hud.apply(animated: false)
        let look = settings.effectiveLook(on: key), notched = hud.geometry.hasNotch
        XCTAssertEqual(look.appearance, .light)
        XCTAssertFalse(hud.island.rootView.isOpen)
        XCTAssertEqual(hud.island.rootView.look, notched ? look.inNotchRow : look, "at rest")
        XCTAssertEqual(hud.island.rootView.inksNotch, notched)
        if notched {
            XCTAssertEqual(hud.island.rootView.look.appearance, .dark, "the notch's row stays dark")
            XCTAssertEqual(hud.island.rootView.look.material, look.material, "in the look's material")
            XCTAssertEqual(hud.island.rootView.look.transparency, look.transparency)
        }

        hud.forceOpen()
        poll("the island opens") { hud.island.rootView.isOpen }
        XCTAssertEqual(hud.island.rootView.look, look, "open, it takes the screen's whole look")
        XCTAssertEqual(hud.island.rootView.inksNotch, notched, "and keeps the housing black")
    }

    /// The island at a hardware notch keeps its ink in every look, so that a change of look fades it in or out rather
    /// than adding it, and under the standard look the ink is clear: the black island is the housing as it has always
    /// been. A dock on a notched display draws the screen's look, at rest too, with no ink at all.
    func testTheHousingIsInkedBeyondTheStandardLookAndNeverOnADock() throws {
        let (standard, _, _) = try hud(ScreenPlacement(mode: .notch))
        standard.apply(animated: false)
        XCTAssertEqual(standard.island.rootView.look, .standard, "the ink is drawn clear")
        XCTAssertEqual(standard.island.rootView.inksNotch, standard.geometry.hasNotch)
        standard.close()

        let (dock, settings, key) = try hud(ScreenPlacement(mode: .simple, appearance: .light))
        dock.apply(animated: false)
        XCTAssertEqual(dock.island.rootView.look, settings.effectiveLook(on: key))
        XCTAssertEqual(dock.island.rootView.look.appearance, .light)
        XCTAssertFalse(dock.island.rootView.inksNotch)
    }
}
