import AppKit
import SwiftUI
import AgentHUDCore

/// The look the app's own windows and the menu-bar menu take with Match screen on (`Settings.appearanceFollowsScreen`):
/// each in the whole look of the HUD of the screen it is on, the panel's look there (`SettingsStore.effectiveLook(on:)`),
/// its appearance, material and transparency, and a window taken to another screen takes that screen's. With it off
/// nothing here applies: the windows take the app's Appearance, opaque, as they always have, and the menu that
/// Appearance in regular glass.
///
/// A window takes the look through its appearance, which moves its tokens (`Theme.forScheme`), its controls, its sheets
/// and its popovers together, and its material and transparency through its grounds (`WindowGround`): under any look
/// the desktop shows through, glass or a solid with a transparency, the window is cleared
/// (`HostedWindowController.refreshLook()`) and the ground of its page and of its sidebar is the screen's glass, clear or
/// regular Liquid Glass or a material, with their colour beneath or over it, or their colour thinned as the HUD's solid
/// fill is. The cards, rows and inputs on them thin with the ground (`Theme.under(_:)`), and light glass's greys are a
/// grade darker. The menu-bar menu takes the whole look as the HUD's surfaces do (`StatusItemController.menuLook(on:)`).
/// A window changes its appearance at once, as macOS changes it.
@MainActor
enum WindowLook {
    /// The look of the HUD on a screen for a window or the menu, or nil where they take the app's Appearance. Set by
    /// `DesktopApplication` at start.
    static var source: ((NSScreen?) -> HUDLook?)?

    /// The look a window or the menu on `screen` takes; nil while Match screen is off.
    static func look(on screen: NSScreen?) -> HUDLook? {
        source?(screen)
    }

    /// Every app window takes the look of its screen again: after a change of the setting, of a screen's look, of the
    /// Mac's light or dark setting, of Reduce Transparency, or of the displays.
    static func refreshAll() {
        for window in NSApp.windows {
            (window.windowController as? HostedWindowController)?.refreshLook()
        }
    }
}

extension SettingsStore {
    /// The look the app's windows and the menu take on `screen` (the main screen when nil): nil unless Match screen is
    /// on, else the look of that screen's HUD, as the panel that opens there draws it, style draft included.
    func windowLook(on screen: NSScreen?) -> HUDLook? {
        guard settings.appearanceFollowsScreen, let screen = screen ?? NSScreen.main else { return nil }
        return effectiveLook(on: ScreenIdentity.key(for: screen))
    }
}

/// What a hosted window's SwiftUI content reads of the look its window takes (`HostedWindowController.refreshLook()`):
/// nil while the window takes the app's Appearance.
@MainActor @Observable
final class WindowSurface {
    var look: HUDLook?
}

/// A window's ground, its page or its sidebar: `color`, or under a look of glass the screen's glass, the HUD's own
/// choice (`HUDLook.glassStyle`), with `color` as its dimming layer (`HUDLook.dimmingOpacity`): all of it at 0 %, where
/// the glass shows the window's own colour, and what the Transparency leaves above that, which the look carries as it is
/// drawn: 40 % of it at Clear's and Regular's top, where 60 % is drawn, and none at the material's, 100 %. Liquid Glass
/// blurs the colour beneath it with the desktop; a material, and the frosted blur that stands in for Liquid Glass, hide
/// what lies beneath them, so there the colour lies over them. Clear Liquid Glass is all but unblurred in the active
/// window, as macOS draws it, and frosted once another window is active. A solid look thins the colour as the HUD's
/// solid fill is thinned (`HUDLook.coverOpacity`), to 40 % at the top, the desktop showing through unblurred. One ground
/// is drawn wherever the window shows through, never one over another, since glass laid over glass does not see the
/// desktop.
struct WindowGround: View {
    let color: Color
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    var body: some View {
        if let look = surface?.look, look.material == .glass {
            if look.glassStyle == .material {
                Rectangle().fill(.regularMaterial)
                    .overlay { color.opacity(look.dimmingOpacity) }
            } else if HUDGlass.isLiquid {
                ZStack {
                    color.opacity(look.dimmingOpacity)
                    WindowGlass(appearance: look.appearanceName, style: look.glassStyle)
                }
            } else {
                WindowGlass(appearance: look.appearanceName, style: look.glassStyle)
                    .overlay { color.opacity(look.dimmingOpacity) }
            }
        } else {
            color.opacity(surface?.look?.coverOpacity ?? 1)
        }
    }
}

/// Liquid Glass across a window's ground, of what is behind the window, in the screen's variant, clear or regular
/// (`NSGlassEffectView`), on macOS 26 in a build made with Xcode 26 or later, and before that the HUD's frosted blur,
/// drawn the same whether the window is the active one or not. Liquid Glass sees the desktop only through a window that
/// is not opaque, which the window under a look of glass is not (`HostedWindowController.refreshLook()`).
private struct WindowGlass: NSViewRepresentable {
    let appearance: NSAppearance.Name
    let style: HUDGlassStyle

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = style == .regular ? .regular : .clear
            glass.cornerRadius = 0
            glass.appearance = NSAppearance(named: appearance)
            return glass
        }
        #endif
        let blur = NSVisualEffectView()
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: appearance)
        return blur
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.appearance?.name != appearance { view.appearance = NSAppearance(named: appearance) }
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            let variant: NSGlassEffectView.Style = style == .regular ? .regular : .clear
            if glass.style != variant { glass.style = variant }
        }
        #endif
    }
}
