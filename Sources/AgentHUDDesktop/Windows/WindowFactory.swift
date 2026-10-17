import AppKit
import SwiftUI

/// Standard windows with a transparent title bar so the SwiftUI content owns the whole surface
/// (traffic lights stay native and sit over our sidebar/header, as in the design).
@MainActor
enum WindowFactory {
    static func make(size: CGSize, title: String, resizable: Bool = false) -> NSWindow {
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { mask.insert(.resizable) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = resizable
        window.center()
        return window
    }
}

/// Hosts one SwiftUI root view in a factory window. Subclasses pass the view to `setContent` after initialisation, so
/// it can call back into the controller.
class HostedWindowController: NSWindowController, NSWindowDelegate {
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))
    private let baseSize: CGSize
    /// The look the window takes from its screen, which its content reads (`WindowGround`).
    private let surface = WindowSurface()

    init(size: CGSize, title: String, resizable: Bool = false) {
        let window = WindowFactory.make(size: size, title: title, resizable: resizable)
        baseSize = size
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Replaces the root view; with `fitToContent` the window grows to the view's ideal height.
    func setContent<Content: View>(_ content: Content, fitToContent: Bool = false) {
        hosting.rootView = AnyView(content.ignoresSafeArea().environment(surface))
        guard fitToContent, let window else { return }
        hosting.sizingOptions = [.intrinsicContentSize]
        let fitting = hosting.fittingSize
        hosting.sizingOptions = []
        if fitting.height > 0 {
            window.setContentSize(CGSize(width: baseSize.width, height: max(baseSize.height, fitting.height)))
        }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window, !window.isVisible { window.center() }
        // Centring can take a hidden window to another screen, so its look is taken where it now is.
        refreshLook()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Takes the look of the screen the window is on with Match screen on, or gives the window back the
    /// app's own (`WindowLook`).
    func refreshLook() {
        guard let window else { return }
        let look = WindowLook.look(on: window.screen)
        if window.appearance?.name != look?.appearanceName {
            window.appearance = look.flatMap { NSAppearance(named: $0.appearanceName) }
        }
        // Under a look the desktop shows through, glass or a thinned solid, the window is cleared; its grounds then draw
        // all of it, and its shadow is made again from what they draw.
        let clear = look?.seeThrough == true
        if window.isOpaque == clear {
            window.isOpaque = !clear
            window.backgroundColor = clear ? .clear : .windowBackgroundColor
        }
        if surface.look != look {
            surface.look = look
            DispatchQueue.main.async { [weak window] in window?.invalidateShadow() }
        }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        refreshLook()
    }

    func windowWillClose(_ notification: Notification) {
        // The closing window is still visible during this callback. Minimized windows
        // remain open and must keep the app available in the Dock and app switcher.
        let hasOtherOpenWindow = NSApp.windows.contains {
            $0 !== window && $0.windowController is HostedWindowController
                && ($0.isVisible || $0.isMiniaturized)
        }
        if !hasOtherOpenWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
