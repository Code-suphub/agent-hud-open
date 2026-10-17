import AppKit
import SwiftUI
import AgentHUDCore

/// Design tokens for the dark and light window chrome, and for the HUD drawn in either. The HUD reads the theme of its
/// screen's look (`HUDLook.theme`) from the environment (`hudTheme`); `.island`, the dark one, is the standard look's.
/// A light HUD draws with `.lightIsland`, modelled on macOS's light popovers and HUDs: dark ink on a near-white surface,
/// the light window's own background, so the window tokens the panel shares with the statistics window sit on the
/// ground they were made for. On a ground the desktop shows through, glass or a thinned solid, the tokens are taken
/// `under(_:)` that look.
///
/// The tokens are declared here and set in two places only: the palettes (`Theme+Palettes.swift`), and `under(_:)` for a
/// ground the desktop shows through (`Theme+Under.swift`). A light HUD's theme is the light window's with the few tokens
/// changed that its surface asks for.
struct Theme {
    /// The palettes' variants.
    enum Shades {
        /// The dark chrome's, and the dark HUD's.
        case dark
        /// The light window's.
        case light
        /// A light HUD's, which draws levels in shades of its own (`StatusPalette.lightHUDColor(for:)`): its surface has
        /// no window chrome round it to set the system tints off.
        case lightHUD
    }

    /// Chooses the palettes' variant.
    var shades: Shades

    /// The opaque ground the tokens' greys were chosen on, which `under(_:)` reads to draw them as tints of the ink that
    /// give the same greys there.
    enum Ground {
        /// A window's page, #282828 in the dark (its sidebar #1f1f1f), and the light window's #f5f5f7.
        case window
        /// The HUD's surface: the black island, the panel and the cards on it, the notch row's wings, and the menu, whose
        /// glass has black beneath it. A light HUD's is the light window's colour, so only a dark one is told apart.
        case hud
    }
    var windowBackground: Color
    var sidebarBackground: Color
    var sidebarBorder: Color
    var inputBackground: Color
    var text: Color
    var secondary: Color
    var tertiary: Color
    var card: Color
    var cardBorder: Color
    var divider: Color
    var track: Color
    var rowBackground: Color
    var rowBorder: Color
    var sessionRowBackground: Color
    var segmentBackground: Color
    var segmentSelected: Color
    var sidebarText: Color
    var dotEnded: Color

    // The HUD's own tokens, which the window chrome has no use for.

    /// The HUD's surface: the island's silhouette, a detached card, the Simple panel and the panel's picture.
    var islandFill: Color
    /// The hairline round a surface that floats free of the screen's edge: the Simple panel and a detached card.
    var islandOutline: Color
    /// The hairline round the island while the desktop behind it is light, so the two do not run together.
    var desktopOutline: Color
    /// The unfilled part of a ring on the Simple panel.
    var meterTrack: Color
    /// The alerts' ink at full strength. Their reminders and cards grade it with opacities of their own (`alertInk(_:)`).
    var alertText: Color
    /// Ink on a fill of `text`, such as the draft bar's Save button.
    var inverseText: Color
    /// Ink on a bright fill that stays bright either way, such as Approve or Submit.
    var onAccent: Color
    /// A box raised off the HUD's surface, such as a hover popover's body.
    var raisedSurface: Color
    /// A box set into a card, such as a request's command inside the request's own card.
    var insetSurface: Color
    /// The look's own colour where it meets glass: the dimming layer beneath it (`HUDLook.glassDimming`), and what stands
    /// in for glass where nothing is behind to blur (`HUDLook.glassStandIn`); the island's own surface, black beneath dark
    /// glass and the light window's near-white beneath light glass.
    var glassTint: Color
    /// The alerts' accents (`IslandAlert.accent`) as fills: their main buttons, such as Return to session or View usage
    /// statistics, and their dots and bars, under ink of `onAlertFill`. On the dark HUD they are the bright accents
    /// themselves, and on a light one deep shades, where a pastel on near-white reads as a button switched off. The
    /// accents stay the glow's tint.
    var alertTurnFill: Color
    var alertCalmFill: Color
    var alertWarningFill: Color

    // Set apart from the palettes, the same in each, until `under(_:)` changes them.

    var ground: Ground = .window
    /// Whether the tokens lie on a ground the desktop shows through (`under(_:)`), where a level and an alert's accent
    /// as text take the shades that hold there (`statusText(_:)`, `alertTurnText`), and a colour of its own, such as a
    /// heatmap's, may take another.
    var isSeeThrough = false
    /// The grey of an agent with no level to show, as a fill and as text: a ring's colour and its figure on the Simple
    /// panel. Held here, as the other greys are, so that `under(_:)` reaches them.
    var idle = Color(StatusPalette.idle)
    var idleText: Color { idleTextUnder ?? Color(StatusPalette.idleTextColor(light: isLight)) }
    var idleTextUnder: Color?
    /// The fill under a chosen row of a list, such as the agent picked in Settings → Agents.
    var selectedRowBackground = Color.accentColor.opacity(0.14)
    /// The fill under a chosen chip, such as a model picked in the statistics' legend: the ink at 6 %.
    var pickedChip: Color { text.opacity(isSeeThrough ? 0.12 : 0.06) }

    /// Whether the ink is dark on a light ground.
    var isLight: Bool { shades != .dark }

    /// A level as a fill: a ring, a bar, a dot.
    func status(_ level: StatusLevel) -> Color {
        Color(shades == .lightHUD ? StatusPalette.lightHUDColor(for: level)
                                  : StatusPalette.color(for: level, light: isLight))
    }

    /// A level as text or a thin glyph, which on a light theme has to be darker than the fill to be read. On a ground
    /// the desktop shows through, which lightens a dark look and darkens a light one, a paler shade on dark and a deeper
    /// one on light (`StatusPalette.seeThroughTextColor(for:light:)`); the fills keep their hues.
    func statusText(_ level: StatusLevel) -> Color {
        if isSeeThrough { return Color(StatusPalette.seeThroughTextColor(for: level, light: isLight)) }
        return Color(shades == .lightHUD ? StatusPalette.lightHUDTextColor(for: level)
                                         : StatusPalette.textColor(for: level, light: isLight))
    }

    /// The alerts' accents as text and thin glyphs: a finished turn's blue, calm news's green and a warning's warm. They
    /// are the fills' shades, and on a ground the desktop shows through paler on dark and deeper on light, as a level's
    /// text is (`statusText(_:)`).
    var alertTurnText: Color { isSeeThrough ? Color(hex: isLight ? 0x1d439c : 0xb8cfff) : alertTurnFill }
    var alertCalmText: Color { isSeeThrough ? Color(hex: isLight ? 0x0a5a3f : 0xa8ecd0) : alertCalmFill }
    var alertWarningText: Color { isSeeThrough ? Color(hex: isLight ? 0x7c3b12 : 0xf6c9a6) : alertWarningFill }
    /// Ink on those fills: black on the dark HUD's bright accents, white on a light HUD's deep shades.
    var onAlertFill: Color { isLight ? .white : .black }

    /// The alerts' ink graded to `opacity`, for their captions, account lines and times. Near-black ink thinned on a
    /// near-white surface fades much faster than white ink thinned on black, so a light theme lifts the grade by a fifth
    /// to keep a caption about as legible as on the dark HUD, where the grade is the one asked for.
    func alertInk(_ opacity: Double) -> Color {
        alertText.opacity(isLight ? min(1, opacity + 0.2) : opacity)
    }

    /// A link's ink, such as Reveal log in Finder's, and an accent written as text, such as Copy command's: the system's
    /// link and accent colours, which follow the appearance but not a ground the desktop shows through, where a bright
    /// blue falls to about 1:1 on a mid-grey ground; there the main ink, underlined (`themedLink(_:)`).
    var link: Color { isSeeThrough ? text : Color(nsColor: .linkColor) }
    var accentText: Color { isSeeThrough ? text : Color.accentColor }

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

    /// The palettes' tokens, each given; what is set apart from them takes its default.
    init(shades: Shades, windowBackground: Color, sidebarBackground: Color, sidebarBorder: Color,
                 inputBackground: Color, text: Color, secondary: Color, tertiary: Color, card: Color,
                 cardBorder: Color, divider: Color, track: Color, rowBackground: Color, rowBorder: Color,
                 sessionRowBackground: Color, segmentBackground: Color, segmentSelected: Color, sidebarText: Color,
                 dotEnded: Color, islandFill: Color, islandOutline: Color, desktopOutline: Color, meterTrack: Color,
                 alertText: Color, inverseText: Color, onAccent: Color, raisedSurface: Color, insetSurface: Color,
                 glassTint: Color, alertTurnFill: Color, alertCalmFill: Color, alertWarningFill: Color) {
        self.shades = shades
        self.windowBackground = windowBackground
        self.sidebarBackground = sidebarBackground
        self.sidebarBorder = sidebarBorder
        self.inputBackground = inputBackground
        self.text = text
        self.secondary = secondary
        self.tertiary = tertiary
        self.card = card
        self.cardBorder = cardBorder
        self.divider = divider
        self.track = track
        self.rowBackground = rowBackground
        self.rowBorder = rowBorder
        self.sessionRowBackground = sessionRowBackground
        self.segmentBackground = segmentBackground
        self.segmentSelected = segmentSelected
        self.sidebarText = sidebarText
        self.dotEnded = dotEnded
        self.islandFill = islandFill
        self.islandOutline = islandOutline
        self.desktopOutline = desktopOutline
        self.meterTrack = meterTrack
        self.alertText = alertText
        self.inverseText = inverseText
        self.onAccent = onAccent
        self.raisedSurface = raisedSurface
        self.insetSurface = insetSurface
        self.glassTint = glassTint
        self.alertTurnFill = alertTurnFill
        self.alertCalmFill = alertCalmFill
        self.alertWarningFill = alertWarningFill
    }
}
