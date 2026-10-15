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

    /// The HUD as it has always been drawn: dark and solid. A screen has it until its settings choose another, and the
    /// island in a hardware notch keeps it whatever they choose.
    static let standard = HUDLook(appearance: .dark)

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
    /// The look of a HUD that draws `placement` on a screen with or without a hardware notch, with macOS set to light or
    /// dark (`systemIsLight`) and Reduce Transparency on or off: the placement's appearance, `system` as macOS is set,
    /// and its material, glass drawn solid under Reduce Transparency. The island in a hardware notch has the standard
    /// look, whatever the placement chooses (`ScreenPlacement.drawsLook(hasNotch:)`).
    init(drawing placement: ScreenPlacement, hasNotch: Bool, systemIsLight: Bool, reducesTransparency: Bool) {
        self.init(appearance: placement.drawsLight(hasNotch: hasNotch, systemIsLight: systemIsLight) ? .light : .dark,
                  material: placement.drawsGlass(hasNotch: hasNotch, reducesTransparency: reducesTransparency)
                    ? .glass : .solid)
    }
}

extension SettingsStore {
    /// The look of the HUD on `screen`, which its island, its panel, its cards and every picture and preview of them draw
    /// with: the one place a screen's look comes from. It is resolved from the placement the screen draws now, its style
    /// draft included (`effectivePlacement(on:hasNotch:)`), on the display of that key, one that is not attached counting
    /// as a display without a notch, and from how the Mac is set now:
    /// - Notch mode on a display with a hardware notch keeps the standard look, black, dark and solid, whatever the
    ///   screen's appearance and material: the island there is one with the camera housing, and its panel and its cards
    ///   grow out of it. A notch-style bar on a display without a notch takes the screen's look.
    /// - Otherwise the screen's appearance, with `system` read from macOS's own light or dark setting
    ///   (`SystemAppearance.isLight`), never from the app's Appearance, which only its windows take.
    /// - And the screen's material, except that Reduce Transparency draws glass solid.
    ///
    /// A HUD being dragged keeps the look its screen has saved until it is dropped.
    func effectiveLook(on screen: String) -> HUDLook {
        let display = NSScreen.screens.first { ScreenIdentity.key(for: $0) == screen }
        let hasNotch = display.map(ScreenIdentity.hasNotch) ?? false
        return HUDLook(drawing: effectivePlacement(on: screen, hasNotch: hasNotch), hasNotch: hasNotch,
                       systemIsLight: SystemAppearance.isLight,
                       reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
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
