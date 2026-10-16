import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// The look the app's own windows and the menu-bar menu take under Appearance → Match screen (`WindowLook`): the look of
/// the HUD on the screen they are on, nothing under any other Appearance, a window that takes it, or gives it back, as
/// the look it is given changes, the grounds a window draws under a look the desktop shows through (`WindowGround`), and
/// the settings groups that stand on them.
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

    /// With Match screen on a window takes the transparency its screen's HUD draws, not the slider's: three fifths of
    /// it for Solid, clear glass and regular glass, 0.6 at the top, and all of it for the material, so that the windows
    /// and the HUD on a screen are one surface; none under Reduce Transparency, which draws the window opaque. A window
    /// under any of the others is cleared, the desktop showing through it.
    func testAWindowTakesTheTransparencyItsScreenDraws() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no display is attached to take a look from")
        let settings = store()
        settings.update { $0.appearanceFollowsScreen = true }
        let controller = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Transparency")
        let window = try XCTUnwrap(controller.window)
        giveLooks { settings.windowLook(on: $0) }
        defer { WindowLook.source = nil }
        let reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let cases: [(String, ScreenPlacement, Double)] = [
            ("glass as first chosen", ScreenPlacement(mode: .simple, material: .glass), 0.3),
            ("clear glass at the top", ScreenPlacement(mode: .simple, material: .glass, glassTransparency: 1), 0.6),
            ("regular glass at the top",
             ScreenPlacement(mode: .simple, material: .glass, glassStyle: .regular, glassTransparency: 1), 0.6),
            ("the material at the top",
             ScreenPlacement(mode: .simple, material: .glass, glassStyle: .material, glassTransparency: 1), 1),
            ("the material at 50 %",
             ScreenPlacement(mode: .simple, material: .glass, glassStyle: .material, glassTransparency: 0.5), 0.5),
            ("solid at the top", ScreenPlacement(mode: .simple, solidTransparency: 1), 0.6),
            ("solid at 50 %", ScreenPlacement(mode: .simple, solidTransparency: 0.5), 0.3),
        ]
        for (name, placement, drawn) in cases {
            settings.update {
                for display in NSScreen.screens { $0.screens[ScreenIdentity.key(for: display)] = placement }
            }
            for display in NSScreen.screens {
                XCTAssertEqual(settings.windowLook(on: display)?.transparency, reduces ? 0 : drawn,
                               "\(name) on \(ScreenIdentity.key(for: display))")
            }
            controller.refreshLook()
            XCTAssertEqual(WindowLook.look(on: window.screen)?.transparency, reduces ? 0 : drawn, name)
            XCTAssertEqual(window.isOpaque, reduces, "\(name): cleared unless Reduce Transparency draws it opaque")
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

    /// Under a look the desktop shows through a hosted window is cleared, not opaque and with no background of its own,
    /// so that its grounds draw all of it: under glass, whatever the glass is made of, at 0 and at the top of what the
    /// Transparency draws, 0.6 for Liquid Glass and 1 for the material, so that the glass sees the desktop behind it;
    /// and under a solid look with a transparency, so that the thinned fill shows the desktop unblurred. Under a solid look with none, and under no look, it is opaque on
    /// the window background again.
    func testAWindowIsClearedWheneverTheDesktopShowsThrough() throws {
        let controller = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Glass")
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .windowBackgroundColor)

        var look: HUDLook? = HUDLook(appearance: .dark, material: .glass)
        giveLooks { _ in look }
        defer { WindowLook.source = nil }
        func assertCleared(_ cleared: Bool, _ what: String, line: UInt = #line) {
            XCTAssertEqual(window.isOpaque, !cleared, what, line: line)
            XCTAssertEqual(window.backgroundColor, cleared ? .clear : .windowBackgroundColor, what, line: line)
        }
        for style in HUDGlassStyle.allCases {
            for transparency in [0, 0.3, style == .material ? 1 : 0.6] {
                look = HUDLook(appearance: .dark, material: .glass, transparency: transparency, glassStyle: style)
                controller.refreshLook()
                assertCleared(true, "\(style) \(transparency)")
            }
        }

        look = HUDLook(appearance: .light, material: .solid)
        controller.refreshLook()
        assertCleared(false, "an opaque solid look")

        for transparency in [0.03, 0.3, 0.6] {
            look = HUDLook(appearance: .light, material: .solid, transparency: transparency)
            controller.refreshLook()
            assertCleared(true, "solid at \(transparency)")
        }

        look = .standard
        controller.refreshLook()
        assertCleared(false, "the standard look, opaque again")

        look = HUDLook(appearance: .light, material: .glass, transparency: 0.6)
        controller.refreshLook()
        assertCleared(true, "glass at the top")

        look = nil
        controller.refreshLook()
        assertCleared(false, "under any other Appearance the window is a window again")
    }

    /// A window's content reads the look the window takes, and reads it again on every change, so its grounds and its
    /// cards follow; with no look, nothing.
    func testAWindowsContentReadsTheLookItTakes() throws {
        let controller = HostedWindowController(size: CGSize(width: 320, height: 200), title: "Surface")
        let seen = SurfaceSeen()
        controller.setContent(SurfaceProbe(seen: seen))
        let hosting = try XCTUnwrap(controller.window?.contentView)
        var look: HUDLook? = HUDLook(appearance: .light, transparency: 0.4)
        giveLooks { _ in look }
        defer { WindowLook.source = nil }
        controller.refreshLook()
        poll("the content reads the look") {
            hosting.layoutSubtreeIfNeeded()
            return seen.look == look
        }
        look = HUDLook(appearance: .dark, material: .glass, transparency: 0.6, glassStyle: .regular)
        controller.refreshLook()
        poll("and reads it again on a change") {
            hosting.layoutSubtreeIfNeeded()
            return seen.look == look
        }
        look = nil
        controller.refreshLook()
        poll("and none once the window takes the app's Appearance") {
            hosting.layoutSubtreeIfNeeded()
            return seen.look == nil
        }
    }

    // MARK: Its ground

    /// The ground of a window under a look of glass, its page's or its sidebar's, is the glass the screen's HUD has, in
    /// the look's appearance, so that every surface on the screen is one glass. Clear or regular, it is Liquid Glass of
    /// that variant on macOS 26 in a build made with Xcode 26 or later (`NSGlassEffectView`), and before that the HUD's
    /// frosted blur of what is behind the window, drawn the same whether the window is active or not; clear Liquid
    /// Glass is all but unblurred in the active window, as macOS draws it. A material is SwiftUI's regular material on
    /// any Mac, which SwiftUI draws itself, with no glass or blur view of AppKit's. Under a solid look, with a
    /// transparency or without, the ground is its colour, with neither.
    func testAWindowsGroundIsTheScreensGlassUnderGlassOnly() throws {
        let looks: [(String, HUDLook)] = [
            ("dark clear glass", HUDLook(appearance: .dark, material: .glass, glassStyle: .clear)),
            ("dark regular glass", HUDLook(appearance: .dark, material: .glass, glassStyle: .regular)),
            ("dark material", HUDLook(appearance: .dark, material: .glass, glassStyle: .material)),
            ("light clear glass at the top", HUDLook(appearance: .light, material: .glass, transparency: 0.6)),
            ("light regular glass at the top",
             HUDLook(appearance: .light, material: .glass, transparency: 0.6, glassStyle: .regular)),
            ("light material at the top",
             HUDLook(appearance: .light, material: .glass, transparency: 1, glassStyle: .material)),
            ("light solid at the top", HUDLook(appearance: .light, transparency: 0.6)),
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

    /// A ground's dimming is the window's own colour at what the transparency drawn leaves of it, all of it at 0, 0.7 at
    /// the standard glass's 0.3, 0.4 at Liquid Glass's top of 0.6 and none at the material's top of 1, the bare
    /// material: beneath Liquid Glass, which blurs it with the desktop, and over a material or the frosted blur, which
    /// hide what lies beneath them. The glass itself is drawn
    /// whole at any setting: nothing between it and the window is faded. Each ground is compared with its bare glass,
    /// drawn with no colour, and the colour laid at its share beneath or over it as the ground lays it, in the same
    /// drawing, since glass off screen has nothing behind it to show and draws as it does there. A solid ground is its
    /// colour at what the transparency drawn leaves of its fill (`HUDLook.coverOpacity`), as the HUD's solid fill is:
    /// whole at 0, 0.7 at 0.3 and 0.4 at its top of 0.6, over what is behind the window, unblurred.
    func testAWindowsGroundDimsWholeGlassWithItsColour() throws {
        for appearance in [HUDLook.Appearance.dark, .light] {
            for (transparency, share) in [(0.0, 1.0), (0.3, 0.7), (0.6, 0.4)] {
                let solid = HUDLook(appearance: appearance, transparency: transparency)
                XCTAssertEqual(solid.coverOpacity, share, accuracy: 0.0001, "\(appearance) solid \(transparency)")
                let plain = try drawn(in: solid) { Color.red.opacity(share) }.middle
                let laidSolid = try ground(in: solid)
                XCTAssertNil(laidSolid.glass, "\(appearance) solid \(transparency): no glass")
                for channel in [\NSColor.redComponent, \.greenComponent, \.blueComponent] {
                    XCTAssertEqual(laidSolid.middle[keyPath: channel], plain[keyPath: channel], accuracy: 0.01,
                                   "\(appearance) solid \(transparency)")
                }
            }
            for style in HUDGlassStyle.allCases {
                let beneath = style != .material && HUDGlass.isLiquid
                let top = style == .material ? 1.0 : 0.6
                for (transparency, share) in [(0.0, 1.0), (0.3, 0.7), (top, 1 - top)] {
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

    // MARK: What stands on it

    /// A settings group's card, Settings → General's and every page's, takes the window's tokens on the ground its look
    /// gives it (`Theme.under(_:)`): on a light ground the desktop shows through, the white card is drawn at the share
    /// the look leaves of it, 0.76 at the standard glass's 0.3 and a fifth at the material's top of 1, solid or glass,
    /// so that the desktop shows through it as through the dark card's tint of white; on an opaque light ground it is white, and on a dark
    /// ground it is the dark card, a tint of white, at any transparency. Each card is drawn in a hosted window over black,
    /// and compared with the colour it should be drawn the same way.
    func testASettingsCardThinsWithTheWindowsGround() throws {
        let card = { Color.clear.frame(width: 160, height: 80).settingsCard() }
        let cases: [(String, HUDLook, Color)] = [
            ("light opaque", HUDLook(appearance: .light), Theme.light.card),
            ("light solid at 0.3", HUDLook(appearance: .light, transparency: 0.3), Theme.light.card.opacity(0.76)),
            ("light glass at 0.3", HUDLook(appearance: .light, material: .glass, transparency: 0.3),
             Theme.light.card.opacity(0.76)),
            ("light material at the top", HUDLook(appearance: .light, material: .glass, transparency: 1,
                                                  glassStyle: .material), Theme.light.card.opacity(0.2)),
            ("dark opaque", .standard, Theme.dark.card),
            ("dark glass at 0.6", HUDLook(appearance: .dark, material: .glass, transparency: 0.6), Theme.dark.card),
        ]
        for (name, look, expected) in cases {
            let drawn = try hosted(in: look) { ZStack { Color.black; card() } }
            let should = try plainly { ZStack { Color.black; Color.clear.frame(width: 160, height: 80).background(expected) } }
            for channel in [\NSColor.redComponent, \.greenComponent, \.blueComponent] {
                XCTAssertEqual(drawn[keyPath: channel], should[keyPath: channel], accuracy: 0.02, name)
            }
        }
        let opaque = try hosted(in: HUDLook(appearance: .light)) { ZStack { Color.black; card() } }
        let thin = try hosted(in: HUDLook(appearance: .light, material: .glass, transparency: 0.3)) {
            ZStack { Color.black; card() }
        }
        XCTAssertGreaterThan(opaque.redComponent, 0.95, "white, opaque")
        XCTAssertLessThan(thin.redComponent, opaque.redComponent - 0.1, "the black behind shows through")
    }

    /// A settings group stands its rows on that same card, which follows the window's ground as a card alone does.
    func testASettingsSectionStandsOnACardThatFollowsTheLook() throws {
        let section = {
            ZStack {
                Color.black
                SettingsSection(title: "Group", subtitle: "What it holds") { Color.clear.frame(width: 160, height: 80) }
            }
        }
        for (look, share) in [(HUDLook(appearance: .light), 1.0),
                              (HUDLook(appearance: .light, material: .glass, transparency: 0.3), 0.76),
                              (HUDLook(appearance: .light, transparency: 0.6), 0.52)] {
            let what = "\(look.material) at \(look.transparency)"
            // The middle of the rows, below the title and the subtitle.
            let drawn = try hosted(in: look, at: CGPoint(x: 0.5, y: 0.62), section)
            let should = try plainly { ZStack { Color.black; Theme.light.card.opacity(share) } }
            XCTAssertEqual(drawn.redComponent, should.redComponent, accuracy: 0.02, what)
        }
    }

    /// A box raised off a window's ground, a chart's hover details, casts its shadow on an opaque ground, as it always
    /// has with no look, and none on a ground the desktop shows through, glass or a thinned solid, where a shadow would
    /// darken the box and the desktop round it. Measured on a white page just past the box's lower edge, where the
    /// shadow falls.
    func testARaisedBoxCastsAShadowOnAnOpaqueGroundOnly() throws {
        func beneath(_ look: HUDLook?) throws -> CGFloat {
            _ = NSApplication.shared
            let surface = WindowSurface()
            surface.look = look
            let page = ZStack {
                Color.white
                Color.clear.frame(width: 120, height: 40).raisedBox(Theme.light)
            }
            .frame(width: 200, height: 120)
            .environment(surface)
            let hosting = NSHostingView(rootView: page)
            hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
            hosting.layoutSubtreeIfNeeded()
            // The box's lower edge is 80 points down; 4 more is in its shadow.
            return try color(of: hosting, at: CGPoint(x: 0.5, y: 84.0 / 120)).redComponent
        }
        XCTAssertLessThan(try beneath(nil), 0.98, "a shadow under no look")
        XCTAssertLessThan(try beneath(HUDLook(appearance: .light)), 0.98, "and on an opaque ground")
        for look in [HUDLook(appearance: .light, material: .glass, transparency: 0.3),
                     HUDLook(appearance: .light, material: .glass, transparency: 1, glassStyle: .material),
                     HUDLook(appearance: .light, transparency: 0.3)] {
            XCTAssertEqual(try beneath(look), 1, accuracy: 0.005, "\(look.material) at \(look.transparency): no shadow")
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

    /// The colour at `point`, a share of the window's width and height from its top left, the middle by default, of
    /// `content` in a hosted window that takes `look` as it does with Match screen on, never shown, drawn off screen.
    private func hosted<Content: View>(in look: HUDLook, at point: CGPoint = CGPoint(x: 0.5, y: 0.5),
                                       _ content: () -> Content) throws -> NSColor {
        let controller = HostedWindowController(size: CGSize(width: 240, height: 200), title: "Card")
        controller.setContent(content())
        giveLooks { _ in look }
        defer { WindowLook.source = nil }
        controller.refreshLook()
        let hosting = try XCTUnwrap(controller.window?.contentView)
        // SwiftUI takes the window's new look on its next update.
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        return try color(of: hosting, at: point)
    }

    /// The colour in the middle of `content` drawn alone, in no window, as `hosted(in:at:_:)` draws.
    private func plainly<Content: View>(_ content: () -> Content) throws -> NSColor {
        let hosting = NSHostingView(rootView: content())
        hosting.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        hosting.layoutSubtreeIfNeeded()
        return try color(of: hosting, at: CGPoint(x: 0.5, y: 0.5))
    }

    private func color(of view: NSView, at point: CGPoint) throws -> NSColor {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let x = Int(CGFloat(rep.pixelsWide) * point.x), y = Int(CGFloat(rep.pixelsHigh) * point.y)
        return try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
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

/// What a probe last read of the look its window takes.
@MainActor
private final class SurfaceSeen {
    var look: HUDLook?
}

private struct SurfaceProbe: View {
    let seen: SurfaceSeen
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    var body: some View {
        seen.look = surface?.look
        return Color.clear
    }
}
