import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// The look the app's own windows and the menu-bar menu take under Appearance → Match screen (`WindowLook`): the look of
/// the HUD on the screen they are on, nothing under any other Appearance, a window that takes it, or gives it back, as
/// the look it is given changes, and the grounds a window draws under a look of glass (`WindowGround`).
@MainActor
final class WindowLookTests: XCTestCase {
    /// Sets where the windows' look comes from for one test, and when it ends gives back none, as a process without
    /// `DesktopApplication` has. Kept in the test rather than in `setUp`, which is not on the main actor.
    private func giveLooks(_ source: @escaping (NSScreen?) -> HUDLook?) {
        _ = NSApplication.shared
        WindowLook.source = source
    }

    private func store() -> SettingsStore {
        let suite = "app.agenthud.tests.window-look.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
    }

    // MARK: Where the look comes from

    /// With Match screen off the windows and the menu take the app's own Appearance, System, Light or Dark, whatever a
    /// screen's HUD looks like: there is no look for them on any screen.
    func testOnlyMatchScreenGivesTheWindowsALook() {
        let settings = store()
        settings.update {
            for display in NSScreen.screens {
                $0.screens[ScreenIdentity.key(for: display)] = ScreenPlacement(mode: .simple, appearance: .light,
                                                                               material: .glass)
            }
        }
        for appearance in [AppearanceMode.system, .light, .dark] {
            settings.update { $0.appearance = appearance }
            XCTAssertNil(settings.windowLook(on: nil), "\(appearance)")
            for display in NSScreen.screens {
                XCTAssertNil(settings.windowLook(on: display), "\(appearance)")
            }
        }
    }

    /// With Match screen on a window on a screen takes the look of that screen's HUD, as the panel that opens there draws
    /// it, its style draft included; with no screen named it takes the main screen's.
    func testMatchScreenGivesEachScreensHUDLook() throws {
        let settings = store()
        settings.update { $0.appearanceFollowsScreen = true }
        try XCTSkipIf(NSScreen.screens.isEmpty, "no display is attached to take a look from")
        for display in NSScreen.screens {
            let key = ScreenIdentity.key(for: display)
            XCTAssertEqual(settings.windowLook(on: display), settings.effectiveLook(on: key), key)
            settings.update { $0.screens[key] = ScreenPlacement(mode: .simple, appearance: .light) }
            XCTAssertEqual(settings.windowLook(on: display)?.appearance, .light, key)
            settings.panelLayout.proposeStyle(HUDStyle(appearance: .dark), for: key, hasNotch: ScreenIdentity.hasNotch(display))
            XCTAssertEqual(settings.windowLook(on: display)?.appearance, .dark, "the style draft is drawn over the settings")
            settings.panelLayout.discardStyle(key)
        }
        if let main = NSScreen.main {
            XCTAssertEqual(settings.windowLook(on: nil), settings.windowLook(on: main))
        }
    }

    // MARK: A window that takes it

    /// A hosted window takes the look its screen gives it as its appearance, light or dark, and again whenever it is
    /// asked to, as on a move to another screen; given none, it takes the app's own again.
    func testAWindowTakesTheLookOfItsScreen() throws {
        let controller = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Look")
        let window = try XCTUnwrap(controller.window)
        XCTAssertNil(window.appearance)

        var look: HUDLook? = HUDLook(appearance: .light)
        giveLooks { _ in look }
        defer { WindowLook.source = nil }
        controller.refreshLook()
        XCTAssertEqual(window.appearance?.name, .aqua)

        look = HUDLook(appearance: .dark, material: .glass)
        controller.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification, object: window))
        XCTAssertEqual(window.appearance?.name, .darkAqua, "a move to another screen takes that screen's look")

        look = nil
        controller.refreshLook()
        XCTAssertNil(window.appearance, "under any other Appearance the window takes the app's")
    }

    /// Under a look of glass a hosted window is cleared, not opaque and with no background of its own, so that the
    /// glass of its grounds sees the desktop behind it, whatever the glass is made of and bare at the top of the
    /// Transparency too; under a solid look, with a transparency or without, and under none, it is opaque on the window
    /// background again.
    func testAWindowIsClearedUnderGlassOnly() throws {
        let controller = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Glass")
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .windowBackgroundColor)

        var look: HUDLook? = HUDLook(appearance: .dark, material: .glass)
        giveLooks { _ in look }
        defer { WindowLook.source = nil }
        for style in HUDGlassStyle.allCases {
            look = HUDLook(appearance: .dark, material: .glass, transparency: 0.5, glassStyle: style)
            controller.refreshLook()
            XCTAssertFalse(window.isOpaque, "\(style)")
            XCTAssertEqual(window.backgroundColor, .clear, "\(style)")
        }

        look = HUDLook(appearance: .light, material: .solid, transparency: 0.4)
        controller.refreshLook()
        XCTAssertTrue(window.isOpaque, "a solid look keeps the window opaque whatever its transparency")
        XCTAssertEqual(window.backgroundColor, .windowBackgroundColor, "solid")

        look = HUDLook(appearance: .light, material: .glass, transparency: 1)
        controller.refreshLook()
        XCTAssertFalse(window.isOpaque, "bare glass")
        XCTAssertEqual(window.backgroundColor, .clear, "bare glass")

        look = nil
        controller.refreshLook()
        XCTAssertTrue(window.isOpaque, "under any other Appearance the window is a window again")
        XCTAssertEqual(window.backgroundColor, .windowBackgroundColor, "no look")
    }

    // MARK: Its ground

    /// The ground of a window under a look of glass, its page's or its sidebar's, is the glass the screen's HUD has, in
    /// the look's appearance, so that every surface on the screen is one glass. Clear or regular, it is Liquid Glass of
    /// that variant on macOS 26 in a build made with Xcode 26 or later (`NSGlassEffectView`), and before that the HUD's
    /// frosted blur of what is behind the window, drawn the same whether the window is active or not; clear Liquid
    /// Glass is all but unblurred in the active window, as macOS draws it. A material is SwiftUI's regular material on
    /// any Mac, which SwiftUI draws itself, with no glass or blur view of AppKit's. Under a solid look, with a
    /// transparency or without, the ground is its plain colour, with neither.
    func testAWindowsGroundIsTheScreensGlassUnderGlassOnly() throws {
        let looks: [(String, HUDLook)] = [
            ("dark clear glass", HUDLook(appearance: .dark, material: .glass, glassStyle: .clear)),
            ("dark regular glass", HUDLook(appearance: .dark, material: .glass, glassStyle: .regular)),
            ("dark material", HUDLook(appearance: .dark, material: .glass, glassStyle: .material)),
            ("light clear glass at the top", HUDLook(appearance: .light, material: .glass, transparency: 1)),
            ("light regular glass at the top",
             HUDLook(appearance: .light, material: .glass, transparency: 1, glassStyle: .regular)),
            ("light material at the top",
             HUDLook(appearance: .light, material: .glass, transparency: 1, glassStyle: .material)),
            ("light solid", HUDLook(appearance: .light, transparency: 0.4)),
            ("standard", .standard),
        ]
        for (name, look) in looks {
            let views = try ground(in: look).views
            let glass = look.material == .glass && look.glassStyle != .material
            let blurs = views.compactMap { $0 as? NSVisualEffectView }.filter { $0.material == .hudWindow }
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                let panes = views.compactMap { $0 as? NSGlassEffectView }
                XCTAssertEqual(panes.count, glass ? 1 : 0, name)
                for pane in panes {
                    XCTAssertEqual(pane.style, look.glassStyle == .regular ? .regular : .clear, "\(name): its variant")
                    XCTAssertEqual(pane.appearance?.name, look.appearanceName, name)
                }
                XCTAssertTrue(blurs.isEmpty, name)
                continue
            }
            #endif
            XCTAssertEqual(blurs.count, glass ? 1 : 0, name)
            for blur in blurs {
                XCTAssertEqual(blur.material, .hudWindow, name)
                XCTAssertEqual(blur.blendingMode, .behindWindow, name)
                XCTAssertEqual(blur.state, .active, "\(name): the same whether the window is active or not")
                XCTAssertEqual(blur.appearance?.name, look.appearanceName, name)
            }
        }
    }

    /// A ground's glass takes a change of the screen's glass where it is, as the window shows it: the same glass turns
    /// light with the look and, as Liquid Glass, regular or clear; a material puts it away, and glass again brings it
    /// back.
    func testAWindowsGroundTakesAChangeOfGlass() throws {
        _ = NSApplication.shared
        let surface = WindowSurface()
        surface.look = HUDLook(appearance: .dark, material: .glass, glassStyle: .clear)
        let hosting = NSHostingView(rootView: WindowGround(color: .red).environment(surface))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
        // The views as SwiftUI leaves them once it has taken the change.
        func settled() -> [NSView] {
            hosting.layoutSubtreeIfNeeded()
            return tree(hosting)
        }
        let before = try XCTUnwrap(Self.glass(in: tree(hosting)), "clear glass")
        XCTAssertEqual(before.appearance?.name, .darkAqua)

        surface.look = HUDLook(appearance: .light, material: .glass, glassStyle: .regular)
        poll("the glass takes the light look") { Self.glass(in: settled())?.appearance?.name == .aqua }
        let after = try XCTUnwrap(Self.glass(in: settled()), "regular glass")
        XCTAssertTrue(after === before, "the same glass, changed where it is")
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            XCTAssertEqual((after as? NSGlassEffectView)?.style, .regular)
            surface.look = HUDLook(appearance: .light, material: .glass, glassStyle: .clear)
            poll("the glass turns clear again") { (Self.glass(in: settled()) as? NSGlassEffectView)?.style == .clear }
        }
        #endif

        surface.look = HUDLook(appearance: .light, material: .glass, glassStyle: .material)
        poll("a material puts the glass away") { Self.glass(in: settled()) == nil }
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            XCTAssertTrue(settled().allSatisfy { !($0 is NSVisualEffectView) }, "SwiftUI draws the material itself")
        }
        #endif
        surface.look = HUDLook(appearance: .light, material: .glass, glassStyle: .regular)
        poll("glass brings it back") { Self.glass(in: settled()) != nil }
    }

    /// A ground's dimming is the window's own colour at what the screen's Transparency leaves of it, all of it at 0,
    /// half at 0.5 and none at 1, the bare glass: beneath Liquid Glass, which blurs it with the desktop, and over a
    /// material or the frosted blur, which hide what lies beneath them. The glass itself is drawn whole at any setting:
    /// nothing between it and the window is faded. Each ground is compared with its bare glass, drawn with no colour,
    /// and the colour laid at its share beneath or over it as the ground lays it, in the same drawing, since glass off
    /// screen has nothing behind it to show and draws as it does there. A solid ground is its plain colour, opaque,
    /// whatever its transparency.
    func testAWindowsGroundDimsWholeGlassWithItsColour() throws {
        for appearance in [HUDLook.Appearance.dark, .light] {
            let solid = HUDLook(appearance: appearance, transparency: 0.4)
            let plain = try drawn(in: solid) { Color.red }.middle, laidSolid = try ground(in: solid).middle
            for channel in [\NSColor.redComponent, \.greenComponent, \.blueComponent] {
                XCTAssertEqual(laidSolid[keyPath: channel], plain[keyPath: channel], accuracy: 0.01,
                               "\(appearance): solid")
            }
            for style in HUDGlassStyle.allCases {
                let beneath = style != .material && HUDGlass.isLiquid
                for (transparency, share) in [(0.0, 1.0), (0.5, 0.5), (1.0, 0.0)] {
                    let look = HUDLook(appearance: appearance, material: .glass, transparency: transparency,
                                       glassStyle: style)
                    let what = "\(appearance) \(style) \(transparency)"
                    let laid = try ground(in: look)
                    let bare = WindowGround(color: .clear)
                    let colour = Color.red.opacity(share)
                    let expected = try beneath
                        ? drawn(in: look) { ZStack { colour; bare } }.middle
                        : drawn(in: look) { ZStack { bare; colour } }.middle
                    for channel in [\NSColor.redComponent, \.greenComponent, \.blueComponent] {
                        XCTAssertEqual(laid.middle[keyPath: channel], expected[keyPath: channel], accuracy: 0.02, what)
                    }
                    guard let glass = laid.glass else { continue }
                    let hosting = try XCTUnwrap(laid.views.first)
                    for view in sequence(first: glass, next: { $0 === hosting ? nil : $0.superview }) {
                        XCTAssertEqual(view.alphaValue, 1, "\(what): \(type(of: view))")
                        XCTAssertEqual(view.layer?.opacity ?? 1, 1, "\(what): \(type(of: view))")
                    }
                }
            }
        }
    }

    /// Every hosted window takes its look again at once, as after a change of the setting or of a screen's look.
    func testEveryWindowTakesItsLookAgain() throws {
        let one = HostedWindowController(size: CGSize(width: 320, height: 200), title: "One")
        let two = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Two")
        // Never shown: the app's windows are every one it has, on screen or not.
        let windows = try [XCTUnwrap(one.window), XCTUnwrap(two.window)]

        giveLooks { _ in HUDLook(appearance: .light) }
        defer { WindowLook.source = nil }
        WindowLook.refreshAll()
        XCTAssertEqual(windows.map { $0.appearance?.name }, [.aqua, .aqua])
        giveLooks { _ in nil }
        WindowLook.refreshAll()
        XCTAssertEqual(windows.map { $0.appearance?.name }, [nil, nil])
    }

    // MARK: Helpers

    /// Waits for the main run loop to bring `condition` about, for up to two seconds.
    private func poll(_ what: String, line: UInt = #line, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), what, line: line)
    }

    /// A window's ground in `look`, of `color`, as a hosted window draws it (`drawn(in:_:)`).
    private func ground(in look: HUDLook, color: Color = .red) throws
        -> (views: [NSView], glass: NSView?, middle: NSColor) {
        try drawn(in: look) { WindowGround(color: color) }
    }

    /// `content` drawn as a hosted window draws its grounds: given the look by its surface, in a window of the look's
    /// appearance that is never shown, over a grey standing in for what is behind it, and laid out. Its AppKit views,
    /// its hosting view first; the glass among them; and the colour in its middle, drawn off screen.
    private func drawn<Content: View>(in look: HUDLook, _ content: () -> Content) throws
        -> (views: [NSView], glass: NSView?, middle: NSColor) {
        _ = NSApplication.shared
        let surface = WindowSurface()
        surface.look = look
        let size = CGSize(width: 200, height: 120)
        let hosting = NSHostingView(rootView: content().environment(surface).background(Color(white: 0.5)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: look.appearanceName)
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
        let views = tree(hosting)
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let middle = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        return (views, Self.glass(in: views), middle)
    }

    /// The glass among a ground's views: Liquid Glass where the build and the Mac have it, the frosted blur everywhere
    /// else. A material has neither.
    private static func glass(in views: [NSView]) -> NSView? {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return views.first { $0 is NSGlassEffectView } }
        #endif
        return views.first { ($0 as? NSVisualEffectView)?.material == .hudWindow }
    }
}
