import AgentHUDCore
import AppKit
import XCTest
@testable import AgentHUDDesktop

/// Where a screen's look comes from: its settings with any style draft, macOS's light or dark setting for a look that
/// matches it, and Reduce Transparency, which draws glass solid; glass's transparency for a look of glass; and the dark
/// the island keeps in the row of a hardware notch.
@MainActor
final class HUDLookResolutionTests: XCTestCase {
    /// The rule itself, with the Mac given: the default is today's HUD, every mode takes the look chosen, the notch's
    /// included, `system` follows macOS and Reduce Transparency draws glass solid.
    func testTheLookFollowsThePlacementMacOSAndReduceTransparency() {
        func look(_ placement: ScreenPlacement, light: Bool = false, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: light, reducesTransparency: reduces)
        }
        XCTAssertEqual(look(.default(hasNotch: true)), .standard, "the default is the HUD as it was")
        XCTAssertEqual(look(.default(hasNotch: false)), .standard)

        for mode in HUDMode.allCases {
            let chosen = ScreenPlacement(mode: mode, appearance: .light, material: .glass)
            XCTAssertEqual(look(chosen, light: true), HUDLook(appearance: .light, material: .glass), "\(mode)")
            XCTAssertEqual(look(chosen, reduces: true), HUDLook(appearance: .light, material: .solid), "\(mode)")
        }

        let system = ScreenPlacement(appearance: .system)
        XCTAssertEqual(look(system, light: true), HUDLook(appearance: .light, material: .solid))
        XCTAssertEqual(look(system, light: false), .standard)
        XCTAssertEqual(look(ScreenPlacement(appearance: .dark), light: true), .standard, "dark stays dark on a light Mac")
        XCTAssertEqual(look(ScreenPlacement(material: .glass)), HUDLook(appearance: .dark, material: .glass))
        XCTAssertEqual(look(ScreenPlacement(material: .glass), reduces: true), .standard)
    }

    /// A look of glass carries the screen's transparency; a solid look, Reduce Transparency's included, carries the
    /// standard one whatever the screen keeps for glass, so it is the same look as any other solid one of its colours.
    func testOnlyGlassCarriesTheScreensTransparency() {
        func look(_ placement: ScreenPlacement, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: false, reducesTransparency: reduces)
        }
        XCTAssertEqual(HUDLook.standard.transparency, ScreenPlacement.standardGlassTransparency)
        for transparency in [0, 0.2, 0.9] {
            let glass = ScreenPlacement(appearance: .light, material: .glass, glassTransparency: transparency)
            XCTAssertEqual(look(glass).transparency, transparency)
            XCTAssertEqual(look(glass), HUDLook(appearance: .light, material: .glass, transparency: transparency))
            XCTAssertEqual(look(glass, reduces: true), HUDLook(appearance: .light), "glass drawn solid is plain solid")
            XCTAssertEqual(look(glass, reduces: true).transparency, ScreenPlacement.standardGlassTransparency)

            let solid = ScreenPlacement(material: .solid, glassTransparency: transparency)
            XCTAssertEqual(look(solid), .standard, "a solid look compares equal whatever glass would have")
        }
        XCTAssertNotEqual(look(ScreenPlacement(material: .glass, glassTransparency: 0.2)),
                          look(ScreenPlacement(material: .glass, glassTransparency: 0.3)),
                          "a change of transparency is a change of look, which the HUD moves to")
    }

    /// The island in the row of a hardware notch is dark in any look, in the look's own material and at its
    /// transparency, black or black glass: the look of a light HUD there is dark, and the standard look is its own row's.
    func testTheNotchsRowIsDarkInTheLooksMaterial() {
        XCTAssertEqual(HUDLook.standard.inNotchRow, .standard)
        XCTAssertEqual(HUDLook(appearance: .light).inNotchRow, .standard, "black")
        XCTAssertEqual(HUDLook(appearance: .light, material: .glass, transparency: 0.3).inNotchRow,
                       HUDLook(appearance: .dark, material: .glass, transparency: 0.3), "black glass")
        XCTAssertEqual(HUDLook(appearance: .dark, material: .glass, transparency: 0.7).inNotchRow,
                       HUDLook(appearance: .dark, material: .glass, transparency: 0.7))
        XCTAssertEqual(HUDLook(appearance: .light, material: .glass).inNotchRow.theme.text, Theme.island.text,
                       "the dark island's ink")
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
                       "the notch takes the look as every mode does")

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

    /// A screen of glass gives its look the transparency it has saved, or its style draft's, unless Reduce Transparency
    /// draws it solid.
    func testAScreensGlassTakesItsTransparencyAndItsDrafts() {
        let suite = "app.agenthud.tests.hud-look-resolution.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
        let key = "screen:away"
        let reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 0.2) }
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? ScreenPlacement.standardGlassTransparency : 0.2)
        settings.panelLayout.proposeStyle(HUDStyle(transparency: 0.7), for: key, hasNotch: false)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? ScreenPlacement.standardGlassTransparency : 0.7,
                       "the style draft is drawn over the settings")
        settings.panelLayout.discardStyle(key)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? ScreenPlacement.standardGlassTransparency : 0.2)
    }

    /// A picture or a preview of the resting HUD draws the island in Notch mode at a hardware notch in the standard look,
    /// black, as it rests there in any look (`NotchInk`), and every other resting HUD in its screen's look: a dock on a
    /// notched display, and a screen without a notch, a screen that is not attached among them.
    func testTheRestingLookIsTheStandardOneAtAHardwareNotch() {
        let suite = "app.agenthud.tests.hud-look-resolution.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
        let away = "screen:away"
        settings.update { $0.screens[away] = ScreenPlacement(mode: .notch, appearance: .light, material: .glass) }
        XCTAssertEqual(settings.restingLook(on: away), settings.effectiveLook(on: away), "a screen not attached has no notch")
        XCTAssertEqual(settings.restingLook(on: away).appearance, .light)

        // Every display this Mac has attached, a notched one or not.
        for display in NSScreen.screens {
            let key = ScreenIdentity.key(for: display), notched = ScreenIdentity.hasNotch(display)
            for mode in HUDMode.allCases where mode != .notch || notched {
                settings.update { $0.screens[key] = ScreenPlacement(mode: mode, appearance: .light, material: .glass) }
                let look = settings.effectiveLook(on: key)
                XCTAssertEqual(look.appearance, .light, "\(mode): the screen's look is its own")
                XCTAssertEqual(settings.restingLook(on: key), notched && mode == .notch ? .standard : look,
                               "\(mode) on \(key)")
            }
        }
    }
}
