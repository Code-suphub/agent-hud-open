import AppKit
import SwiftUI
import AgentHUDCore

/// The look the app's own windows and the menu-bar menu take under Appearance → Match screen (`AppearanceMode.screen`):
/// each as dark or light as the HUD of the screen it is on, the panel's look there (`SettingsStore.effectiveLook(on:)`),
/// and a window taken to another screen takes that screen's. Under any other Appearance nothing here applies, and the
/// windows and the menu take the app's own, as they always have.
///
/// A window takes the look through its appearance, which moves its tokens (`Theme.forScheme`), its controls, its sheets
/// and its popovers together. Glass reaches a window only where macOS itself draws a window translucent, its sidebar
/// (`WindowGround`): the statistics and the settings stay on an opaque ground, which their charts and small grey text
/// need over any desktop. A window changes its appearance at once, as macOS changes it.
@MainActor
enum WindowLook {
    /// The look of the HUD on a screen for a window or the menu, or nil where they take the app's Appearance. Set by
    /// `DesktopApplication` at start.
    static var source: ((NSScreen?) -> HUDLook?)?

    /// The look a window or the menu on `screen` takes; nil while Appearance is not Match screen.
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
    /// The look the app's windows and the menu take on `screen` (the main screen when nil): nil unless Appearance is
    /// Match screen, else the look of that screen's HUD, as the panel that opens there draws it, style draft included.
    func windowLook(on screen: NSScreen?) -> HUDLook? {
        guard settings.appearance == .screen, let screen = screen ?? NSScreen.main else { return nil }
        return effectiveLook(on: ScreenIdentity.key(for: screen))
    }
}

/// What a hosted window's SwiftUI content reads of the look its window takes (`HostedWindowController.refreshLook()`):
/// nil while the window takes the app's Appearance.
@MainActor @Observable
final class WindowSurface {
    var look: HUDLook?
}

/// A window's ground where macOS draws a window translucent, its sidebar: `color`, or under a look of glass a blur of
/// what is behind the window, covered with `color` at the screen's transparency, as the HUD's glass is
/// (`HUDLook.glassCover`).
struct WindowGround: View {
    let color: Color
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    var body: some View {
        if let look = surface?.look, look.material == .glass {
            WindowBlur()
                .overlay { color.opacity(1 - look.transparency) }
        } else {
            color
        }
    }
}

/// The blur of a sidebar: what is behind the window, in the window's own appearance, dimmed as macOS dims a sidebar
/// when its window is not the active one.
private struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .sidebar
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
