import AppKit
import SwiftUI
import AgentHUDCore

/// The palettes: the dark and the light window's tokens, and the HUD's, each built from its tokens given one by one, so
/// that each is checked on its own rather than in one long expression.
extension Theme {
    static let dark = Theme(
        shades: .dark,
        windowBackground: Color(hex: 0x282828),
        sidebarBackground: Color(hex: 0x1f1f1f),
        sidebarBorder: Color.white.opacity(0.08),
        inputBackground: Color(hex: 0x1c1c1e),
        text: Color(hex: 0xf5f5f7),
        secondary: Color(hex: 0x98989d),
        tertiary: Color(hex: 0x6e6e73),
        card: Color.white.opacity(0.05),
        cardBorder: Color.white.opacity(0.12),
        divider: Color.white.opacity(0.10),
        track: Color.white.opacity(0.12),
        rowBackground: Color.white.opacity(0.05),
        rowBorder: Color.clear,
        sessionRowBackground: Color.white.opacity(0.04),
        segmentBackground: Color.white.opacity(0.08),
        // A tint of white rather than a grey, so that the chosen segment stays a step lighter than its track on any dark
        // ground: on glass or a thinned window the ground lightens, and a fixed grey ran into the track there.
        segmentSelected: Color.white.opacity(0.24),
        sidebarText: Color(hex: 0xd0d0d5),
        dotEnded: Color(hex: 0x6e6e73),
        islandFill: Color.black,
        islandOutline: Color.white.opacity(0.14),
        desktopOutline: Color.white.opacity(0.18),
        meterTrack: Color.white.opacity(0.14),
        alertText: Color.white,
        inverseText: Color.black,
        onAccent: Color.black,
        raisedSurface: Color(hex: 0x282828),
        insetSurface: Color.white.opacity(0.05),
        glassTint: Color.black,
        alertTurnFill: Color(IslandAlert.turnAccent),
        alertCalmFill: Color(IslandAlert.calmAccent),
        alertWarningFill: Color(IslandAlert.warningAccent)
    )

    static let light = Theme(
        shades: .light,
        windowBackground: Color(hex: 0xf5f5f7),
        sidebarBackground: Color(hex: 0xe8e8ea),
        sidebarBorder: Color.black.opacity(0.08),
        inputBackground: Color.white,
        text: Color(hex: 0x1d1d1f),
        secondary: Color(hex: 0x6e6e73),
        tertiary: Color(hex: 0x8e8e93),
        card: Color.white,
        cardBorder: Color.black.opacity(0.06),
        divider: Color.black.opacity(0.08),
        track: Color.black.opacity(0.10),
        rowBackground: Color.white,
        rowBorder: Color.black.opacity(0.06),
        sessionRowBackground: Color.black.opacity(0.03),
        segmentBackground: Color.black.opacity(0.08),
        segmentSelected: Color.white,
        sidebarText: Color(hex: 0x1d1d1f),
        dotEnded: Color(hex: 0xaeaeb2),
        // The light HUD: the window's near-white with its ink, hairlines of black at 8 to 10 %, an edge round a shell
        // that stands on a light desktop, and boxes raised in white or set in a shade of black.
        islandFill: Color(hex: 0xf5f5f7),
        islandOutline: Color.black.opacity(0.10),
        desktopOutline: Color.black.opacity(0.10),
        meterTrack: Color.black.opacity(0.10),
        alertText: Color(hex: 0x1d1d1f),
        inverseText: Color.white,
        onAccent: Color.black,
        raisedSurface: Color.white,
        insetSurface: Color.black.opacity(0.04),
        glassTint: Color(hex: 0xf5f5f7),
        alertTurnFill: Color(hex: 0x2f62d0),
        alertCalmFill: Color(hex: 0x0f7b57),
        alertWarningFill: Color(hex: 0xa8521c)
    )

    /// The HUD's dark tokens, which the standard look draws with: light ink on the black island. They are the dark
    /// window's, marked as standing on black, so that on a ground the desktop shows through their greys are the tints of
    /// white that give them on black (`under(_:)`).
    static let island: Theme = {
        var theme = Theme.dark
        theme.ground = .hud
        return theme
    }()

    /// The HUD's light tokens, which a light look draws with: the light window's, with the levels in the HUD's own
    /// shades, and a button's outline as firm as on the dark HUD, where the window's hairline would all but vanish on a
    /// white card. Light glass takes them too, under its look, with its secondary and tertiary ink a grade darker
    /// (`under(_:)`).
    static let lightIsland: Theme = {
        var theme = Theme.light
        theme.shades = .lightHUD
        theme.ground = .hud
        theme.cardBorder = Color.black.opacity(0.12)
        return theme
    }()

    static func forScheme(_ scheme: ColorScheme) -> Theme {
        scheme == .light ? .light : .dark
    }
}
