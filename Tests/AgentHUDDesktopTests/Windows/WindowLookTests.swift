import AgentHUDCore
import AppKit
import XCTest
@testable import AgentHUDDesktop

/// The look the app's own windows and the menu-bar menu take under Appearance → Match screen (`WindowLook`): the look of
/// the HUD on the screen they are on, nothing under any other Appearance, and a window that takes it, or gives it back,
/// as the look it is given changes.
@MainActor
final class WindowLookTests: XCTestCase {
    /// Sets where the windows' look comes from for one test, and when it ends gives back none, as a process without
    /// `DesktopApplication` has. Kept in the test rather than in `setUp`, which is not on the main actor.
    private func giveLooks(_ source: @escaping (NSScreen?) -> HUDLook?) {
        _ = NSApplication.shared
        WindowLook.source = source
    }

    private func store() -> SettingsStore {
        let suite = "app.agenthud.tests.window-look.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
    }

    // MARK: Where the look comes from

    /// With Match screen off the windows and the menu take the app's own Appearance, System, Light or Dark, whatever a
    /// screen's HUD looks like: there is no look for them on any screen.
    func testOnlyMatchScreenGivesTheWindowsALook() {
        let settings = store()
        settings.update {
            for display in NSScreen.screens {
                $0.screens[ScreenIdentity.key(for: display)] = ScreenPlacement(mode: .simple, appearance: .light,
                                                                               material: .glass)
            }
        }
        for appearance in [AppearanceMode.system, .light, .dark] {
            settings.update { $0.appearance = appearance }
            XCTAssertNil(settings.windowLook(on: nil), "\(appearance)")
            for display in NSScreen.screens {
                XCTAssertNil(settings.windowLook(on: display), "\(appearance)")
            }
        }
    }

    /// With Match screen on a window on a screen takes the look of that screen's HUD, as the panel that opens there draws
    /// it, its style draft included; with no screen named it takes the main screen's.
    func testMatchScreenGivesEachScreensHUDLook() throws {
        let settings = store()
        settings.update { $0.appearanceFollowsScreen = true }
        try XCTSkipIf(NSScreen.screens.isEmpty, "no display is attached to take a look from")
        for display in NSScreen.screens {
            let key = ScreenIdentity.key(for: display)
            XCTAssertEqual(settings.windowLook(on: display), settings.effectiveLook(on: key), key)
            settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, appearance: .light) }
            XCTAssertEqual(settings.windowLook(on: display)?.appearance, .light, key)
            settings.panelLayout.proposeStyle(HUDStyle(appearance: .dark), for: key, hasNotch: ScreenIdentity.hasNotch(display))
            XCTAssertEqual(settings.windowLook(on: display)?.appearance, .dark, "the style draft is drawn over the settings")
            settings.panelLayout.discardStyle(key)
        }
        if let main = NSScreen.main {
            XCTAssertEqual(settings.windowLook(on: nil), settings.windowLook(on: main))
        }
    }

    // MARK: A window that takes it

    /// A hosted window takes the look its screen gives it as its appearance, light or dark, and again whenever it is
    /// asked to, as on a move to another screen; given none, it takes the app's own again.
    func testAWindowTakesTheLookOfItsScreen() throws {
        let controller = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Look")
        let window = try XCTUnwrap(controller.window)
        XCTAssertNil(window.appearance)

        var look: HUDLook? = HUDLook(appearance: .light)
        giveLooks { _ in look }
        defer { WindowLook.source = nil }
        controller.refreshLook()
        XCTAssertEqual(window.appearance?.name, .aqua)

        look = HUDLook(appearance: .dark, material: .glass)
        controller.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification, object: window))
        XCTAssertEqual(window.appearance?.name, .darkAqua, "a move to another screen takes that screen's look")

        look = nil
        controller.refreshLook()
        XCTAssertNil(window.appearance, "under any other Appearance the window takes the app's")
    }

    /// Every hosted window takes its look again at once, as after a change of the setting or of a screen's look.
    func testEveryWindowTakesItsLookAgain() throws {
        let one = HostedWindowController(size: CGSize(width: 320, height: 200), title: "One")
        let two = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Two")
        // Never shown: the app's windows are every one it has, on screen or not.
        let windows = try [XCTUnwrap(one.window), XCTUnwrap(two.window)]

        giveLooks { _ in HUDLook(appearance: .light) }
        defer { WindowLook.source = nil }
        WindowLook.refreshAll()
        XCTAssertEqual(windows.map { $0.appearance?.name }, [.aqua, .aqua])
        giveLooks { _ in nil }
        WindowLook.refreshAll()
        XCTAssertEqual(windows.map { $0.appearance?.name }, [nil, nil])
    }
}
