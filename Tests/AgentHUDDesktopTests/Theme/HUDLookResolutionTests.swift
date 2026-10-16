import AgentHUDCore
import AppKit
import XCTest
@testable import AgentHUDDesktop

/// Where a screen's look comes from: its settings with any style draft, macOS's light or dark setting for a look that
/// matches it, and Reduce Transparency, which draws glass solid; glass's transparency and what its glass is made of for
/// a look of glass; and the dark the island keeps in the row of a hardware notch.
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
            let glass = HUDLook(appearance: .light, material: .glass,
                                transparency: ScreenPlacement.standardGlassTransparency)
            XCTAssertEqual(look(chosen, light: true), glass, "\(mode)")
            XCTAssertEqual(look(chosen, reduces: true), HUDLook(appearance: .light, material: .solid), "\(mode)")
        }

        let system = ScreenPlacement(appearance: .system)
        XCTAssertEqual(look(system, light: true), HUDLook(appearance: .light, material: .solid))
        XCTAssertEqual(look(system, light: false), .standard)
        XCTAssertEqual(look(ScreenPlacement(appearance: .dark), light: true), .standard, "dark stays dark on a light Mac")
        XCTAssertEqual(look(ScreenPlacement(material: .glass)),
                       HUDLook(appearance: .dark, material: .glass, transparency: ScreenPlacement.standardGlassTransparency))
        XCTAssertEqual(look(ScreenPlacement(material: .glass), reduces: true), .standard)
    }

    /// Each material carries its own transparency from the screen, glass's and solid's, and the one it does not draw
    /// changes nothing; Reduce Transparency draws either opaque, the same look as any other opaque one of its colours.
    /// Glass's runs to 1, solid's stops at 0.9, whatever was saved.
    func testEachMaterialCarriesItsOwnTransparency() {
        func look(_ placement: ScreenPlacement, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: false, reducesTransparency: reduces)
        }
        XCTAssertEqual(HUDLook.standard.transparency, 0, "the HUD as it was is opaque")
        XCTAssertEqual(ScreenPlacement().solidTransparency, 0)
        for transparency in [0, 0.2, 0.9] {
            let glass = ScreenPlacement(appearance: .light, material: .glass, glassTransparency: transparency,
                                        solidTransparency: 0.4)
            XCTAssertEqual(look(glass).transparency, transparency)
            XCTAssertEqual(look(glass).dimmingOpacity, 1 - transparency, accuracy: 0.0001,
                           "the glass whole, over what the transparency leaves of its dimming")
            XCTAssertEqual(look(glass), HUDLook(appearance: .light, material: .glass, transparency: transparency))
            XCTAssertEqual(look(glass, reduces: true), HUDLook(appearance: .light), "glass drawn solid is plain solid")

            let solid = ScreenPlacement(material: .solid, glassTransparency: 0.4, solidTransparency: transparency)
            XCTAssertEqual(look(solid), HUDLook(appearance: .dark, transparency: transparency), "solid's own")
            XCTAssertEqual(look(solid, reduces: true), .standard, "Reduce Transparency draws it opaque")
            XCTAssertEqual(look(ScreenPlacement(material: .solid, glassTransparency: transparency)), .standard,
                           "glass's transparency changes nothing on a solid HUD")
        }
        XCTAssertEqual(look(ScreenPlacement(material: .glass, glassTransparency: 1)),
                       HUDLook(appearance: .dark, material: .glass, transparency: 1), "glass's own top")
        XCTAssertEqual(look(ScreenPlacement(material: .solid, solidTransparency: 1)),
                       HUDLook(appearance: .dark, transparency: 0.9), "solid's own top")
        XCTAssertNotEqual(look(ScreenPlacement(material: .glass, glassTransparency: 0.2)),
                          look(ScreenPlacement(material: .glass, glassTransparency: 0.3)),
                          "a change of transparency is a change of look, which the HUD moves to")
    }

    /// The island in the row of a hardware notch is dark in any look, in the look's own material, black or black glass:
    /// the look of a light HUD there is dark, and the standard look is its own row's. A solid row keeps the screen's
    /// transparency, which leaves at least half of its black. Black glass is the screen's own glass, clear, regular or
    /// a material, over four fifths of black (`notchRowTransparency`, 0.2), whatever Transparency the screen chooses, 0
    /// to 1, which thins only what opens out of the row: bare glass turns light over a light menu bar, and the row
    /// stays one with the camera housing.
    func testTheNotchsRowIsDarkInTheLooksMaterial() {
        XCTAssertEqual(HUDLook.standard.inNotchRow, .standard)
        XCTAssertEqual(HUDLook(appearance: .light).inNotchRow, .standard, "black")
        XCTAssertEqual(HUDLook(appearance: .light, transparency: 0.4).inNotchRow,
                       HUDLook(appearance: .dark, transparency: 0.4), "black at the screen's solid transparency")
        XCTAssertEqual(HUDLook.notchRowTransparency, 0.2)
        for style in HUDGlassStyle.allCases {
            let blackGlass = HUDLook(appearance: .dark, material: .glass, transparency: HUDLook.notchRowTransparency,
                                     glassStyle: style)
            XCTAssertEqual(blackGlass.dimmingOpacity, 0.8, accuracy: 0.0001, "\(style): four fifths of black under it")
            for appearance in [HUDLook.Appearance.dark, .light] {
                for transparency in [0, 0.3, 0.7, 1] {
                    let screen = HUDLook(appearance: appearance, material: .glass, transparency: transparency,
                                         glassStyle: style)
                    XCTAssertEqual(screen.inNotchRow, blackGlass, "\(appearance) \(style) \(transparency): black glass")
                }
            }
        }
        XCTAssertEqual(HUDLook(appearance: .light, material: .glass).inNotchRow.theme.text, Theme.island.text,
                       "the dark island's ink")
    }

    /// A screen's glass is what its settings make it, clear Liquid Glass unless they choose the regular one or a
    /// material, and a look of glass carries it whatever its appearance and transparency: a change of it is a change of
    /// look, which the HUD moves to. Reduce Transparency draws glass of any make solid and opaque, its fill whole with
    /// no dimming layer.
    func testTheLookCarriesWhatTheScreensGlassIsMadeOf() {
        func look(_ placement: ScreenPlacement, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: false, reducesTransparency: reduces)
        }
        XCTAssertEqual(ScreenPlacement().glassStyle, .clear)
        XCTAssertEqual(HUDLook.standard.glassStyle, .clear)
        XCTAssertEqual(look(ScreenPlacement(material: .glass)).glassStyle, .clear, "clear unless chosen otherwise")
        for style in HUDGlassStyle.allCases {
            for (appearance, drawn) in [(HUDAppearance.dark, HUDLook.Appearance.dark), (.light, .light)] {
                let glass = ScreenPlacement(appearance: appearance, material: .glass, glassStyle: style,
                                            glassTransparency: 0.3)
                XCTAssertEqual(look(glass),
                               HUDLook(appearance: drawn, material: .glass, transparency: 0.3, glassStyle: style),
                               "\(appearance) \(style)")
                let reduced = look(glass, reduces: true)
                XCTAssertEqual(reduced.appearance, drawn, "\(appearance) \(style)")
                XCTAssertEqual(reduced.material, .solid, "\(appearance) \(style): Reduce Transparency draws it solid")
                XCTAssertEqual(reduced.transparency, 0, "\(appearance) \(style)")
                XCTAssertEqual(reduced.coverOpacity, 1, "\(appearance) \(style): opaque")
                XCTAssertEqual(reduced.dimmingOpacity, 0, "\(appearance) \(style)")
                XCTAssertFalse(reduced.seeThrough, "\(appearance) \(style)")
            }
        }
        XCTAssertNotEqual(look(ScreenPlacement(material: .glass, glassStyle: .clear)),
                          look(ScreenPlacement(material: .glass, glassStyle: .regular)))
        XCTAssertNotEqual(look(ScreenPlacement(material: .glass, glassStyle: .regular)),
                          look(ScreenPlacement(material: .glass, glassStyle: .material)))
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
    /// draws it solid and opaque, and what its glass is made of, which a style draft leaves as it is: an agent cannot
    /// choose it.
    func testAScreensGlassTakesItsTransparencyAndItsDrafts() {
        let suite = "app.agenthud.tests.hud-look-resolution.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
        let key = "screen:away"
        let reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        settings.update {
            $0.screens[key] = ScreenPlacement(mode: .simple, material: .glass, glassStyle: .regular,
                                              glassTransparency: 0.2)
        }
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.2)
        XCTAssertEqual(settings.effectiveLook(on: key).glassStyle, .regular)
        settings.panelLayout.proposeStyle(HUDStyle(transparency: 0.7), for: key, hasNotch: false)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.7,
                       "the style draft is drawn over the settings")
        XCTAssertEqual(settings.effectiveLook(on: key).glassStyle, .regular, "the draft keeps the screen's glass")
        settings.panelLayout.discardStyle(key)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.2)
        settings.update { $0.screens[key]?.glassStyle = .material }
        XCTAssertEqual(settings.effectiveLook(on: key).glassStyle, .material)
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
