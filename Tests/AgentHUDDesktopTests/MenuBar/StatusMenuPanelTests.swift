import AppKit
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

/// The menu-bar menu as the panel the app draws (`StatusMenuPanel`): what it shows, how it is chosen from and closed,
/// how the keys move about it, and the look it takes.
final class StatusMenuPanelTests: XCTestCase {
    /// A host item's target, which counts what it is sent.
    private final class HostTarget: NSObject {
        var sent: [NSMenuItem] = []
        @objc func update(_ sender: Any?) { sent.append(sender as! NSMenuItem) }
    }

    /// The open menu shows the controller's lines in their order, the host's item between Settings and Quit, and
    /// VoiceOver finds a menu item for each row with its title and figure.
    @MainActor
    func testTheOpenMenuShowsEveryLineAndTheHostsItem() throws {
        let (controller, _, target, defaults) = try makeController()
        defer { cleanUp(controller, defaults) }
        controller.openMenu()
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(controller.isMenuOpen)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertEqual(panel.model.entries.map(\.title), controller.menuEntries().map(\.title))
        XCTAssertEqual(panel.model.entries.suffix(3).map(\.title), ["Settings…", "New Version…", "Quit"])
        XCTAssertEqual(panel.model.entries.suffix(3).map(\.value), ["⌘,", "", "⌘Q"])
        XCTAssertEqual(panel.model.entries.suffix(2).first?.titleInk, .custom(.systemBlue), "the host's own colour is kept")
        XCTAssertEqual(panel.frame.size, StatusMenuLayout.size(for: panel.model.entries))
        XCTAssertGreaterThanOrEqual(panel.frame.width, StatusMenuLayout.minimumWidth)
        let content = try XCTUnwrap(panel.contentView as? StatusMenuContentView)
        XCTAssertEqual(content.accessibilityRole(), .menu)
        let labels = content.rowElements.compactMap { $0.accessibilityLabel() }
        XCTAssertEqual(labels.suffix(3), ["Settings…, ⌘,", "New Version…", "Quit, ⌘Q"])
        XCTAssertTrue(target.sent.isEmpty)
    }

    /// Choosing the host's row sends its action to its target from the item, as a menu does, and closes the menu first;
    /// choosing Settings calls the controller's action.
    @MainActor
    func testChoosingARowPerformsItsActionAndClosesTheMenu() throws {
        let (controller, update, target, defaults) = try makeController()
        defer { cleanUp(controller, defaults) }
        var settingsOpened = 0
        controller.actions.openSettings = { settingsOpened += 1 }
        controller.openMenu()
        let panel = try XCTUnwrap(controller.panel)
        let host = try XCTUnwrap(panel.model.entries.firstIndex { $0.title == "New Version…" })
        panel.choose(at: host)
        XCTAssertEqual(target.sent.count, 1)
        XCTAssertTrue(target.sent.first === update)
        XCTAssertFalse(controller.isMenuOpen)
        XCTAssertFalse(panel.isVisible)

        controller.openMenu()
        let settings = try XCTUnwrap(panel.model.entries.firstIndex { $0.title == "Settings…" })
        let content = try XCTUnwrap(panel.contentView as? StatusMenuContentView)
        XCTAssertTrue(content.rowElements.first { $0.index == settings }?.accessibilityPerformPress() == true)
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertFalse(panel.isVisible)
    }

    /// Escape closes the menu without choosing anything, and so do ⌘, and ⌘Q choose Settings and Quit while it is open.
    @MainActor
    func testEscapeClosesAndTheShortcutsChooseWhileOpen() throws {
        let (controller, _, target, defaults) = try makeController()
        defer { cleanUp(controller, defaults) }
        var calls: [String] = []
        controller.actions = MenuActions(toggleGlow: { calls.append("glow") }, openSettings: { calls.append("settings") },
                                         openStats: { calls.append("stats") }, quit: { calls.append("quit") })
        controller.openMenu()
        let panel = try XCTUnwrap(controller.panel)
        let content = try XCTUnwrap(panel.contentView as? StatusMenuContentView)
        content.keyDown(with: key(53))
        XCTAssertFalse(controller.isMenuOpen)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(target.sent.isEmpty)

        for (character, call) in [(",", "settings"), ("q", "quit")] {
            controller.openMenu()
            XCTAssertTrue(panel.performKeyEquivalent(with: key(0, character, modifiers: .command)))
            XCTAssertEqual(calls.last, call)
            XCTAssertFalse(panel.isVisible)
        }
        controller.openMenu()
        XCTAssertFalse(panel.performKeyEquivalent(with: key(0, "w", modifiers: .command)), "a key no row has is let through")
        XCTAssertTrue(panel.isVisible)
        controller.closeMenu()
    }

    /// The arrows move the highlight over the rows that can be chosen only, past headers, separators and a disabled row,
    /// round from the last to the first; Return chooses the highlighted row; the pointer highlights only such a row.
    @MainActor
    func testArrowKeysMoveTheHighlightOverChoosableRowsOnly() throws {
        _ = NSApplication.shared
        var chosen: [String] = []
        let entries = [
            StatusMenuEntry(title: "Codex", weight: .agent, isEnabled: false),
            StatusMenuEntry(title: "5h", perform: {}),
            .separator,
            StatusMenuEntry(title: "Disabled", isEnabled: false, perform: {}),
            StatusMenuEntry(title: "Weekly", perform: {}),
            StatusMenuEntry(title: "Quit", perform: {}),
        ]
        let panel = StatusMenuPanel(look: HUDLook(appearance: .dark, material: .glass))
        defer { panel.orderOut(nil) }
        panel.onChoose = { chosen.append($0.title) }
        panel.show(entries, in: CGRect(origin: CGPoint(x: 100, y: 100), size: StatusMenuLayout.size(for: entries)))
        XCTAssertNil(panel.model.highlighted)
        var visited: [Int?] = []
        for _ in 0..<4 {
            panel.handleKey(key(125))
            visited.append(panel.model.highlighted)
        }
        XCTAssertEqual(visited, [1, 4, 5, 1])
        panel.handleKey(key(126))
        XCTAssertEqual(panel.model.highlighted, 5)
        panel.handleKey(key(126))
        XCTAssertEqual(panel.model.highlighted, 4)
        panel.handleKey(key(36))
        XCTAssertEqual(chosen, ["Weekly"])

        let content = try XCTUnwrap(panel.contentView as? StatusMenuContentView)
        let rects = StatusMenuLayout.rects(for: entries, width: panel.frame.width)
        XCTAssertEqual(content.entryIndex(at: CGPoint(x: rects[3].midX, y: rects[3].midY)), 3)
        panel.highlight(3)
        XCTAssertNil(panel.model.highlighted, "a disabled row does not highlight")
        panel.highlight(0)
        XCTAssertNil(panel.model.highlighted, "a header does not highlight")
        panel.highlight(1)
        XCTAssertEqual(panel.model.highlighted, 1)
        XCTAssertEqual(content.rowElements.filter { $0.isAccessibilitySelected() }.map(\.index), [1])
        XCTAssertEqual(content.rowElements.map(\.index), [0, 1, 3, 4, 5], "separators are not menu items")
        XCTAssertEqual(content.rowElements.map { $0.isAccessibilityEnabled() }, [false, true, false, true, true])
    }

    /// With Match screen on the menu takes the look a window on its screen takes (`WindowLook`), and takes a new one
    /// while it is open; with it off, the app's Appearance in regular glass at the standard transparency drawn at three
    /// fifths, as a screen's is, solid under Reduce Transparency. Its shadow is off wherever the desktop shows through it.
    @MainActor
    func testTheMenuTakesTheLookOfItsScreenOrTheAppsAppearance() throws {
        let (controller, _, _, defaults) = try makeController()
        let saved = (WindowLook.source, NSApp.appearance)
        defer {
            WindowLook.source = saved.0
            NSApp.appearance = saved.1
            cleanUp(controller, defaults)
        }
        let light = HUDLook(appearance: .light)
        let darkGlass = HUDLook(appearance: .dark, material: .glass, transparency: 0.95, glassStyle: .material)
        WindowLook.source = { _ in light }
        XCTAssertEqual(StatusItemController.menuLook(on: NSScreen.main), light)
        controller.openMenu()
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(panel.model.look, light)
        XCTAssertEqual(panel.appearance?.name, .aqua)
        XCTAssertTrue(panel.hasShadow)
        WindowLook.source = { _ in darkGlass }
        controller.refreshLook()
        XCTAssertEqual(panel.model.look, darkGlass)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)
        XCTAssertFalse(panel.hasShadow)
        controller.closeMenu()

        WindowLook.source = { _ in nil }
        let reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        for (appearance, shade) in [(NSAppearance.Name.aqua, HUDLook.Appearance.light), (.darkAqua, .dark)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let expected = reduces ? HUDLook(appearance: shade)
                : HUDLook(appearance: shade, material: .glass, transparency: ScreenPlacement.standardGlassTransparency * 0.6,
                          glassStyle: .regular)
            XCTAssertEqual(StatusItemController.menuLook(on: NSScreen.main), expected)
            controller.openMenu()
            XCTAssertEqual(panel.model.look, expected)
            controller.closeMenu()
        }
    }

    /// The menu opens under the status item's button, its left edge under the button's, and stays inside the screen. One
    /// taller than the room under the menu bar keeps its top under it and is cut at the bottom of the screen.
    func testTheMenuOpensUnderTheButtonInsideTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 260, height: 300)
        let under = StatusMenuLayout.frame(size: size, below: CGRect(x: 900, y: 875, width: 60, height: 24), in: visible)
        XCTAssertEqual(under, CGRect(x: 900, y: 875 - StatusMenuLayout.gapBelowMenuBar - 300, width: 260, height: 300))
        let atEdge = StatusMenuLayout.frame(size: size, below: CGRect(x: 1400, y: 875, width: 30, height: 24), in: visible)
        XCTAssertEqual(atEdge.maxX, 1436)
        let tall = StatusMenuLayout.frame(size: CGSize(width: 260, height: 2000),
                                          below: CGRect(x: 900, y: 875, width: 60, height: 24), in: visible)
        XCTAssertEqual(tall.maxY, 875 - StatusMenuLayout.gapBelowMenuBar, "the top stays under the menu bar")
        XCTAssertEqual(tall.minY, 4)
        let unplaced = StatusMenuLayout.frame(size: size, below: CGRect(x: 0, y: 0, width: 59, height: 0), in: visible)
        XCTAssertEqual(unplaced.maxY, 875 - StatusMenuLayout.gapBelowMenuBar, "a button not in the menu bar opens it from the top")
        XCTAssertEqual(unplaced.height, 300)
    }

    /// A menu cut by a short screen draws its top rows whole, the vendors and their quotas, and leaves the rest out, a
    /// separator at the cut too: neither the pointer, the arrows nor VoiceOver reach a row left out, and its shortcut
    /// still chooses it.
    @MainActor
    func testACutMenuKeepsItsTopRowsAndTheShortcutsOfTheRest() throws {
        _ = NSApplication.shared
        var chosen: [String] = []
        let quotas = (0..<4).map { StatusMenuEntry(title: "Quota \($0)", perform: {}) }
        let quit = StatusMenuEntry(title: "Quit", keyEquivalent: "q", modifiers: [.command], perform: { chosen.append("quit") })
        let entries = quotas + [.separator, quit]
        let full = StatusMenuLayout.size(for: entries)
        // Room for the four quotas and the separator, not for Quit.
        let height = full.height - StatusMenuLayout.rowHeight
        XCTAssertEqual(StatusMenuLayout.shownCount(of: entries, height: full.height), entries.count)
        XCTAssertEqual(StatusMenuLayout.shownCount(of: entries, height: height), 4, "the separator at the cut goes too")
        XCTAssertEqual(StatusMenuLayout.shownCount(of: entries, height: height - StatusMenuLayout.separatorHeight - 1), 3)

        let panel = StatusMenuPanel(look: HUDLook(appearance: .dark, material: .glass))
        defer { panel.orderOut(nil) }
        panel.onChoose = { $0.perform?() }
        panel.show(entries, in: CGRect(x: 100, y: 100, width: full.width, height: height))
        XCTAssertEqual(panel.model.shownCount, 4)
        XCTAssertEqual(panel.model.entries.count, entries.count)
        panel.highlight(5)
        XCTAssertNil(panel.model.highlighted, "a row left out does not highlight")
        panel.moveHighlight(by: -1)
        XCTAssertEqual(panel.model.highlighted, 3, "up from none takes the last row shown")
        let content = try XCTUnwrap(panel.contentView as? StatusMenuContentView)
        XCTAssertEqual(content.rowElements.map(\.index), [0, 1, 2, 3])
        let below = StatusMenuLayout.rects(for: entries, width: full.width)[5]
        XCTAssertNil(content.entryIndex(at: CGPoint(x: below.midX, y: min(below.minY + 1, height - 1))))
        XCTAssertTrue(panel.performKeyEquivalent(with: key(0, "q", modifiers: .command)))
        XCTAssertEqual(chosen, ["quit"])
    }

    /// The rows' tooltips show while the app is inactive, the usual case for a menu opened over another app.
    @MainActor
    func testRowTooltipsShowWhileTheAppIsInactive() {
        _ = NSApplication.shared
        let panel = StatusMenuPanel(look: HUDLook(appearance: .dark))
        XCTAssertTrue(panel.allowsToolTipsWhenApplicationIsInactive)
    }

    /// Only a mouse-down in the status item's window at the moment the menu closed is the click that closed it; a key at
    /// that moment, a click elsewhere or later is not. A press of the button after the menu closed by a key opens it.
    @MainActor
    func testOnlyTheClickThatClosedTheMenuKeepsItClosed() throws {
        let (controller, _, _, defaults) = try makeController()
        defer { cleanUp(controller, defaults) }
        let button = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 24), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let other = NSWindow(contentRect: CGRect(x: 60, y: 0, width: 40, height: 24), styleMask: .borderless,
                             backing: .buffered, defer: false)
        defer { button.orderOut(nil); other.orderOut(nil) }
        func event(_ type: NSEvent.EventType, at time: TimeInterval, in window: NSWindow) -> NSEvent? {
            type == .keyDown
                ? NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: time,
                                   windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
                : NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: time,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                     pressure: 1)
        }
        let closing = { (event: NSEvent?) in
            StatusItemController.isClosingClick(event, closedAt: 42, buttonWindow: button)
        }
        XCTAssertTrue(closing(event(.leftMouseDown, at: 42, in: button)))
        XCTAssertTrue(closing(event(.rightMouseDown, at: 42, in: button)))
        XCTAssertFalse(closing(event(.keyDown, at: 42, in: button)), "the key that closed it")
        XCTAssertFalse(closing(event(.leftMouseDown, at: 43, in: button)), "a later click")
        XCTAssertFalse(closing(event(.leftMouseDown, at: 42, in: other)), "a click in another window")
        XCTAssertFalse(closing(nil), "a press with no event")
        XCTAssertFalse(StatusItemController.isClosingClick(event(.leftMouseDown, at: 42, in: button), closedAt: nil,
                                                           buttonWindow: button))

        controller.openMenu()
        try XCTUnwrap(controller.panel?.contentView as? StatusMenuContentView).keyDown(with: key(53))
        XCTAssertFalse(controller.isMenuOpen)
        controller.toggleMenu()
        XCTAssertTrue(controller.isMenuOpen, "a press after Escape opens the menu")
        controller.toggleMenu()
        XCTAssertFalse(controller.isMenuOpen)
    }

    /// The menu takes the keys as it opens and gives them back as it closes to the window that had them, the island's
    /// non-activating panel with its field and caret included, whether or not the app is active; it leaves them where a
    /// click in another app took them.
    @MainActor
    func testClosingGivesTheKeysBackToTheWindowThatHadThem() throws {
        let (controller, _, _, defaults) = try makeController()
        defer { cleanUp(controller, defaults) }
        let island = OverlayPanel(frame: CGRect(x: 200, y: 200, width: 300, height: 60), level: .statusBar, acceptsMouse: true)
        let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 200, height: 22))
        field.stringValue = "Use the second one"
        island.contentView?.addSubview(field)
        island.orderFrontRegardless()
        defer { island.orderOut(nil) }
        island.takeKeyboard()
        XCTAssertTrue(island.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        editor.selectedRange = NSRange(location: 4, length: 0)
        XCTAssertTrue(island.isKeyWindow)

        controller.openMenu()
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isKeyWindow)
        XCTAssertFalse(island.isKeyWindow)
        XCTAssertNil(field.currentEditor(), "the island ends the typing as it hands the keyboard on")
        controller.closeMenu()
        XCTAssertTrue(island.isKeyWindow)
        XCTAssertEqual(field.currentEditor()?.selectedRange, NSRange(location: 4, length: 0), "the caret stands where it stood")

        controller.openMenu()
        XCTAssertTrue(panel.isKeyWindow)
        controller.closeMenu(returningKeys: false)
        XCTAssertFalse(island.isKeyWindow)
    }

    /// VoiceOver hears the menu as a menu: the highlighted row is the focused element, and the menu itself while none is.
    @MainActor
    func testTheHighlightedRowIsTheFocusedElement() throws {
        _ = NSApplication.shared
        let entries = [StatusMenuEntry(title: "5h", perform: {}), StatusMenuEntry(title: "Weekly", perform: {})]
        let panel = StatusMenuPanel(look: HUDLook(appearance: .light))
        defer { panel.orderOut(nil) }
        panel.show(entries, in: CGRect(origin: CGPoint(x: 100, y: 100), size: StatusMenuLayout.size(for: entries)))
        let content = try XCTUnwrap(panel.contentView as? StatusMenuContentView)
        XCTAssertTrue(content.accessibilityFocusedUIElement as AnyObject === content)
        panel.highlight(1)
        let focused = try XCTUnwrap(content.accessibilityFocusedUIElement as? StatusMenuRowElement)
        XCTAssertEqual(focused.index, 1)
        XCTAssertTrue(focused.isAccessibilityFocused())
        XCTAssertEqual(content.rowElements.map { $0.isAccessibilityFocused() }, [false, true])
        panel.hide()
        XCTAssertNil(panel.model.highlighted)
        XCTAssertTrue(content.accessibilityFocusedUIElement as AnyObject === content)
        XCTAssertFalse(panel.isVisible)
    }

    // MARK: Helpers

    @MainActor
    private func makeController() throws -> (StatusItemController, NSMenuItem, HostTarget, String) {
        _ = NSApplication.shared
        let suite = "StatusMenuPanelTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = SettingsStore(defaults: defaults, defaultAgents: [])
        settings.update { $0.language = .en }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        let target = HostTarget()
        let update = NSMenuItem(title: "New Version…", action: #selector(HostTarget.update(_:)), keyEquivalent: "")
        update.keyEquivalentModifierMask = []
        update.attributedTitle = NSAttributedString(string: update.title, attributes: [.foregroundColor: NSColor.systemBlue])
        update.target = target
        let controller = StatusItemController(store: store, settings: settings, additionalMenuItems: { [update] })
        return (controller, update, target, suite)
    }

    @MainActor
    private func cleanUp(_ controller: StatusItemController, _ suite: String) {
        controller.closeMenu()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        L10n.setLanguage(.system)
    }

    private func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: code)!
    }
}
