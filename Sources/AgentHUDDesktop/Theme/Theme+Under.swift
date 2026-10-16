import SwiftUI
import AgentHUDCore

extension Theme {
    /// These tokens on a ground of `look`, the HUD's or, with Match screen on, a window's (`WindowSurface`), so that what
    /// lies on the ground follows the look as the ground does, light and dark alike. Under no look, or an opaque one,
    /// the tokens are as they are. On a ground the desktop shows through, glass or a solid with a transparency:
    /// - The greys, secondary, tertiary, an ended session's dot, the sidebar's names and the idle grey, are tints of the
    ///   ink, white on dark and black on light, at the share that gives the very grey on the look's own colour
    ///   (`SeeThroughGreys`), so that nothing moves as the slider leaves 0. A fixed grey lies inside the range of grounds
    ///   glass can reach, mid-grey for a dark look over a light desktop and for a light look over a dark one, and ran
    ///   into the ground and into its own track there; a tint always lies between the ground and the ink, so it never
    ///   crosses either, and the greys stay in order on any ground. On light glass they are a grade darker, since glass
    ///   over a dark desktop is a greyer ground than the solid surface.
    /// - A level and an alert's accent as text take paler shades on dark and deeper ones on light (`statusText(_:)`).
    /// - The faint tints that mark a state, a hovered session, a chosen row or chip and the sidebar's edge, are about
    ///   twice as strong: a tint's step shrinks as the ground nears the ink.
    /// - The boxes painted on it, cards, rows and inputs, which are opaque where the dark ones are tints of white, thin
    ///   as the ground does (`HUDLook.innerOpacity`), so that a light card lets the glass or the desktop through as a dark
    ///   card does.
    /// A selected segment (`segmentSelected`) is not thinned: white on light grounds, as macOS draws a chosen control, and
    /// a tint of white on dark ones, a step lighter than its track whatever the ground.
    func under(_ look: HUDLook?) -> Theme {
        guard let look, look.seeThrough else { return self }
        var theme = self
        let greys = SeeThroughGreys(light: isLight, onBlack: ground == .hud, glass: look.material == .glass)
        let ink = isLight ? Color.black : Color.white
        theme.secondary = ink.opacity(greys.secondary)
        theme.tertiary = ink.opacity(greys.tertiary)
        theme.dotEnded = ink.opacity(greys.dotEnded)
        if let sidebar = greys.sidebarText { theme.sidebarText = ink.opacity(sidebar) }
        theme.idle = ink.opacity(greys.idle)
        theme.idleTextUnder = theme.secondary
        theme.isSeeThrough = true
        theme.sessionRowBackground = ink.opacity(isLight ? 0.06 : 0.08)
        theme.selectedRowBackground = Color.accentColor.opacity(0.26)
        theme.sidebarBorder = ink.opacity(0.14)
        let share = look.innerOpacity
        guard share < 1 else { return theme }
        theme.inputBackground = inputBackground.opacity(share)
        if isLight {
            theme.card = card.opacity(share)
            theme.rowBackground = rowBackground.opacity(share)
        }
        return theme
    }

    /// The shares of the ink, white on dark and black on light, that the greys are drawn at on a ground the desktop shows
    /// through, each the one that lays today's grey over the look's own colour, to within a level: on a dark window's
    /// #282828 page (#1f1f1f sidebar) #98989d, #6e6e73 and #d0d0d5; on the black HUD #98989d and #6e6e73 again; on the
    /// light #f5f5f7 #6e6e73, #8e8e93 and #aeaeb2, and light glass's darker #55555a and #737378; the idle grey #9a9aa0
    /// on light and the secondary on dark. The tints are neutral, so the greys lose the few levels of blue the fixed
    /// ones carry.
    struct SeeThroughGreys: Equatable {
        let secondary: Double
        let tertiary: Double
        let dotEnded: Double
        /// The Settings sidebar's names, on a dark window's sidebar; nil where they are the main ink.
        let sidebarText: Double?
        let idle: Double

        init(light: Bool, onBlack: Bool, glass: Bool) {
            switch (light, onBlack, glass) {
            case (false, false, _):
                (secondary, tertiary, dotEnded, sidebarText) = (0.52, 0.33, 0.33, 0.79)
                idle = secondary
            case (false, true, _):
                (secondary, tertiary, dotEnded, sidebarText) = (0.60, 0.43, 0.43, 0.82)
                idle = secondary
            case (true, _, false):
                (secondary, tertiary, dotEnded, sidebarText, idle) = (0.55, 0.42, 0.29, nil, 0.37)
            case (true, _, true):
                (secondary, tertiary, dotEnded, sidebarText, idle) = (0.65, 0.53, 0.29, nil, 0.37)
            }
        }
    }
}
