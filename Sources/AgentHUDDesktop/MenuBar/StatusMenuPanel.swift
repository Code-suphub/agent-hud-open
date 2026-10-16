import AppKit
import SwiftUI

/// The menu-bar menu, a panel the app draws itself so that it takes the look of its screen as every other surface does
/// (`StatusItemController.menuLook(on:)`), where an `NSMenu` could only be dark or light.
///
/// It behaves as a menu does. It stands at the menu's level above every app on the Space it opens on, without
/// activating the app: it becomes key to take the arrow keys, Return, Space, Escape and its rows' shortcuts, so the app
/// in front stays in front, and macOS draws Clear glass sharper in a key window, as it does in the window in use. The
/// pointer highlights a row it is over and a click chooses it; a header, a separator and a disabled row take neither.
/// Choosing a row, Escape, and the panel losing the keys close it (`onDismiss`), and its controller closes it on the
/// rest: a click elsewhere, a second click of the status item, the app resigning, a change of displays, and a change of
/// Space that leaves it behind. A menu taller than the screen keeps its top rows, the vendors and their quotas, and
/// leaves out the rows that do not fit at the bottom, whose shortcuts still choose them.
///
/// Not an `OverlayPanel`: that panel takes the keyboard only for a field the user clicked into and hands it back after,
/// where this one takes it for as long as it is open.
@MainActor
final class StatusMenuPanel: NSPanel {
    let model: StatusMenuModel
    private let content: StatusMenuContentView
    /// Called with a row the user chose, by the pointer, the keyboard or VoiceOver, before the panel closes.
    var onChoose: (StatusMenuEntry) -> Void = { _ in }
    /// Called when the panel should close without a choice: Escape, with the keys to go back to the window that had
    /// them (true), or the keys going elsewhere (false).
    var onDismiss: (_ returningKeys: Bool) -> Void = { _ in }

    init(look: HUDLook) {
        model = StatusMenuModel(look: look)
        content = StatusMenuContentView(model: model)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        acceptsMouseMovedEvents = true
        title = "Agent HUD menu"
        // The menu opens over other apps, the app itself inactive, and its rows' tooltips show all the same.
        allowsToolTipsWhenApplicationIsInactive = true
        contentView = content
        content.panel = self
        apply(look: look)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The menu keeps the frame it is given under the menu bar; AppKit would otherwise push it about.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Shows `entries` in `frame`, nothing highlighted, the rows that fit it from the top, and takes the keys. The
    /// entries come in at once, as the panel was closed, so that it does not open on a cross-fade from the last ones.
    func show(_ entries: [StatusMenuEntry], in frame: CGRect) {
        Self.withoutAnimation {
            model.entries = entries
            model.shownCount = StatusMenuLayout.shownCount(of: entries, height: frame.height)
            model.highlighted = nil
            model.size = frame.size
        }
        setFrame(frame, display: false)
        content.rebuild()
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(content)
        NSAccessibility.post(element: content, notification: StatusMenuContentView.menuOpened)
    }

    /// Puts the panel away with nothing highlighted, and tells VoiceOver the menu closed.
    func hide() {
        highlight(nil)
        NSAccessibility.post(element: content, notification: StatusMenuContentView.menuClosed)
        orderOut(nil)
    }

    /// Takes `look`: its surface and ink, its appearance for the system colours, and a shadow only where the desktop does
    /// not show through, since a shadow under a see-through menu would darken it, as the HUD keeps them from under its
    /// own see-through surfaces. An open menu changes to it as every surface does; a closed one at once, so that the next
    /// opening does not cross-fade from the old look.
    func apply(look: HUDLook) {
        if model.look != look {
            if isVisible { model.look = look } else { Self.withoutAnimation { model.look = look } }
        }
        if appearance?.name != look.appearanceName { appearance = NSAppearance(named: look.appearanceName) }
        if hasShadow == look.seeThrough {
            hasShadow = !look.seeThrough
            invalidateShadow()
        }
    }

    private static func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// The keys went to another window, which keeps them.
    override func resignKey() {
        super.resignKey()
        if isVisible { onDismiss(false) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        _ = handleKey(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss(true)
    }

    /// A row's shortcut chooses it while the menu is open: ⌘, opens Settings and ⌘Q quits, as in a menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let index = model.entries.firstIndex(where: { $0.matches(event) }) else {
            return super.performKeyEquivalent(with: event)
        }
        choose(at: index)
        return true
    }

    /// The menu's keys: the arrows move the highlight, Return, Enter and Space choose the highlighted row, and Escape
    /// closes. Any other key is let go without a beep, as a menu does.
    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: moveHighlight(by: 1)
        case 126: moveHighlight(by: -1)
        case 36, 76, 49:
            if let index = model.highlighted { choose(at: index) }
        case 53: onDismiss(true)
        default:
            if event.modifierFlags.contains(.command) { return performKeyEquivalent(with: event) }
            return false
        }
        return true
    }

    /// Moves the highlight to the next row shown that can be chosen, `step` down or up, round from the last to the first
    /// as a menu does; with none highlighted, down takes the first and up the last.
    func moveHighlight(by step: Int) {
        let selectable = model.entries.indices.filter { isHighlightable($0) }
        guard !selectable.isEmpty else { return }
        let next: Int
        if let current = model.highlighted, let position = selectable.firstIndex(of: current) {
            next = selectable[(position + step + selectable.count) % selectable.count]
        } else {
            next = step > 0 ? selectable[0] : selectable[selectable.count - 1]
        }
        highlight(next)
    }

    /// Highlights the row at `index`, or none for nil, a row that cannot be chosen or one left out at the bottom.
    func highlight(_ index: Int?) {
        let index = index.flatMap { isHighlightable($0) ? $0 : nil }
        guard model.highlighted != index else { return }
        model.highlighted = index
        content.highlightChanged()
    }

    private func isHighlightable(_ index: Int) -> Bool {
        index >= 0 && index < model.shownCount && model.entries.indices.contains(index) && model.entries[index].isSelectable
    }

    /// Chooses the row at `index` if it can be chosen.
    func choose(at index: Int) {
        guard model.entries.indices.contains(index), model.entries[index].isSelectable else { return }
        onChoose(model.entries[index])
    }
}

/// The panel's content: the drawn menu (`StatusMenuView`) and over it what the pointer and VoiceOver reach. The pointer
/// is matched against the menu's own geometry (`StatusMenuLayout`), tracked whether or not the app is active, as the
/// menu is open over other apps; each row with a tooltip shows it; and each row shown is a menu item to VoiceOver in a
/// menu, which hears it open and close as a menu's, and follows the highlighted row as the focused one.
@MainActor
final class StatusMenuContentView: NSView, NSViewToolTipOwner {
    private let model: StatusMenuModel
    private let hosting: NSHostingView<StatusMenuView>
    private var tracking: NSTrackingArea?
    private(set) var rowElements: [StatusMenuRowElement] = []
    weak var panel: StatusMenuPanel?
    /// The highlighted row's element (`accessibilityFocusedUIElement`), set on the main thread as the highlight moves.
    nonisolated(unsafe) private var focusedRow: StatusMenuRowElement?

    /// What a menu tells VoiceOver as it opens and closes, which AppKit has no names for.
    static let menuOpened = NSAccessibility.Notification(rawValue: "AXMenuOpened")
    static let menuClosed = NSAccessibility.Notification(rawValue: "AXMenuClosed")

    init(model: StatusMenuModel) {
        self.model = model
        hosting = NSHostingView(rootView: StatusMenuView(model: model))
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Agent HUD")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The pointer reaches this view, never the drawing under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    /// Lays the drawing and the rows' tooltips and elements out again for new entries.
    func rebuild() {
        hosting.frame = bounds
        removeAllToolTips()
        let rects = StatusMenuLayout.rects(for: model.entries, width: model.size.width)
        rowElements = []
        focusedRow = nil
        for (index, entry) in model.entries.prefix(model.shownCount).enumerated() where entry.kind == .item {
            if entry.toolTip != nil { addToolTip(rects[index], owner: self, userData: nil) }
            let element = StatusMenuRowElement(index: index, entry: entry, frame: rects[index], parent: self)
            element.onPress = { [weak self] in self?.panel?.choose(at: index) }
            rowElements.append(element)
        }
    }

    func highlightChanged() {
        for element in rowElements {
            element.setAccessibilitySelected(element.index == model.highlighted)
            element.setAccessibilityFocused(element.index == model.highlighted)
        }
        focusedRow = rowElements.first { $0.index == model.highlighted }
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        NSAccessibility.post(element: focusedRow ?? self, notification: .focusedUIElementChanged)
    }

    /// The entry shown under `point`, in this view's coordinates.
    func entryIndex(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        let rects = StatusMenuLayout.rects(for: model.entries, width: bounds.width).prefix(model.shownCount)
        return rects.firstIndex { $0.contains(point) }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { panel?.highlight(nil) }
    override func mouseDown(with event: NSEvent) { track(event) }

    override func mouseUp(with event: NSEvent) {
        guard let index = entryIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        panel?.choose(at: index)
    }

    override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }

    private func track(_ event: NSEvent) {
        panel?.highlight(entryIndex(at: convert(event.locationInWindow, from: nil)))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if panel?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        panel?.cancelOperation(sender)
    }

    // MARK: Tooltips and VoiceOver

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        entryIndex(at: point).flatMap { model.entries[$0].toolTip } ?? ""
    }

    override func accessibilityChildren() -> [Any]? { rowElements }

    /// The highlighted row, as a menu's selected item is to VoiceOver, or the menu while none is. AppKit's getter is not
    /// on the main actor, though AppKit calls it on the main thread only, so the row is kept where it can read it.
    override var accessibilityFocusedUIElement: Any? { focusedRow ?? self }
}

/// One row of the menu to VoiceOver: a menu item with the row's title and figure, its tooltip as help, chosen by a press,
/// and not enabled where the pointer cannot choose it either.
final class StatusMenuRowElement: NSAccessibilityElement {
    let index: Int
    /// Sendable, so that it crosses into the main actor below as Swift 6.1 requires too.
    var onPress: @MainActor @Sendable () -> Void = {}

    init(index: Int, entry: StatusMenuEntry, frame: CGRect, parent: NSView) {
        self.index = index
        super.init()
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(entry.accessibilityLabel)
        setAccessibilityHelp(entry.toolTip)
        setAccessibilityEnabled(entry.isSelectable)
        setAccessibilityParent(parent)
        // In the parent's own coordinates, which run down from its top as the menu's geometry does.
        setAccessibilityFrameInParentSpace(frame)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityEnabled() else { return false }
        // VoiceOver asks on the main thread, as AppKit does all of its accessibility.
        let press = onPress
        MainActor.assumeIsolated { press() }
        return true
    }
}
