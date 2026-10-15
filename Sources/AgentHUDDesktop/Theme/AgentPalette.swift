import AgentHUDCore

/// Per-agent colors used in the stats window (distinct from the status colors).
public enum AgentPalette {
    public static let colors: [RGBA] = [
        RGBA(hex: 0xc084fc), // Opus
        RGBA(hex: 0x60a5fa), // Sonnet
        RGBA(hex: 0x2dd4bf), // ChatGPT
        RGBA(hex: 0xfb923c), // Codex
        RGBA(hex: 0xf472b6),
        RGBA(hex: 0xa3e635),
    ]

    /// The same hues for a light HUD, where the pale ones above wash out: each the deeper shade of its family that stands
    /// at least 3:1 on the light surface, as a dot or a bar must. Lime takes its 700, the rest their 600.
    public static let lightColors: [RGBA] = [
        RGBA(hex: 0x9333ea),
        RGBA(hex: 0x2563eb),
        RGBA(hex: 0x0d9488),
        RGBA(hex: 0xea580c),
        RGBA(hex: 0xdb2777),
        RGBA(hex: 0x4d7c0f),
    ]

    public static func color(index: Int) -> RGBA {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// The colour at `index`, from the light HUD's shades when `light` is set.
    public static func color(index: Int, light: Bool) -> RGBA {
        let palette = light ? lightColors : colors
        return palette[((index % palette.count) + palette.count) % palette.count]
    }
}
