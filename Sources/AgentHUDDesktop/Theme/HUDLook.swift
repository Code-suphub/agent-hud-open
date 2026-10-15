import AppKit
import SwiftUI
import AgentHUDCore

/// What one screen's HUD looks like: its island, the panel that opens from it, and the cards and reminders on it. Each
/// screen's HUD draws with a look of its own (`SettingsStore.effectiveLook(on:)`). The standard look is the HUD as it
/// has always been drawn, light ink on its black island, whatever the Mac or the app is set to.
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

    /// The HUD as it has always been drawn: dark and solid. Every screen has it until a setting of its own chooses
    /// another.
    static let standard = HUDLook(appearance: .dark)

    /// The tokens the HUD draws with: the island's own for a dark HUD, the light window's for a light one.
    var theme: Theme {
        switch appearance {
        case .dark: .island
        case .light: .light
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

    /// The same for AppKit: the appearance of a window or a hosting view that draws a piece of the HUD apart from the
    /// island, such as a hover popover's or a picture's, which a scroller, a text field's caret and a template image
    /// follow.
    var appearanceName: NSAppearance.Name {
        switch appearance {
        case .dark: .darkAqua
        case .light: .aqua
        }
    }
}

extension SettingsStore {
    /// The look of the HUD on `screen`, which its island, its panel and every picture and preview of them draw with.
    /// Every screen has the standard look until its settings can choose another.
    func effectiveLook(on screen: String) -> HUDLook { .standard }
}

extension EnvironmentValues {
    /// The look of the HUD a view is drawn in, which the island and `hudLook(_:)` set; the standard look anywhere else.
    @Entry var hudLook: HUDLook = .standard

    /// The tokens of the HUD a view is drawn in: its look's theme.
    var hudTheme: Theme { hudLook.theme }
}

extension View {
    /// Draws the view with `look`: the HUD's own colours from its theme, and everything SwiftUI chooses itself from its
    /// colour scheme, so a dark HUD in a window set to light picks no light-background artwork and no light controls.
    /// A piece of the HUD drawn apart from the island takes its look this way: a picture, a hover popover's details, a
    /// preview. The island itself takes only the look's colours, and leaves its colour scheme to the app as it always
    /// has (`IslandRootView.body`).
    func hudLook(_ look: HUDLook) -> ModifiedContent<Self, HUDLookEnvironment> {
        modifier(HUDLookEnvironment(look: look))
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
