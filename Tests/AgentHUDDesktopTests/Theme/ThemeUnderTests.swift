import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// What lies on a ground the desktop shows through (`Theme.under(_:)`): the boxes painted on it, cards, rows and inputs,
/// thin as the ground does (`HUDLook.innerOpacity`), so that a light card lets the glass or the desktop through as a dark
/// card's tint of white does; light glass inks its secondary and tertiary text a grade darker; and on an opaque ground,
/// or with no look at all, every token is as it is.
@MainActor
final class ThemeUnderTests: XCTestCase {
    // MARK: How much of a box is drawn

    /// A box is drawn whole on an opaque ground, and on one the desktop shows through it keeps a fifth and four fifths
    /// of what the transparency drawn leaves: 0.76 at the standard glass's 0.3, clear glass at 50 %, 0.52 at the 0.6
    /// that Solid, Clear and Regular draw at their top, and the fifth alone at the material's top of 1, never under it.
    /// Glass is see-through at any transparency, so at 0 its boxes are whole too; a solid ground thins them as glass
    /// does.
    func testABoxKeepsAFifthAndFourFifthsOfWhatTheGroundLeaves() {
        XCTAssertEqual(HUDLook.innerFloor, 0.2)
        XCTAssertEqual(HUDLook.standard.innerOpacity, 1, "the HUD as it was")
        XCTAssertEqual(HUDLook(appearance: .light).innerOpacity, 1, "an opaque light ground")
        for appearance in [HUDLook.Appearance.dark, .light] {
            for material in [HUDLook.Material.glass, .solid] {
                let what = "\(appearance) \(material)"
                for (transparency, share) in [(0.0, 1.0), (0.3, 0.76), (0.6, 0.52), (1, 0.2)] {
                    let look = HUDLook(appearance: appearance, material: material, transparency: transparency)
                    XCTAssertEqual(look.innerOpacity, share, accuracy: 0.0001, "\(what) \(transparency)")
                }
                for transparency in stride(from: 0.0, through: 1, by: 0.1) {
                    let look = HUDLook(appearance: appearance, material: material, transparency: transparency)
                    XCTAssertGreaterThanOrEqual(look.innerOpacity, HUDLook.innerFloor, "\(what) \(transparency)")
                    XCTAssertLessThanOrEqual(look.innerOpacity, 1, "\(what) \(transparency)")
                }
            }
        }
        XCTAssertTrue(HUDLook(appearance: .dark, material: .glass).seeThrough, "glass at 0 is still glass")
        XCTAssertFalse(HUDLook(appearance: .light).seeThrough, "a solid ground at 0 is opaque")
        let standard = HUDLook(drawing: ScreenPlacement(appearance: .light, material: .glass), systemIsLight: false,
                               reducesTransparency: false)
        XCTAssertEqual(standard.innerOpacity, 0.76, accuracy: 0.0001, "glass as a screen first has it")
    }

    // MARK: The tokens on it

    /// On a light ground the desktop shows through, a card, a row and an input are the light tokens' white at the share
    /// the look leaves of them, solid or glass, the light window's and the light HUD's alike; what is not a painted box,
    /// the ink, the hairlines and the window's own background, is as it was.
    func testALightGroundThinsItsCardsRowsAndInputs() throws {
        let looks = [HUDLook(appearance: .light, transparency: 0.3),
                     HUDLook(appearance: .light, material: .glass, transparency: 0.3),
                     HUDLook(appearance: .light, material: .glass, transparency: 1, glassStyle: .material)]
        for base in [("the light window", Theme.light), ("the light HUD", Theme.lightIsland)] {
            for look in looks {
                let what = "\(base.0) under \(look.material) at \(look.transparency)"
                let theme = base.1.under(look), share = look.innerOpacity
                XCTAssertLessThan(share, 1, what)
                XCTAssertEqual(theme.card, base.1.card.opacity(share), what)
                XCTAssertEqual(theme.rowBackground, base.1.rowBackground.opacity(share), what)
                XCTAssertEqual(theme.inputBackground, base.1.inputBackground.opacity(share), what)
                XCTAssertEqual(theme.text, base.1.text, what)
                XCTAssertEqual(theme.cardBorder, base.1.cardBorder, what)
                XCTAssertEqual(theme.rowBorder, base.1.rowBorder, what)
                XCTAssertEqual(theme.windowBackground, base.1.windowBackground, what)
                XCTAssertEqual(theme.sessionRowBackground, base.1.sessionRowBackground, what)
            }
        }
        let card = try XCTUnwrap(NSColor(Theme.light.under(looks[1]).card).usingColorSpace(.sRGB))
        XCTAssertEqual(card.alphaComponent, 0.76, accuracy: 0.002, "0.76 of the white card at the standard 0.3")
        let top = try XCTUnwrap(NSColor(Theme.light.under(looks[2]).card).usingColorSpace(.sRGB))
        XCTAssertEqual(top.alphaComponent, 0.2, accuracy: 0.002, "a fifth of it at the material's top")
    }

    /// The dark tokens' cards and rows are tints of white already, which the desktop shows through, so a dark ground
    /// leaves them as they are; only the input, an opaque near-black box, thins with the ground.
    func testADarkGroundThinsOnlyItsInputs() {
        for look in [HUDLook(appearance: .dark, transparency: 0.3), HUDLook(appearance: .dark, material: .glass, transparency: 0.3),
                     HUDLook(appearance: .dark, material: .glass, transparency: 0.6, glassStyle: .regular)] {
            let what = "\(look.material) at \(look.transparency)"
            let theme = Theme.dark.under(look)
            XCTAssertEqual(theme.card, Theme.dark.card, what)
            XCTAssertEqual(theme.rowBackground, Theme.dark.rowBackground, what)
            XCTAssertEqual(theme.inputBackground, Theme.dark.inputBackground.opacity(look.innerOpacity), what)
            XCTAssertEqual(theme.secondary, Theme.dark.secondary, what)
            XCTAssertEqual(theme.tertiary, Theme.dark.tertiary, what)
        }
    }

    /// Light glass inks its secondary and tertiary text a grade darker, light glass's own, at any transparency, 0
    /// included, on the light window's tokens as on the HUD's; a light solid ground and dark glass keep their ink.
    func testLightGlassInksItsGreysAGradeDarker() {
        for transparency in [0, 0.3, 0.6, 1] {
            let glass = HUDLook(appearance: .light, material: .glass, transparency: transparency)
            for base in [Theme.light, Theme.lightIsland] {
                XCTAssertEqual(base.under(glass).secondary, Theme.lightGlass.secondary, "\(transparency)")
                XCTAssertEqual(base.under(glass).tertiary, Theme.lightGlass.tertiary, "\(transparency)")
                XCTAssertEqual(base.under(glass).text, base.text, "\(transparency): the main ink is the same")
            }
            let solid = HUDLook(appearance: .light, transparency: transparency)
            XCTAssertEqual(Theme.light.under(solid).secondary, Theme.light.secondary, "\(transparency): solid")
            XCTAssertEqual(Theme.light.under(solid).tertiary, Theme.light.tertiary, "\(transparency): solid")
            let dark = HUDLook(appearance: .dark, material: .glass, transparency: transparency)
            XCTAssertEqual(Theme.dark.under(dark).secondary, Theme.dark.secondary, "\(transparency): dark glass")
        }
        XCTAssertNotEqual(Theme.lightGlass.secondary, Theme.light.secondary)
        XCTAssertNotEqual(Theme.lightGlass.tertiary, Theme.light.tertiary)
    }

    /// With no look, as a window takes with Match screen off, and on an opaque ground, a solid one with no transparency
    /// or the standard look, the tokens are as they are.
    func testNoLookOrAnOpaqueOneChangesNothing() {
        for (name, look) in [("no look", nil), ("the standard look", HUDLook.standard),
                             ("an opaque light look", HUDLook(appearance: .light))] as [(String, HUDLook?)] {
            for base in [Theme.light, Theme.dark, Theme.lightIsland] {
                let theme = base.under(look)
                XCTAssertEqual(theme.card, base.card, name)
                XCTAssertEqual(theme.rowBackground, base.rowBackground, name)
                XCTAssertEqual(theme.inputBackground, base.inputBackground, name)
                XCTAssertEqual(theme.secondary, base.secondary, name)
                XCTAssertEqual(theme.tertiary, base.tertiary, name)
            }
        }
    }

    /// The HUD's own tokens are its theme on its own ground: a light HUD's request cards thin with the look, and the
    /// standard look's are the island's as they always were.
    func testTheHUDsThemeIsItsTokensOnItsOwnGround() {
        let glass = HUDLook(appearance: .light, material: .glass, transparency: 0.5)
        XCTAssertEqual(glass.theme.card, Theme.lightGlass.card.opacity(glass.innerOpacity))
        XCTAssertEqual(glass.theme.secondary, Theme.lightGlass.secondary)
        let solid = HUDLook(appearance: .light, transparency: 0.3)
        XCTAssertEqual(solid.theme.card, Theme.lightIsland.card.opacity(solid.innerOpacity))
        XCTAssertEqual(solid.theme.secondary, Theme.lightIsland.secondary)
        XCTAssertEqual(HUDLook(appearance: .light).theme.card, Theme.lightIsland.card, "opaque, white")
        XCTAssertEqual(HUDLook.standard.theme.card, Theme.island.card)
        XCTAssertEqual(HUDLook.standard.theme.inputBackground, Theme.island.inputBackground)
        let darkGlass = HUDLook(appearance: .dark, material: .glass, transparency: 0.5)
        XCTAssertEqual(darkGlass.theme.card, Theme.island.card, "a tint of white already")
        XCTAssertEqual(darkGlass.theme.inputBackground, Theme.island.inputBackground.opacity(darkGlass.innerOpacity))
    }
}
