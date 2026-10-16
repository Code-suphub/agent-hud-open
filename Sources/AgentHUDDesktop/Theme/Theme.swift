import AppKit
import SwiftUI
import AgentHUDCore

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(RGBA(hex: hex, alpha: opacity))
    }
}

extension NSColor {
    convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }

    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(RGBA(hex: hex, alpha: alpha))
    }
}

extension CGColor {
    static func rgba(_ c: RGBA) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [c.red, c.green, c.blue, c.alpha])!
    }
}

extension Font {
    /// System font (SF Pro) at the design's sizes.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func tabular(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// Design tokens for the dark and light window chrome, and for the HUD drawn in either. The HUD reads the theme of its
/// screen's look (`HUDLook.theme`) from the environment (`hudTheme`); `.island`, the dark one, is the standard look's.
/// A light HUD draws with `.lightIsland`, modelled on macOS's light popovers and HUDs: dark ink on a near-white surface,
/// the light window's own background, so the window tokens the panel shares with the statistics window sit on the
/// ground they were made for. Light glass draws with `.lightGlass`.
///
/// The tokens are set here and nowhere else. A light HUD's theme is the light window's with the few tokens changed that
/// its surface asks for, which is why they can be changed in this file.
struct Theme {
    /// The palettes' variants.
    private enum Shades {
        /// The dark chrome's, and the dark HUD's.
        case dark
        /// The light window's.
        case light
        /// A light HUD's, which draws levels in shades of its own (`StatusPalette.lightHUDColor(for:)`): its surface has
        /// no window chrome round it to set the system tints off.
        case lightHUD
    }

    /// Chooses the palettes' variant.
    private var shades: Shades
    private(set) var windowBackground: Color
    private(set) var sidebarBackground: Color
    private(set) var sidebarBorder: Color
    private(set) var inputBackground: Color
    private(set) var text: Color
    private(set) var secondary: Color
    private(set) var tertiary: Color
    private(set) var card: Color
    private(set) var cardBorder: Color
    private(set) var divider: Color
    private(set) var track: Color
    private(set) var rowBackground: Color
    private(set) var rowBorder: Color
    private(set) var sessionRowBackground: Color
    private(set) var segmentBackground: Color
    private(set) var segmentSelected: Color
    private(set) var sidebarText: Color
    private(set) var dotEnded: Color

    // The HUD's own tokens, which the window chrome has no use for.

    /// The HUD's surface: the island's silhouette, a detached card, the Simple panel and the panel's picture.
    private(set) var islandFill: Color
    /// The hairline round a surface that floats free of the screen's edge: the Simple panel and a detached card.
    private(set) var islandOutline: Color
    /// The hairline round the island while the desktop behind it is light, so the two do not run together.
    private(set) var desktopOutline: Color
    /// The unfilled part of a ring on the Simple panel.
    private(set) var meterTrack: Color
    /// The alerts' ink at full strength. Their reminders and cards grade it with opacities of their own (`alertInk(_:)`).
    private(set) var alertText: Color
    /// Ink on a fill of `text`, such as the draft bar's Save button.
    private(set) var inverseText: Color
    /// Ink on a bright fill that stays bright either way, such as Approve or Submit.
    private(set) var onAccent: Color
    /// A box raised off the HUD's surface, such as a hover popover's body.
    private(set) var raisedSurface: Color
    /// A box set into a card, such as a request's command inside the request's own card.
    private(set) var insetSurface: Color
    /// The look's own colour where it meets glass: the dimming layer beneath it (`HUDLook.glassDimming`), and what stands
    /// in for glass where nothing is behind to blur (`HUDLook.glassStandIn`); the island's own surface, black beneath dark
    /// glass and the light window's near-white beneath light glass.
    private(set) var glassTint: Color
    /// The alerts' accents (`IslandAlert.accent`) as text and thin glyphs: a finished turn's blue, calm news's green and
    /// a warning's warm. On the dark HUD they are the accents themselves; on a light one, darker versions that stay
    /// legible there. The accents stay the glow's tint.
    private(set) var alertTurnText: Color
    private(set) var alertCalmText: Color
    private(set) var alertWarningText: Color

    private var isLight: Bool { shades != .dark }

    /// A level as a fill: a ring, a bar, a dot.
    func status(_ level: StatusLevel) -> Color {
        Color(shades == .lightHUD ? StatusPalette.lightHUDColor(for: level)
                                  : StatusPalette.color(for: level, light: isLight))
    }

    /// A level as text or a thin glyph, which on a light theme has to be darker than the fill to be read.
    func statusText(_ level: StatusLevel) -> Color {
        Color(shades == .lightHUD ? StatusPalette.lightHUDTextColor(for: level)
                                  : StatusPalette.textColor(for: level, light: isLight))
    }

    /// The alerts' accents as fills: their main buttons, such as Return to session or View usage statistics, and their
    /// dots and bars, under ink of `onAlertFill`. They are the text shades: on the dark HUD the bright accents
    /// themselves, and on a light one the deep shades, where a pastel on near-white reads as a button switched off.
    var alertTurnFill: Color { alertTurnText }
    var alertCalmFill: Color { alertCalmText }
    var alertWarningFill: Color { alertWarningText }
    /// Ink on those fills: black on the dark HUD's bright accents, white on a light HUD's deep shades.
    var onAlertFill: Color { isLight ? .white : .black }

    /// The alerts' ink graded to `opacity`, for their captions, account lines and times. Near-black ink thinned on a
    /// near-white surface fades much faster than white ink thinned on black, so a light theme lifts the grade by a fifth
    /// to keep a caption about as legible as on the dark HUD, where the grade is the one asked for.
    func alertInk(_ opacity: Double) -> Color {
        alertText.opacity(isLight ? min(1, opacity + 0.2) : opacity)
    }

    /// The grey of an agent with no level to show, as a fill, and as text.
    var idle: Color { Color(StatusPalette.idle) }
    var idleText: Color { Color(StatusPalette.idleTextColor(light: isLight)) }

    /// One agent's colour in the HUD, by its palette index (`UsageStore.consumerPaletteIndex(_:)`): the statistics
    /// window's palette on a dark HUD, its deeper shades on a light one.
    func agent(_ index: Int) -> Color {
        Color(AgentPalette.color(index: index, light: isLight))
    }

    /// One hue per token kind, lighter on the dark chrome.
    func kind(_ kind: TokenKind) -> Color {
        switch kind {
        case .cacheWrite: Color(hex: isLight ? 0x9470cd : 0xb699eb)
        case .input: Color(hex: isLight ? 0x398ad6 : 0x6db0f4)
        case .reasoning: Color(hex: isLight ? 0xc35f92 : 0xe38ab5)
        case .output: Color(hex: isLight ? 0xc26e12 : 0xe29858)
        case .cacheRead: Color(hex: isLight ? 0x00a091 : 0x31c3b5)
        }
    }

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
        segmentSelected: Color(hex: 0x5a5a5e),
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
        alertTurnText: Color(IslandAlert.turnAccent),
        alertCalmText: Color(IslandAlert.calmAccent),
        alertWarningText: Color(IslandAlert.warningAccent)
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
        alertTurnText: Color(hex: 0x2f62d0),
        alertCalmText: Color(hex: 0x0f7b57),
        alertWarningText: Color(hex: 0xa8521c)
    )

    /// The HUD's dark tokens, which the standard look draws with: light ink on the black island.
    static let island = Theme.dark

    /// The HUD's light tokens, which a light look draws with: the light window's, with the levels in the HUD's own
    /// shades, and a button's outline as firm as on the dark HUD, where the window's hairline would all but vanish on a
    /// white card.
    static let lightIsland: Theme = {
        var theme = Theme.light
        theme.shades = .lightHUD
        theme.cardBorder = Color.black.opacity(0.12)
        return theme
    }()

    /// Light glass's tokens: the light HUD's, with its secondary and tertiary ink a grade darker, since glass over a dark
    /// desktop is a greyer ground than the solid surface and the window's own greys fall to 2:1 there. A window on light
    /// glass, with Match screen on, takes the same two greys (`under(_:)`). Its cards, rows and inputs thin with the
    /// transparency drawn, as every light box does on a ground the desktop shows through (`HUDLook.innerOpacity`): to
    /// about half at Clear's and Regular's top, 60 % drawn, and to a fifth at the material's, 100 %.
    static let lightGlass: Theme = {
        var theme = Theme.lightIsland
        theme.secondary = Color(hex: 0x55555a)
        theme.tertiary = Color(hex: 0x737378)
        return theme
    }()

    static func forScheme(_ scheme: ColorScheme) -> Theme {
        scheme == .light ? .light : .dark
    }

    /// These tokens on a ground of `look`, the HUD's or, with Match screen on, a window's (`WindowSurface`), so that what
    /// lies on the ground follows the look as the ground does, light and dark alike:
    /// - The boxes painted on it, cards, rows and inputs, which are opaque where the dark ones are tints of white, thin
    ///   as the ground does (`HUDLook.innerOpacity`), so that a light card lets the glass or the desktop through as a dark
    ///   card does.
    /// - On light glass the secondary and tertiary ink are light glass's, a grade darker.
    /// A selected segment (`segmentSelected`) stays opaque on purpose, white or grey whatever the ground: a selected
    /// control is drawn opaque, as macOS draws it on glass too. Under no look, or an opaque one, the tokens are as they
    /// are.
    func under(_ look: HUDLook?) -> Theme {
        guard let look else { return self }
        var theme = self
        if look.appearance == .light, look.material == .glass {
            theme.secondary = Theme.lightGlass.secondary
            theme.tertiary = Theme.lightGlass.tertiary
        }
        let share = look.innerOpacity
        guard share < 1 else { return theme }
        theme.inputBackground = inputBackground.opacity(share)
        if isLight {
            theme.card = card.opacity(share)
            theme.rowBackground = rowBackground.opacity(share)
        }
        return theme
    }
}

/// Convenience: `Color(rgba)` for agent palette entries.
extension AgentPalette {
    static func swiftUIColor(index: Int) -> Color {
        Color(color(index: index))
    }
}
