import AgentHUDCore
import AppKit
import XCTest
@testable import AgentHUDDesktop

/// Where a screen's look comes from: its settings with any style draft, macOS's light or dark setting for a look that
/// matches it, and Reduce Transparency, which draws glass solid; the transparency as it is drawn, three fifths of the
/// slider's for Solid, Clear and Regular and all of it for the material, and what its glass is made of for a look of
/// glass; and the dark the island keeps in the row of a hardware notch.
@MainActor
final class HUDLookResolutionTests: XCTestCase {
    /// The rule itself, with the Mac given: the default is today's HUD, every mode takes the look chosen, the notch's
    /// included, `system` follows macOS and Reduce Transparency draws glass solid. Glass chosen first is clear at 50 %,
    /// which it draws at 0.3.
    func testTheLookFollowsThePlacementMacOSAndReduceTransparency() {
        func look(_ placement: ScreenPlacement, light: Bool = false, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: light, reducesTransparency: reduces)
        }
        XCTAssertEqual(look(.default(hasNotch: true)), .standard, "the default is the HUD as it was")
        XCTAssertEqual(look(.default(hasNotch: false)), .standard)

        for mode in HUDMode.allCases {
            let chosen = ScreenPlacement(mode: mode, appearance: .light, material: .glass)
            let glass = HUDLook(appearance: .light, material: .glass, transparency: 0.3)
            XCTAssertEqual(look(chosen, light: true), glass, "\(mode)")
            XCTAssertEqual(look(chosen, reduces: true), HUDLook(appearance: .light, material: .solid), "\(mode)")
        }

        let system = ScreenPlacement(appearance: .system)
        XCTAssertEqual(look(system, light: true), HUDLook(appearance: .light, material: .solid))
        XCTAssertEqual(look(system, light: false), .standard)
        XCTAssertEqual(look(ScreenPlacement(appearance: .dark), light: true), .standard, "dark stays dark on a light Mac")
        XCTAssertEqual(look(ScreenPlacement(material: .glass)), HUDLook(appearance: .dark, material: .glass, transparency: 0.3))
        XCTAssertEqual(look(ScreenPlacement(material: .glass), reduces: true), .standard)
    }

    /// Each material carries its own transparency from the screen, glass's and solid's, as it is drawn, three fifths of
    /// the slider's on clear glass and Solid, and the one it does not draw changes nothing; Reduce Transparency draws
    /// either opaque, the same look as any other opaque one of its colours. Both run to the slider's 1, which they draw
    /// at 0.6.
    func testEachMaterialCarriesItsOwnTransparency() {
        func look(_ placement: ScreenPlacement, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: false, reducesTransparency: reduces)
        }
        XCTAssertEqual(HUDLook.standard.transparency, 0, "the HUD as it was is opaque")
        XCTAssertEqual(ScreenPlacement().solidTransparency, 0)
        for transparency in [0, 0.2, 0.5, 0.9, 1] {
            let drawn = transparency * 0.6
            let glass = ScreenPlacement(appearance: .light, material: .glass, glassTransparency: transparency,
                                        solidTransparency: 0.4)
            XCTAssertEqual(look(glass).transparency, drawn, "\(transparency)")
            XCTAssertEqual(look(glass).dimmingOpacity, 1 - drawn, accuracy: 0.0001,
                           "\(transparency): the glass whole, over what the transparency leaves of its dimming")
            XCTAssertEqual(look(glass), HUDLook(appearance: .light, material: .glass, transparency: drawn))
            XCTAssertEqual(look(glass, reduces: true), HUDLook(appearance: .light), "glass drawn solid is plain solid")

            let solid = ScreenPlacement(material: .solid, glassTransparency: 0.4, solidTransparency: transparency)
            XCTAssertEqual(look(solid), HUDLook(appearance: .dark, transparency: drawn), "\(transparency): solid's own")
            XCTAssertEqual(look(solid, reduces: true), .standard, "Reduce Transparency draws it opaque")
            XCTAssertEqual(look(ScreenPlacement(material: .solid, glassTransparency: transparency)), .standard,
                           "glass's transparency changes nothing on a solid HUD")
        }
        XCTAssertEqual(look(ScreenPlacement(material: .glass, glassTransparency: 1)),
                       HUDLook(appearance: .dark, material: .glass, transparency: 0.6), "glass's top")
        XCTAssertEqual(look(ScreenPlacement(material: .solid, solidTransparency: 1)),
                       HUDLook(appearance: .dark, transparency: 0.6), "solid's top, the same")
        XCTAssertNotEqual(look(ScreenPlacement(material: .glass, glassTransparency: 0.2)),
                          look(ScreenPlacement(material: .glass, glassTransparency: 0.3)),
                          "a change of transparency is a change of look, which the HUD moves to")
    }

    /// The look carries the transparency as it is drawn, and everything it draws follows from that, never from the
    /// slider: the dimming beneath glass, a solid fill, the painted boxes on the ground and the stand-in of a picture.
    /// Clear and regular glass at the slider's top draw 0.6, a dimming of 0.4; the material at the top draws all of it,
    /// the bare material with no dimming; Solid at 50 % draws 0.3, its fill at 0.7; Reduce Transparency draws each
    /// opaque.
    func testTheLookDrawsWhatTheScaledTransparencyLeaves() {
        func look(_ placement: ScreenPlacement, reduces: Bool = false) -> HUDLook {
            HUDLook(drawing: placement, systemIsLight: false, reducesTransparency: reduces)
        }
        for style in [HUDGlassStyle.clear, .regular] {
            let top = look(ScreenPlacement(material: .glass, glassStyle: style, glassTransparency: 1))
            XCTAssertEqual(top.transparency, 0.6, "\(style)")
            XCTAssertEqual(top.dimmingOpacity, 0.4, accuracy: 0.0001, "\(style)")
            XCTAssertEqual(top.coverOpacity, 0, "\(style): no solid cover")
            XCTAssertEqual(top.innerOpacity, 0.52, accuracy: 0.0001, "\(style): a fifth and four fifths of 0.4")
            XCTAssertEqual(top.glassStyle, style)
        }
        let material = look(ScreenPlacement(material: .glass, glassStyle: .material, glassTransparency: 1))
        XCTAssertEqual(material.transparency, 1, "the material, all of it")
        XCTAssertEqual(material.dimmingOpacity, 0, "the bare material")
        XCTAssertEqual(material.innerOpacity, HUDLook.innerFloor, accuracy: 0.0001, "a fifth of a box left")
        XCTAssertEqual(material.glassStandIn, material.theme.glassTint.opacity(HUDLook.standInFloor),
                       "a picture's stand-in at its floor")
        let half = look(ScreenPlacement(material: .glass, glassStyle: .material, glassTransparency: 0.5))
        XCTAssertEqual(half.dimmingOpacity, 0.5, accuracy: 0.0001, "the material at 50 %, half its colour beneath")

        let solid = look(ScreenPlacement(solidTransparency: 0.5))
        XCTAssertEqual(solid.transparency, 0.3, "three fifths of 50 %")
        XCTAssertEqual(solid.coverOpacity, 0.7, accuracy: 0.0001, "its fill")
        XCTAssertEqual(solid.dimmingOpacity, 0, "no glass")
        XCTAssertEqual(solid.innerOpacity, 0.76, accuracy: 0.0001)
        XCTAssertTrue(solid.seeThrough)
        let solidTop = look(ScreenPlacement(glassStyle: .material, solidTransparency: 1))
        XCTAssertEqual(solidTop.transparency, 0.6, "solid's share, whatever glass it keeps")
        XCTAssertEqual(solidTop.coverOpacity, 0.4, accuracy: 0.0001)

        let standard = look(ScreenPlacement(material: .glass))
        XCTAssertEqual(standard.transparency, 0.3, "the standard 50 %, on clear glass")
        XCTAssertEqual(standard.dimmingOpacity, 0.7, accuracy: 0.0001)

        for placement in [ScreenPlacement(material: .glass, glassStyle: .material, glassTransparency: 1),
                          ScreenPlacement(material: .glass, glassTransparency: 1), ScreenPlacement(solidTransparency: 1)] {
            let reduced = look(placement, reduces: true)
            XCTAssertEqual(reduced.transparency, 0, "\(placement.material) \(placement.glassStyle)")
            XCTAssertEqual(reduced.coverOpacity, 1, "\(placement.material) \(placement.glassStyle): opaque")
            XCTAssertEqual(reduced.innerOpacity, 1, "\(placement.material) \(placement.glassStyle)")
            XCTAssertFalse(reduced.seeThrough, "\(placement.material) \(placement.glassStyle)")
        }
    }

    /// The island in the row of a hardware notch is dark in any look, in the look's own material, black or black glass:
    /// the look of a light HUD there is dark, and the standard look is its own row's. A solid row is black, opaque,
    /// whatever solid Transparency the screen chooses, drawn up to 0.6, so that its wings stay one with the camera
    /// housing. Black glass is the screen's own glass, clear, regular or a material, over four fifths of black
    /// (`notchRowTransparency`, 0.2), whatever glass Transparency the screen chooses, drawn up to 0.6, or 1 for the
    /// material, which thins only what opens out of the row: bare glass turns light over a light menu bar, and the row
    /// stays one with the housing.
    func testTheNotchsRowIsDarkInTheLooksMaterial() {
        XCTAssertEqual(HUDLook.standard.inNotchRow, .standard)
        XCTAssertEqual(HUDLook(appearance: .light).inNotchRow, .standard, "black")
        for transparency in [0, 0.3, 0.6] {
            for appearance in [HUDLook.Appearance.dark, .light] {
                let row = HUDLook(appearance: appearance, transparency: transparency).inNotchRow
                XCTAssertEqual(row, .standard, "\(appearance) \(transparency): black, whatever the screen's transparency")
                XCTAssertEqual(row.transparency, 0, "\(appearance) \(transparency)")
                XCTAssertEqual(row.coverOpacity, 1, "\(appearance) \(transparency): its wings opaque")
                XCTAssertFalse(row.seeThrough, "\(appearance) \(transparency)")
            }
        }
        XCTAssertEqual(HUDLook.notchRowTransparency, 0.2)
        for style in HUDGlassStyle.allCases {
            let blackGlass = HUDLook(appearance: .dark, material: .glass, transparency: HUDLook.notchRowTransparency,
                                     glassStyle: style)
            XCTAssertEqual(blackGlass.dimmingOpacity, 0.8, accuracy: 0.0001, "\(style): four fifths of black under it")
            for appearance in [HUDLook.Appearance.dark, .light] {
                for transparency in [0, 0.3, 0.6, 1] {
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
    /// material, and a look of glass carries it whatever its appearance and transparency, which Liquid Glass draws at
    /// three fifths and the material whole: a change of it is a change of look, which the HUD moves to. Reduce Transparency draws glass of any make solid and opaque, its fill whole with
    /// no dimming layer. A look drawn solid, by Reduce Transparency or by the screen's own Solid, carries no glass, clear
    /// whatever the screen keeps for when glass is chosen again, so that it is the same look as any solid one of its
    /// colours.
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
                               HUDLook(appearance: drawn, material: .glass,
                                       transparency: style == .material ? 0.3 : 0.3 * 0.6, glassStyle: style),
                               "\(appearance) \(style)")
                let reduced = look(glass, reduces: true)
                XCTAssertEqual(reduced.appearance, drawn, "\(appearance) \(style)")
                XCTAssertEqual(reduced.material, .solid, "\(appearance) \(style): Reduce Transparency draws it solid")
                XCTAssertEqual(reduced.transparency, 0, "\(appearance) \(style)")
                XCTAssertEqual(reduced.coverOpacity, 1, "\(appearance) \(style): opaque")
                XCTAssertEqual(reduced.dimmingOpacity, 0, "\(appearance) \(style)")
                XCTAssertFalse(reduced.seeThrough, "\(appearance) \(style)")
                XCTAssertEqual(reduced.glassStyle, .clear, "\(appearance) \(style): no glass to be made of")
                XCTAssertEqual(reduced, HUDLook(appearance: drawn), "\(appearance) \(style)")

                let solid = ScreenPlacement(appearance: appearance, material: .solid, glassStyle: style,
                                            solidTransparency: 0.3)
                XCTAssertEqual(look(solid).glassStyle, .clear, "\(appearance) \(style): solid carries no glass")
                XCTAssertEqual(look(solid), HUDLook(appearance: drawn, transparency: 0.3 * 0.6),
                               "\(appearance) \(style): solid's share, whatever glass it keeps")
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

    /// A screen of glass gives its look the transparency it has saved, or its style draft's, as its glass draws it,
    /// three fifths of it for regular glass and all of it for the material, unless Reduce Transparency draws it solid
    /// and opaque, and what its glass is made of, which a style draft leaves as it is: an agent cannot choose it.
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
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.2 * 0.6)
        XCTAssertEqual(settings.effectiveLook(on: key).glassStyle, .regular)
        settings.panelLayout.proposeStyle(HUDStyle(transparency: 0.7), for: key, hasNotch: false)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.7 * 0.6,
                       "the style draft is drawn over the settings")
        XCTAssertEqual(settings.effectiveLook(on: key).glassStyle, .regular, "the draft keeps the screen's glass")
        settings.panelLayout.discardStyle(key)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.2 * 0.6)
        settings.update { $0.screens[key]?.glassStyle = .material }
        XCTAssertEqual(settings.effectiveLook(on: key).glassStyle, .material)
        XCTAssertEqual(settings.effectiveLook(on: key).transparency, reduces ? 0 : 0.2, "the material draws all of it")
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
