import AgentHUDCore
import AppKit
import XCTest
@testable import AgentHUDDesktop

/// Where a screen's look comes from: its settings with any style draft, the hardware notch that keeps the island black,
/// macOS's light or dark setting for a look that matches it, and Reduce Transparency, which draws glass solid.
@MainActor
final class HUDLookResolutionTests: XCTestCase {
    /// The rule itself, with the screen and the Mac given: the default is today's HUD, a notch at a notch stays black
    /// whatever is chosen, a dock or a stand-in bar takes the look, `system` follows macOS and Reduce Transparency
    /// draws glass solid.
    func testTheLookFollowsThePlacementTheNotchMacOSAndReduceTransparency() {
        func look(_ placement: ScreenPlacement, notch: Bool = false, light: Bool = false, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, hasNotch: notch, systemIsLight: light, reducesTransparency: reduces)
        }
        XCTAssertEqual(look(.default(hasNotch: true), notch: true), .standard, "the default is the HUD as it was")
        XCTAssertEqual(look(.default(hasNotch: false)), .standard)

        let chosen = ScreenPlacement(mode: .notch, appearance: .light, material: .glass)
        XCTAssertEqual(look(chosen, notch: true, light: true), .standard, "a notch at a notch stays black")
        XCTAssertEqual(look(chosen), HUDLook(appearance: .light, material: .glass), "the bar standing in for a notch")
        for mode in [HUDMode.logos, .simple] {
            var dock = chosen
            dock.mode = mode
            XCTAssertEqual(look(dock, notch: true), HUDLook(appearance: .light, material: .glass), "\(mode)")
            XCTAssertEqual(look(dock, notch: true, reduces: true), HUDLook(appearance: .light, material: .solid), "\(mode)")
        }

        let system = ScreenPlacement(appearance: .system)
        XCTAssertEqual(look(system, light: true), HUDLook(appearance: .light, material: .solid))
        XCTAssertEqual(look(system, light: false), .standard)
        XCTAssertEqual(look(ScreenPlacement(appearance: .dark), light: true), .standard, "dark stays dark on a light Mac")
        XCTAssertEqual(look(ScreenPlacement(material: .glass)), HUDLook(appearance: .dark, material: .glass))
        XCTAssertEqual(look(ScreenPlacement(material: .glass), reduces: true), .standard)
    }

    /// A screen's look follows its settings and, drawn over them, its style draft. A screen that is not attached counts
    /// as one without a notch, so its notch is the bar that stands in for one.
    func testAScreensLookFollowsItsSettingsAndItsStyleDraft() {
        let suite = "app.agenthud.tests.hud-look-resolution.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
        let key = "screen:away"
        XCTAssertEqual(settings.effectiveLook(on: key), .standard)

        settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, appearance: .light) }
        XCTAssertEqual(settings.effectiveLook(on: key), HUDLook(appearance: .light, material: .solid))
        settings.update { $0.screens[key] = ScreenPlacement(mode: .notch, appearance: .light) }
        XCTAssertEqual(settings.effectiveLook(on: key), HUDLook(appearance: .light, material: .solid),
                       "a screen that is not attached has no notch to keep black")

        settings.panelLayout.proposeStyle(HUDStyle(appearance: .dark), for: key, hasNotch: false)
        XCTAssertEqual(settings.effectiveLook(on: key), .standard, "the style draft is drawn over the settings")
        settings.panelLayout.discardStyle(key)
        XCTAssertEqual(settings.effectiveLook(on: key).appearance, .light)

        // What the Mac is set to now decides the rest.
        settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, material: .glass) }
        let reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        XCTAssertEqual(settings.effectiveLook(on: key).material, reduces ? .solid : .glass)
        settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, appearance: .system) }
        XCTAssertEqual(settings.effectiveLook(on: key).appearance, SystemAppearance.isLight ? .light : .dark,
                       "macOS's own setting, whatever the app's Appearance")
        settings.update { $0.appearance = SystemAppearance.isLight ? .dark : .light }
        XCTAssertEqual(settings.effectiveLook(on: key).appearance, SystemAppearance.isLight ? .light : .dark)
    }
}
