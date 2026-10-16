import AppKit
import SwiftUI
import AgentHUDCore

/// What one screen's HUD looks like: its island, the panel that opens from it, and the cards and reminders on it. Each
/// screen's HUD draws with a look of its own (`SettingsStore.effectiveLook(on:)`), which its settings choose: an
/// appearance and a material. The standard look is the HUD as it has always been drawn, light ink on its black island,
/// whatever the Mac or the app is set to.
struct HUDLook: Equatable, Sendable {
    /// Light ink on a dark surface, or dark ink on a light one.
    enum Appearance: Equatable, Sendable {
        case dark
        case light
    }

    /// What the surface is made of: an opaque fill, or glass that lets the desktop behind it show through blurred.
    /// Glass keeps the look's appearance, dark glass with light ink or light glass with dark ink, whatever is behind it.
    enum Material: Equatable, Sendable {
        case solid
        case glass
    }

    var appearance: Appearance
    var material: Material = .solid
    /// How much of the desktop the HUD lets through, what the screen's Transparency chooses for its material
    /// (`ScreenPlacement.transparency`), 0 to 0.95: for glass how little of the look's own colour lies beneath the glass,
    /// for a solid surface how little of its fill is drawn. None unless chosen otherwise.
    var transparency: Double = 0
    /// What glass is made of (`HUDGlassStyle`): clear or regular Liquid Glass, or a frosted material.
    var glassStyle: HUDGlassStyle = .clear

    /// The HUD as it has always been drawn: dark and solid. A screen has it until its settings choose another, and the
    /// island at rest in a hardware notch looks it whatever they choose.
    static let standard = HUDLook(appearance: .dark)

    /// The look of the island in the row of a hardware notch, at rest or showing a reminder's wings: dark whatever the
    /// appearance, in the look's own material, so that the row stays one with the camera housing. At rest the island is
    /// the housing's own shape, inked black (`NotchInk`); a reminder's wings are black, or black glass under Glass: glass
    /// over a fixed black (`notchRowTransparency`), whatever the screen's Transparency, which the bare glass would leave
    /// light over a light menu bar. What opens out of the row, the panel and the cards, takes the look itself
    /// (`ScreenHUD`).
    var inNotchRow: HUDLook {
        switch material {
        case .glass: HUDLook(appearance: .dark, material: .glass, transparency: Self.notchRowTransparency,
                             glassStyle: glassStyle)
        case .solid: HUDLook(appearance: .dark, material: .solid)
        }
    }

    /// The notch row's glass: four fifths black beneath it.
    static let notchRowTransparency = 0.2

    /// The tokens the HUD draws with: the island's own for a dark HUD, solid or glass; the light window's, set for the
    /// HUD, for a light one; and for light glass, those with ink a grade darker. Their painted boxes thin with the look
    /// (`Theme.under(_:)`), as a window's do.
    var theme: Theme {
        switch (appearance, material) {
        case (.dark, _): Theme.island.under(self)
        case (.light, .solid): Theme.lightIsland.under(self)
        case (.light, .glass): Theme.lightGlass.under(self)
        }
    }

    /// How much of a painted box on the look's ground is drawn, a card, a row or an input (`Theme.under(_:)`): all of it
    /// on an opaque ground; on one the desktop shows through, thinned as the ground is, to a fifth at the most, so that
    /// boxes on a light ground follow the look as the dark ground's tints of white do.
    var innerOpacity: Double {
        seeThrough ? Self.innerFloor + (1 - Self.innerFloor) * (1 - transparency) : 1
    }

    /// The share of a painted box left at the most transparency.
    static let innerFloor = 0.2

    /// The scheme SwiftUI draws in whatever the HUD leaves to it: system colours, controls, and the marks that come in a
    /// version for each background.
    var colorScheme: ColorScheme {
        switch appearance {
        case .dark: .dark
        case .light: .light
        }
    }

    /// The dimming layer beneath Liquid Glass (`HUDSurface`), as Apple asks of clear glass to keep what is on it legible: the
    /// look's own colour, black beneath dark glass and near-white beneath light glass, at the opacity the screen's
    /// transparency leaves it (`dimmingOpacity`). The glass blurs it with the desktop behind, so the HUD stays glass,
    /// frosted and lit at its rim, at any transparency: whole at 0, where the glass shows the look's colour alone, and
    /// none at 1, where it is the system's bare glass, as a macOS menu's is, its colours following the desktop, so that
    /// the HUD's fixed ink reads less well over a desktop of the other shade. Laid over the glass or faded into it, as
    /// before, it either hid the glass or lost its blur.
    var glassDimming: Color {
        theme.glassTint.opacity(dimmingOpacity)
    }

    /// How much of the dimming layer beneath glass is drawn: all of it with no transparency, none at 1.
    var dimmingOpacity: Double {
        material == .glass ? 1 - transparency : 0
    }

    /// How much of a solid surface's fill is drawn: what the transparency leaves of it, all of it at 0 and a twentieth at
    /// the top, as glass's colour beneath it is (`dimmingOpacity`). How much is the user's choice; over a desktop of the
    /// other shade the HUD's ink reads less well the thinner the fill.
    var coverOpacity: Double {
        material == .solid ? 1 - transparency : 0
    }

    /// Glass where nothing is behind to blur (`drawsGlassStandIn`), the HUD's pictures, recordings and some previews: the
    /// look's own colour as the dimming layer has it, and never thinner than about a third, which glass over a mid-grey
    /// backdrop reads as, so that a picture of bare glass still holds the HUD's ink.
    var glassStandIn: Color {
        theme.glassTint.opacity(Self.standInFloor + (1 - Self.standInFloor) * dimmingOpacity)
    }

    /// What glass stands in as at its most transparent.
    static let standInFloor = 0.35

    /// Whether the desktop shows through the HUD: glass, or a solid surface with a transparency. What lies under the
    /// HUD's surfaces, the glow and the shadows, is then kept out from under them (`GlowCutout`, `castsShellShadows`).
    var seeThrough: Bool {
        material == .glass || transparency > 0
    }

    /// The same for AppKit: the appearance of a hosting view or a window that draws the HUD, a hover popover's or a
    /// picture's, which a scroller, a text field's caret and a template image follow.
    var appearanceName: NSAppearance.Name {
        switch appearance {
        case .dark: .darkAqua
        case .light: .aqua
        }
    }

    /// The appearance of the island's own hosting view (`IslandWindowController`): the look's, or none under the standard
    /// look, whose island leaves what AppKit chooses on it to the app, as it always has.
    var islandAppearanceName: NSAppearance.Name? {
        self == .standard ? nil : appearanceName
    }
}

// MARK: Resolution

extension HUDLook {
    /// The look of a HUD that draws `placement`, with macOS set to light or dark (`systemIsLight`) and Reduce
    /// Transparency on or off: the placement's appearance, `system` as macOS is set, and its material, glass drawn solid
    /// under Reduce Transparency, at the placement's transparency.
    init(drawing placement: ScreenPlacement, systemIsLight: Bool, reducesTransparency: Bool) {
        self.init(appearance: placement.drawsLight(systemIsLight: systemIsLight) ? .light : .dark,
                  material: placement.drawsGlass(reducesTransparency: reducesTransparency) ? .glass : .solid,
                  transparency: placement.drawsTransparency(reducesTransparency: reducesTransparency),
                  // A look drawn solid has no glass to be made of, so that it equals any other solid look of its colours.
                  glassStyle: placement.drawsGlass(reducesTransparency: reducesTransparency) ? placement.glassStyle : .clear)
    }
}

extension SettingsStore {
    /// The look of the HUD on `screen`, which its island, its panel, its cards and every picture and preview of them draw
    /// with: the one place a screen's look comes from. It is resolved from the placement the screen draws now, its style
    /// draft included (`effectivePlacement(on:hasNotch:)`), on the display of that key, one that is not attached counting
    /// as a display without a notch, and from how the Mac is set now:
    /// - The screen's appearance, with `system` read from macOS's own light or dark setting (`SystemAppearance.isLight`),
    ///   never from the app's Appearance.
    /// - And the screen's material, except that Reduce Transparency draws glass solid, at the screen's transparency.
    ///
    /// Notch mode at a hardware notch takes the look too, in part: the island stays dark in the notch's row, black or
    /// black glass (`inNotchRow`), and the camera housing black in any look (`IslandRootView.inksNotch`), while the panel
    /// and the cards that open out of the row take the look whole.
    ///
    /// A HUD being dragged keeps the look its screen has saved until it is dropped.
    func effectiveLook(on screen: String) -> HUDLook {
        HUDLook(drawing: effectivePlacement(on: screen, hasNotch: Self.hasNotch(screen)),
                systemIsLight: SystemAppearance.isLight,
                reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// The look of the HUD on `screen` at rest, before it opens, which a picture or a preview of the resting HUD draws:
    /// the screen's look, but in Notch mode at a hardware notch the standard one, black and solid, as the island at rest
    /// there is drawn in any look (`NotchInk`).
    func restingLook(on screen: String) -> HUDLook {
        let hasNotch = Self.hasNotch(screen)
        guard !(hasNotch && effectivePlacement(on: screen, hasNotch: hasNotch).mode == .notch) else { return .standard }
        return effectiveLook(on: screen)
    }

    /// Whether the attached display of `screen` has a hardware notch; a display that is not attached has none.
    private static func hasNotch(_ screen: String) -> Bool {
        NSScreen.screens.first { ScreenIdentity.key(for: $0) == screen }.map(ScreenIdentity.hasNotch) ?? false
    }
}

extension EnvironmentValues {
    /// The look of the HUD a view is drawn in, which the island and `hudLook(_:)` set; the standard look anywhere else.
    @Entry var hudLook: HUDLook = .standard

    /// The tokens of the HUD a view is drawn in: its look's theme.
    var hudTheme: Theme { hudLook.theme }
}

extension View {
    /// Draws the view with `look`: the HUD's own colours from its theme, and everything SwiftUI chooses itself from its
    /// colour scheme, so a dark HUD in a window set to light picks no light-background artwork and no light controls,
    /// and a light HUD in a dark window no dark ones. A piece of the HUD drawn apart from the island takes its look this
    /// way: a picture, a hover popover's details, a preview. The island takes it with `islandLook(_:)`.
    func hudLook(_ look: HUDLook) -> ModifiedContent<Self, HUDLookEnvironment> {
        modifier(HUDLookEnvironment(look: look))
    }

    /// Draws the island, or a sample of it, with `look`: as `hudLook(_:)` does, except that the standard look sets only
    /// its colours and leaves the colour scheme to the app, as the island always has, so the standard island draws as
    /// it always did, its marks' artwork included. Every other look draws in its own scheme, whatever the app is set
    /// to, and the island's hosting view takes its appearance too (`HUDLook.islandAppearanceName`).
    func islandLook(_ look: HUDLook) -> ModifiedContent<Self, IslandLookEnvironment> {
        modifier(IslandLookEnvironment(look: look))
    }
}

/// What a look sets in the environment. A view of its own type so that a window that hosts HUD content apart from the
/// HUD, such as a hover popover's, can name what it hosts.
struct HUDLookEnvironment: ViewModifier {
    let look: HUDLook

    func body(content: Content) -> some View {
        content
            .environment(\.hudLook, look)
            .environment(\.colorScheme, look.colorScheme)
    }
}

/// What the island's look sets in the environment (`islandLook(_:)`). The colour scheme is set either way, to the app's
/// own under the standard look, so that a change of look changes a value and never the island's structure.
struct IslandLookEnvironment: ViewModifier {
    let look: HUDLook
    @Environment(\.colorScheme) private var appScheme

    func body(content: Content) -> some View {
        content
            .environment(\.hudLook, look)
            .environment(\.colorScheme, look == .standard ? appScheme : look.colorScheme)
    }
}
