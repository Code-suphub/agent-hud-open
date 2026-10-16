import AppKit
import SwiftUI
import AgentHUDCore

/// The look the app's own windows and the menu-bar menu take with Match screen on (`Settings.appearanceFollowsScreen`):
/// each as dark or light as the HUD of the screen it is on, the panel's look there (`SettingsStore.effectiveLook(on:)`),
/// and a window taken to another screen takes that screen's. With it off nothing here applies, and the windows and the
/// menu take the app's Appearance, as they always have.
///
/// A window takes the look through its appearance, which moves its tokens (`Theme.forScheme`), its controls, its sheets
/// and its popovers together, and its material through its grounds (`WindowGround`): under a look of glass the window's
/// ground and its sidebar are a blur of what is behind the window, covered with their own colour as the HUD's glass is,
/// while the cards on them keep their fill. A window changes its appearance at once, as macOS changes it.
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

/// A window's ground, its page or its sidebar: `color`, or under a look of glass a blur of what is behind the window,
/// covered with `color` as much as the screen's transparency leaves it, as the HUD's glass is (`HUDLook.coverOpacity`).
/// A solid look keeps the window opaque whatever its transparency: a window read through unblurred is no window.
struct WindowGround: View {
    let color: Color
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    var body: some View {
        if let look = surface?.look, look.material == .glass {
            WindowBlur()
                .overlay { color.opacity(look.coverOpacity) }
        } else {
            color
        }
    }
}

/// A blur of what is behind the window, in the window's own appearance: the HUD's frosted glass (`FrostedGlass`), whose
/// material lets the desktop through where a window's or a sidebar's own tints it nearly away, and drawn the same
/// whether the window is the active one or not, as the HUD's is.
private struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
