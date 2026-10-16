import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// What lies on a ground the desktop shows through (`Theme.under(_:)`): the boxes painted on it, cards, rows and inputs,
/// thin as the ground does (`HUDLook.innerOpacity`), so that a light card lets the glass or the desktop through as a dark
/// card's tint of white does; the greys are tints of the ink that give today's greys on the look's own colour, a grade
/// darker on light glass; levels and accents as text take see-through shades; and on an opaque ground, or with no look
/// at all, every token is as it is.
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
    /// the main ink, the hairlines and the window's own background, is as it was, and a hovered session's tint is twice
    /// as strong, since a tint's step shrinks as the ground darkens toward the ink.
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
                XCTAssertEqual(theme.sessionRowBackground, Color.black.opacity(0.06), "\(what): a hover twice as strong")
            }
        }
        let card = try XCTUnwrap(NSColor(Theme.light.under(looks[1]).card).usingColorSpace(.sRGB))
        XCTAssertEqual(card.alphaComponent, 0.76, accuracy: 0.002, "0.76 of the white card at the standard 0.3")
        let top = try XCTUnwrap(NSColor(Theme.light.under(looks[2]).card).usingColorSpace(.sRGB))
        XCTAssertEqual(top.alphaComponent, 0.2, accuracy: 0.002, "a fifth of it at the material's top")
    }

    /// The dark tokens' cards and rows are tints of white already, which the desktop shows through, so a dark ground
    /// leaves them as they are; only the input, an opaque near-black box, thins with the ground. Its greys are tints of
    /// white: a window's those that give its greys on #282828, the HUD's those that give them on black.
    func testADarkGroundThinsOnlyItsInputs() {
        for look in [HUDLook(appearance: .dark, transparency: 0.3), HUDLook(appearance: .dark, material: .glass, transparency: 0.3),
                     HUDLook(appearance: .dark, material: .glass, transparency: 0.6, glassStyle: .regular)] {
            let what = "\(look.material) at \(look.transparency)"
            let theme = Theme.dark.under(look)
            XCTAssertEqual(theme.card, Theme.dark.card, what)
            XCTAssertEqual(theme.rowBackground, Theme.dark.rowBackground, what)
            XCTAssertEqual(theme.inputBackground, Theme.dark.inputBackground.opacity(look.innerOpacity), what)
            XCTAssertEqual(theme.secondary, Color.white.opacity(0.52), what)
            XCTAssertEqual(theme.tertiary, Color.white.opacity(0.33), what)
            XCTAssertEqual(Theme.island.under(look).secondary, Color.white.opacity(0.60), what)
            XCTAssertEqual(Theme.island.under(look).tertiary, Color.white.opacity(0.43), what)
        }
    }

    /// Light glass inks its secondary and tertiary text a grade darker than a light solid ground, at any transparency,
    /// 0 included, on the light window's tokens as on the HUD's; a light solid ground the desktop shows through tints
    /// its own greys, and an opaque one keeps them.
    func testLightGlassInksItsGreysAGradeDarker() {
        for transparency in [0, 0.3, 0.6, 1] {
            let glass = HUDLook(appearance: .light, material: .glass, transparency: transparency)
            for base in [Theme.light, Theme.lightIsland] {
                XCTAssertEqual(base.under(glass).secondary, Color.black.opacity(0.65), "\(transparency)")
                XCTAssertEqual(base.under(glass).tertiary, Color.black.opacity(0.53), "\(transparency)")
                XCTAssertEqual(base.under(glass).text, base.text, "\(transparency): the main ink is the same")
            }
            let solid = HUDLook(appearance: .light, transparency: transparency)
            let tinted = transparency > 0
            XCTAssertEqual(Theme.light.under(solid).secondary,
                           tinted ? Color.black.opacity(0.55) : Theme.light.secondary, "\(transparency): solid")
            XCTAssertEqual(Theme.light.under(solid).tertiary,
                           tinted ? Color.black.opacity(0.42) : Theme.light.tertiary, "\(transparency): solid")
        }
    }

    /// Each grey on a ground the desktop shows through is a tint of the ink that, laid over the look's own colour, is
    /// the grey drawn on the opaque ground, to within 2 levels of its red and green (the tints are neutral, so the
    /// few levels of blue in #98989d and #6e6e73 are gone), so that nothing moves as the slider leaves 0: on a dark
    /// window's #282828 page and #1f1f1f sidebar, on the HUD's black, on the light #f5f5f7, and on light glass, whose
    /// greys are #55555a and #737378. The idle grey is the secondary's on dark and #9a9aa0 on light.
    func testEachTintOverItsLooksColourIsTodaysGrey() throws {
        struct Case {
            let name: String
            let theme: Theme
            let page: UInt32
            let greys: [(String, KeyPath<Theme, Color>, UInt32)]
        }
        let darkGlass = HUDLook(appearance: .dark, material: .glass, transparency: 0.3)
        let lightSolid = HUDLook(appearance: .light, transparency: 0.3)
        let lightGlass = HUDLook(appearance: .light, material: .glass, transparency: 0.3)
        let dark: [(String, KeyPath<Theme, Color>, UInt32)] = [
            ("secondary", \.secondary, 0x98989d), ("tertiary", \.tertiary, 0x6e6e73), ("dotEnded", \.dotEnded, 0x6e6e73),
            ("idle", \.idle, 0x98989d), ("idleText", \.idleText, 0x98989d)]
        let cases = [
            Case(name: "a dark window", theme: Theme.dark.under(darkGlass), page: 0x282828, greys: dark),
            Case(name: "a dark solid window", theme: Theme.dark.under(HUDLook(appearance: .dark, transparency: 0.3)),
                 page: 0x282828, greys: dark),
            Case(name: "the dark HUD", theme: darkGlass.theme, page: 0x000000, greys: dark),
            Case(name: "the light window", theme: Theme.light.under(lightSolid), page: 0xf5f5f7, greys: [
                ("secondary", \.secondary, 0x6e6e73), ("tertiary", \.tertiary, 0x8e8e93), ("dotEnded", \.dotEnded, 0xaeaeb2),
                ("idle", \.idle, 0x9a9aa0), ("idleText", \.idleText, 0x6e6e73)]),
            Case(name: "light glass", theme: lightGlass.theme, page: 0xf5f5f7, greys: [
                ("secondary", \.secondary, 0x55555a), ("tertiary", \.tertiary, 0x737378), ("dotEnded", \.dotEnded, 0xaeaeb2),
                ("idle", \.idle, 0x9a9aa0), ("idleText", \.idleText, 0x55555a)]),
        ]
        for item in cases {
            XCTAssertTrue(item.theme.isSeeThrough, item.name)
            for (name, path, grey) in item.greys {
                try assertTint(item.theme[keyPath: path], over: item.page, gives: grey, "\(item.name)'s \(name)")
            }
        }
        try assertTint(Theme.dark.under(darkGlass).sidebarText, over: 0x1f1f1f, gives: 0xd0d0d5, "a dark sidebar's names")
        XCTAssertEqual(Theme.light.under(lightSolid).sidebarText, Theme.light.sidebarText, "the light sidebar's main ink")
    }

    /// A chosen segment is a tint of white a step over its track's on a dark ground, so that the two never run
    /// together, from black to a ground as light as glass over a white desktop can make it.
    func testTheChosenSegmentStaysLighterThanItsTrackOnAnyDarkGround() throws {
        let selected = try sRGB(Theme.dark.segmentSelected), track = try sRGB(Theme.dark.segmentBackground)
        XCTAssertEqual(selected.red, 1, accuracy: 0.002, "a tint of white")
        for ground in stride(from: 0.0, through: 0.8, by: 0.05) {
            let chosen = selected.red * selected.alpha + ground * (1 - selected.alpha)
            let under = track.red * track.alpha + ground * (1 - track.alpha)
            XCTAssertGreaterThan(chosen - under, 0.03, "on \(ground)")
        }
    }

    /// On a ground the desktop shows through, a level and an alert's accent as text take their see-through shades,
    /// paler on dark and deeper on light, while the fills keep their hues; the faint tints that mark a state are
    /// stronger; on an opaque ground each is as it was.
    func testSeeThroughShadesForTextAndStateTints() {
        let dark = Theme.island.under(HUDLook(appearance: .dark, material: .glass, transparency: 0.3))
        let light = Theme.lightIsland.under(HUDLook(appearance: .light, transparency: 0.3))
        for level in StatusLevel.allCases {
            XCTAssertEqual(dark.statusText(level), Color(StatusPalette.seeThroughTextColor(for: level, light: false)), "\(level)")
            XCTAssertEqual(light.statusText(level), Color(StatusPalette.seeThroughTextColor(for: level, light: true)), "\(level)")
            XCTAssertEqual(dark.status(level), Theme.island.status(level), "\(level): the fill keeps its hue")
            XCTAssertEqual(light.status(level), Theme.lightIsland.status(level), "\(level): the fill keeps its hue")
            XCTAssertEqual(HUDLook.standard.theme.statusText(level), Theme.island.statusText(level), "\(level)")
        }
        XCTAssertEqual(dark.alertTurnText, Color(hex: 0xb8cfff))
        XCTAssertEqual(light.alertWarningText, Color(hex: 0x7c3b12))
        XCTAssertEqual(dark.alertTurnFill, Theme.island.alertTurnFill, "the fill keeps its hue")
        XCTAssertEqual(light.alertCalmFill, Theme.lightIsland.alertCalmFill, "the fill keeps its hue")
        XCTAssertEqual(Theme.island.alertTurnText, Theme.island.alertTurnFill, "opaque, the accent itself")
        XCTAssertEqual(dark.sessionRowBackground, Color.white.opacity(0.08))
        XCTAssertEqual(light.sessionRowBackground, Color.black.opacity(0.06))
        XCTAssertEqual(dark.selectedRowBackground, Color.accentColor.opacity(0.26))
        XCTAssertEqual(dark.pickedChip, Theme.island.text.opacity(0.12))
        XCTAssertEqual(dark.sidebarBorder, Color.white.opacity(0.14))
        XCTAssertEqual(dark.link, dark.text)
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
                XCTAssertEqual(theme.dotEnded, base.dotEnded, name)
                XCTAssertEqual(theme.sidebarText, base.sidebarText, name)
                XCTAssertEqual(theme.idle, base.idle, name)
                XCTAssertEqual(theme.idleText, base.idleText, name)
                XCTAssertEqual(theme.sessionRowBackground, base.sessionRowBackground, name)
                XCTAssertEqual(theme.selectedRowBackground, base.selectedRowBackground, name)
                XCTAssertEqual(theme.sidebarBorder, base.sidebarBorder, name)
                XCTAssertEqual(theme.pickedChip, base.pickedChip, name)
                XCTAssertEqual(theme.alertTurnText, base.alertTurnText, name)
                XCTAssertFalse(theme.isSeeThrough, name)
                for level in StatusLevel.allCases {
                    XCTAssertEqual(theme.statusText(level), base.statusText(level), "\(name) \(level)")
                }
            }
        }
    }

    /// The HUD's own tokens are its theme on its own ground: a light HUD's request cards thin with the look, and the
    /// standard look's are the island's as they always were.
    func testTheHUDsThemeIsItsTokensOnItsOwnGround() {
        let glass = HUDLook(appearance: .light, material: .glass, transparency: 0.5)
        XCTAssertEqual(glass.theme.card, Theme.lightIsland.card.opacity(glass.innerOpacity))
        XCTAssertEqual(glass.theme.secondary, Color.black.opacity(0.65))
        let solid = HUDLook(appearance: .light, transparency: 0.3)
        XCTAssertEqual(solid.theme.card, Theme.lightIsland.card.opacity(solid.innerOpacity))
        XCTAssertEqual(solid.theme.secondary, Color.black.opacity(0.55))
        XCTAssertEqual(HUDLook(appearance: .light).theme.card, Theme.lightIsland.card, "opaque, white")
        XCTAssertEqual(HUDLook.standard.theme.card, Theme.island.card)
        XCTAssertEqual(HUDLook.standard.theme.inputBackground, Theme.island.inputBackground)
        let darkGlass = HUDLook(appearance: .dark, material: .glass, transparency: 0.5)
        XCTAssertEqual(darkGlass.theme.card, Theme.island.card, "a tint of white already")
        XCTAssertEqual(darkGlass.theme.inputBackground, Theme.island.inputBackground.opacity(darkGlass.innerOpacity))
    }

    // MARK: Helpers

    private struct Components {
        let red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    private func sRGB(_ color: Color, file: StaticString = #filePath, line: UInt = #line) throws -> Components {
        let ns = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB), file: file, line: line)
        return Components(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }

    /// Asserts that `tint` laid over the opaque `ground` gives `grey`'s red and green to within 2 levels.
    private func assertTint(_ tint: Color, over ground: UInt32, gives grey: UInt32, _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let c = try sRGB(tint, file: file, line: line)
        func channel(_ hex: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((hex >> shift) & 0xff) / 255 }
        let red = c.red * c.alpha + channel(ground, 16) * (1 - c.alpha)
        let green = c.green * c.alpha + channel(ground, 8) * (1 - c.alpha)
        XCTAssertLessThan(c.alpha, 1, "\(what) is a tint", file: file, line: line)
        XCTAssertEqual(red, channel(grey, 16), accuracy: 2 / 255, "\(what): red", file: file, line: line)
        XCTAssertEqual(green, channel(grey, 8), accuracy: 2 / 255, "\(what): green", file: file, line: line)
    }
}
