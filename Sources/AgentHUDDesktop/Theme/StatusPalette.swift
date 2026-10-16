import AgentHUDCore

/// Status colors from the design tokens. Dark values are the defaults; light values are the macOS system tints, and a
/// light HUD has shades of its own.
public enum StatusPalette {
    public static let ok = RGBA(hex: 0x3ddc84)
    public static let warning = RGBA(hex: 0xffd23f)
    public static let critical = RGBA(hex: 0xff453a)
    public static let okLight = RGBA(hex: 0x30d158)
    public static let warningLight = RGBA(hex: 0xffcc00)
    public static let warningTextLight = RGBA(hex: 0xc7a100)
    public static let criticalLight = RGBA(hex: 0xff3b30)
    /// The light HUD's levels. Its surface stands on the desktop with no window chrome round it, so a level is read from
    /// its colour alone there: as a fill, a ring, a bar or a dot, the tint deepened to about 3:1 on the surface, and as
    /// text or a thin glyph, darkened to about 4.5:1. Critical's tint already stands at 3:1 as a fill.
    public static let okHUDLight = RGBA(hex: 0x1f9d4c)
    public static let warningHUDLight = RGBA(hex: 0xc08000)
    public static let okTextHUDLight = RGBA(hex: 0x1e7e34)
    public static let warningTextHUDLight = RGBA(hex: 0x946300)
    public static let criticalTextHUDLight = RGBA(hex: 0xd70015)
    /// Paused / idle glow.
    public static let idle = RGBA(hex: 0x9a9aa0)
    /// The idle grey as text on a light surface, the light window's secondary text.
    public static let idleTextLight = RGBA(hex: 0x6e6e73)

    public static func color(for level: StatusLevel, light: Bool = false) -> RGBA {
        switch (level, light) {
        case (.ok, false): return ok
        case (.warning, false): return warning
        case (.critical, false): return critical
        case (.ok, true): return okLight
        case (.warning, true): return warningLight
        case (.critical, true): return criticalLight
        }
    }

    /// Text on light surfaces needs a darker yellow to stay legible.
    public static func textColor(for level: StatusLevel, light: Bool = false) -> RGBA {
        if light && level == .warning { return warningTextLight }
        return color(for: level, light: light)
    }

    /// A level as a fill on a light HUD.
    public static func lightHUDColor(for level: StatusLevel) -> RGBA {
        switch level {
        case .ok: return okHUDLight
        case .warning: return warningHUDLight
        case .critical: return criticalLight
        }
    }

    /// A level as text or a thin glyph on a light HUD.
    public static func lightHUDTextColor(for level: StatusLevel) -> RGBA {
        switch level {
        case .ok: return okTextHUDLight
        case .warning: return warningTextHUDLight
        case .critical: return criticalTextHUDLight
        }
    }

    /// The idle grey as text: itself on a dark surface, darker on a light one.
    public static func idleTextColor(light: Bool) -> RGBA {
        light ? idleTextLight : idle
    }
}
