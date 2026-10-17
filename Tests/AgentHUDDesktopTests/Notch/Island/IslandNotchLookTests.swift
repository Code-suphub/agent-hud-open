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
            $0.collapseDelayMs = 5000
        }
        settings.panelLayout.setSwitches { $0.tokenUsage = false; $0.sessionList = false }
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

    /// The island in a light look of regular glass at a Transparency of 50 %, which regular glass draws at three fifths,
    /// 0.3: at a hardware notch it rests black glass, the screen's regular glass over four fifths of black
    /// (`HUDLook.notchRowTransparency`), with the housing inked, and opens into the light glass panel at the screen's
    /// transparency. The row takes none of the screen's
    /// transparency, so that it stays black glass at any setting, one with the camera housing, where bare glass would
    /// turn light over a light menu bar. On a display without a notch the bar standing in for one draws the light glass
    /// look at rest and open alike, with nothing inked.
    func testTheIslandRestsInTheNotchsRowAndOpensIntoTheLook() throws {
        let (hud, settings, key) = try hud(ScreenPlacement(mode: .notch, appearance: .light, material: .glass,
                                                            glassStyle: .regular, glassTransparency: 0.5))
        hud.apply(animated: false)
        let look = settings.effectiveLook(on: key), notched = hud.geometry.hasNotch
        XCTAssertEqual(look.appearance, .light)
        XCTAssertFalse(hud.island.rootView.isOpen)
        XCTAssertEqual(hud.island.rootView.look, notched ? look.inNotchRow : look, "at rest")
        XCTAssertEqual(hud.island.rootView.inksNotch, notched)
        if notched {
            XCTAssertEqual(hud.island.rootView.look.appearance, .dark, "the notch's row stays dark")
            XCTAssertEqual(hud.island.rootView.look.material, look.material, "in the look's material")
            if look.material == .glass {
                XCTAssertEqual(look.transparency, 0.3, "the screen's own, as regular glass draws it")
                XCTAssertEqual(look.glassStyle, .regular)
                XCTAssertEqual(hud.island.rootView.look,
                               HUDLook(appearance: .dark, material: .glass, transparency: HUDLook.notchRowTransparency,
                                       glassStyle: .regular),
                               "black glass, in the screen's glass, whatever the screen's transparency")
            }
        }

        hud.forceOpen()
        poll("the island opens") { hud.island.rootView.isOpen }
        XCTAssertEqual(hud.island.rootView.look, look, "open, it takes the screen's whole look")
        XCTAssertEqual(hud.island.rootView.inksNotch, notched, "and keeps the housing black")
    }

    /// A solid island at a hardware notch rests black and opaque, the wings of its reminders too, whatever solid
    /// Transparency its screen chooses, here the top, 100 %, which solid draws at 0.6: the row stays one with the camera
    /// housing. It opens into the screen's look at that transparency. On a display without a notch the bar takes the screen's look at rest too.
    func testASolidIslandRestsBlackInTheNotchsRowWhateverItsTransparency() throws {
        let (hud, settings, key) = try hud(ScreenPlacement(mode: .notch, appearance: .light, solidTransparency: 1))
        hud.apply(animated: false)
        let look = settings.effectiveLook(on: key), notched = hud.geometry.hasNotch
        let reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        XCTAssertEqual(look, HUDLook(appearance: .light, transparency: reduces ? 0 : 0.6), "the screen's own")
        XCTAssertFalse(hud.island.rootView.isOpen)
        XCTAssertEqual(hud.island.rootView.look, notched ? .standard : look, "at rest")
        if notched {
            XCTAssertEqual(hud.island.rootView.look.transparency, 0, "black, opaque")
            XCTAssertEqual(hud.island.rootView.look.coverOpacity, 1)
        }

        hud.forceOpen()
        poll("the island opens") { hud.island.rootView.isOpen }
        XCTAssertEqual(hud.island.rootView.look, look, "open, it takes the screen's whole look")
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
