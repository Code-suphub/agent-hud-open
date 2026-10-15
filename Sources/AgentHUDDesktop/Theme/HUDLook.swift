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
    /// How much of the desktop the HUD lets through, from 0, the look's own surface drawn whole, to 1, bare: what the
    /// screen's Transparency chooses for its material (`ScreenPlacement.transparency`). Opaque unless chosen otherwise.
    var transparency: Double = 0

    /// The HUD as it has always been drawn: dark and solid. A screen has it until its settings choose another, and the
    /// island at rest in a hardware notch looks it whatever they choose.
    static let standard = HUDLook(appearance: .dark)

    /// The look of the island in the row of a hardware notch, at rest or showing a reminder's wings: dark whatever the
    /// appearance, in the look's own material, so that the row stays one with the camera housing. At rest the island is
    /// the housing's own shape, inked black (`NotchInk`); a reminder's wings are black, or black glass under Glass. What
    /// opens out of the row, the panel and the cards, takes the look itself (`ScreenHUD`).
    var inNotchRow: HUDLook {
        HUDLook(appearance: .dark, material: material, transparency: transparency)
    }

    /// The tokens the HUD draws with: the island's own for a dark HUD, solid or glass; the light window's, set for the
    /// HUD, for a light one; and for light glass, those with ink a grade darker.
    var theme: Theme {
        switch (appearance, material) {
        case (.dark, _): .island
        case (.light, .solid): .lightIsland
        case (.light, .glass): .lightGlass
        }
    }

    /// The scheme SwiftUI draws in whatever the HUD leaves to it: system colours, controls, and the marks that come in a
    /// version for each background.
    var colorScheme: ColorScheme {
        switch appearance {
        case .dark: .dark
        case .light: .light
        }
    }

    /// What glass is covered with under the HUD's ink (`HUDSurface`): the theme's `glassTint`, the look's own surface,
    /// at the opacity the transparency leaves it (`coverOpacity`). It darkens dark glass and lightens light glass,
    /// and holds the glass to the look's appearance over any desktop: Liquid Glass follows what is behind it, light over
    /// a light desktop, and the HUD's text and status colours are fixed. Where nothing is behind to blur, it is glass's
    /// stand-in on its own.
    var glassCover: Color {
        theme.glassTint.opacity(coverOpacity)
    }

    /// How much of the look's own surface is drawn, glass's cover or a solid surface's fill: all of it with no
    /// transparency, and at the most transparency the screen can choose still half. Under half, a dark surface over a
    /// white window turns the mid-grey that neither the HUD's light ink nor its accents read on, and a light one over a
    /// black desktop the same grey from the other side; the desktop's colours and shapes show through either way.
    var coverOpacity: Double {
        1 - transparency * Self.coverGivenUp
    }

    /// Whether the desktop shows through the HUD: glass, or a solid surface with a transparency. What lies under the
    /// HUD's surfaces, the glow and the shadows, is then kept out from under them (`GlowCutout`, `castsShellShadows`).
    var seeThrough: Bool {
        material == .glass || transparency > 0
    }

    /// The share of the cover the transparency takes away at its most: 0.9 of 0.55, leaving half.
    static let coverGivenUp = 0.55

    /// How much of the glass's frost is drawn: all of it with no transparency, less as the transparency rises, so the
    /// desktop's own shapes come through the glass, and still most of it at the most, so that they come through soft and
    /// the glass reads as glass. The frost alone, however thin the cover over it, blurs a window behind the HUD into an
    /// even tone, light glass over a white window into plain white, and a transparency that only thinned the cover
    /// would show nothing there; with the frost thinned as far as the cover, the window behind came through sharp.
    var glassFrost: Double {
        1 - transparency * Self.frostGivenUp
    }

    /// The share of the frost the transparency takes away at its most: 0.9 of 0.4, leaving about two thirds.
    static let frostGivenUp = 0.4

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
                  transparency: placement.drawsTransparency(reducesTransparency: reducesTransparency))
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
