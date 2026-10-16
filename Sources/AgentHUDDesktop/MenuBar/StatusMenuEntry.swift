import AppKit
import SwiftUI
import AgentHUDCore

/// One line of the menu-bar menu (`StatusMenuPanel`): a row the user can choose, a header that only names what follows,
/// or a separator. Rows are drawn in the look of the menu's screen, so what a row says carries no colour of its own, only
/// which of the look's inks it takes (`Ink`).
struct StatusMenuEntry {
    enum Kind: Equatable {
        case item
        case separator
    }

    /// What stands in the 16 pt column before the title.
    enum Icon {
        case none
        /// The vendor's mark, in its version for the look's appearance.
        case artwork(vendor: String)
        /// A 7 pt dot in the level's colour, or the look's tertiary grey for a row with no level.
        case dot(StatusLevel?)
        /// A host item's own image; a template image takes the row's ink.
        case image(NSImage)
        /// A host item's check mark or dash (`NSMenuItem.state`).
        case state(NSControl.StateValue)
    }

    enum Weight {
        /// 13 pt bold: a vendor's name.
        case agent
        /// 13 pt: a row or an action.
        case regular
        /// 11 pt: an account's header.
        case small

        var size: CGFloat { self == .small ? 11 : 13 }
        var fontWeight: NSFont.Weight { self == .agent ? .bold : .regular }
    }

    /// Which of the look's inks a text takes (`color(in:)`).
    enum Ink: Equatable {
        case primary
        case secondary
        case tertiary
        /// A critical level's text colour: a balance or a quota that has run out.
        case critical
        /// A host item's own colour, read from its attributed title, such as the update item's blue.
        case custom(NSColor)

        func color(in theme: Theme) -> Color {
            switch self {
            case .primary: theme.text
            case .secondary: theme.secondary
            case .tertiary: theme.tertiary
            case .critical: theme.statusText(.critical)
            case .custom(let color): Color(nsColor: color)
            }
        }
    }

    var kind: Kind = .item
    var title = ""
    /// The figure or shortcut at the right edge.
    var value = ""
    var icon: Icon = .none
    var weight: Weight = .regular
    var titleInk: Ink = .primary
    var valueInk: Ink = .secondary
    var toolTip: String?
    var isEnabled = true
    /// The key that chooses the row while the menu is open, with its modifiers: ⌘, for Settings, ⌘Q for Quit.
    var keyEquivalent = ""
    var modifiers: NSEvent.ModifierFlags = []
    /// What choosing the row does; nil for a header.
    var perform: (@MainActor () -> Void)?

    static var separator: StatusMenuEntry { StatusMenuEntry(kind: .separator) }

    /// Whether the row highlights under the pointer and the arrow keys, and can be chosen: an enabled row with an action.
    var isSelectable: Bool { kind == .item && isEnabled && perform != nil }

    /// What VoiceOver reads: the title, then the figure.
    var accessibilityLabel: String { value.isEmpty ? title : "\(title), \(value)" }

    /// The shortcut as a menu writes it, ⌥⌘H.
    static func shortcut(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        guard !key.isEmpty else { return "" }
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }

    /// Whether `event` is this row's key equivalent: the same key, ignoring case, with the same command, option, control
    /// and shift keys down.
    func matches(_ event: NSEvent) -> Bool {
        guard isSelectable, !keyEquivalent.isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(), key == keyEquivalent.lowercased() else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.modifierFlags.intersection(relevant) == modifiers.intersection(relevant)
    }
}

/// The menu's geometry, which the rows are drawn to (`StatusMenuView`) and the pointer is matched against
/// (`StatusMenuContentView`): rows 24 pt high, separators 11, 5 pt above the first and below the last, 250 pt wide at
/// the least and as wide as its widest row needs.
enum StatusMenuLayout {
    static let rowHeight: CGFloat = 24
    static let separatorHeight: CGFloat = 11
    static let verticalInset: CGFloat = 5
    static let inset: CGFloat = 10
    static let iconWidth: CGFloat = 16
    static let iconGap: CGFloat = 4
    static let valueGap: CGFloat = 20
    static let minimumWidth: CGFloat = 250
    static let cornerRadius: CGFloat = 10
    static let selectionInset: CGFloat = 5
    static let selectionRadius: CGFloat = 6
    /// Between the bottom of the menu bar and the top of the menu.
    static let gapBelowMenuBar: CGFloat = 4

    static func height(of entry: StatusMenuEntry) -> CGFloat {
        entry.kind == .separator ? separatorHeight : rowHeight
    }

    /// Each entry's rect, from the top of a view `width` wide whose y runs down.
    static func rects(for entries: [StatusMenuEntry], width: CGFloat) -> [CGRect] {
        var y = verticalInset
        return entries.map { entry in
            defer { y += height(of: entry) }
            return CGRect(x: 0, y: y, width: width, height: height(of: entry))
        }
    }

    static func size(for entries: [StatusMenuEntry]) -> CGSize {
        let width = entries.reduce(minimumWidth) { width, entry in
            guard entry.kind == .item else { return width }
            let title = NSAttributedString(string: entry.title, attributes: [
                .font: NSFont.systemFont(ofSize: entry.weight.size, weight: entry.weight.fontWeight),
            ])
            let value = NSAttributedString(string: entry.value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: entry.weight.size, weight: .regular),
            ])
            return max(width, inset + iconWidth + iconGap + title.size().width + valueGap + value.size().width + inset)
        }
        let height = entries.reduce(2 * verticalInset) { $0 + Self.height(of: $1) }
        return CGSize(width: ceil(width), height: height)
    }

    /// Where a menu `size` opens under `anchor`, the status item's button on screen: its left edge under the button's,
    /// its top `gapBelowMenuBar` below it, kept 4 pt inside the screen's visible frame. A button that does not reach up
    /// to the menu bar is one macOS has not placed there, such as one with no room beside the notch, and the menu opens
    /// from the top of the visible frame instead. A menu taller than the room under the menu bar is cut to it, its top
    /// kept where it is (`shownCount`).
    static func frame(size: CGSize, below anchor: CGRect, in visible: CGRect) -> CGRect {
        let margin: CGFloat = 4
        var x = anchor.minX
        x = min(x, visible.maxX - margin - size.width)
        x = max(x, visible.minX + margin)
        let menuBarBottom = anchor.maxY >= visible.maxY - 1 ? min(anchor.minY, visible.maxY) : visible.maxY
        let top = menuBarBottom - gapBelowMenuBar
        let height = max(0, min(size.height, top - visible.minY - margin))
        return CGRect(x: x, y: top - height, width: size.width, height: height)
    }

    /// How many of `entries`, from the top, a menu `height` high draws whole above its bottom inset: all of them unless
    /// the screen is too short for the menu, when the rows at the bottom are left out, and with them a separator the cut
    /// would leave last. The top rows are the vendors and their quotas, which the menu is opened for; the actions at the
    /// bottom keep their shortcuts.
    static func shownCount(of entries: [StatusMenuEntry], height: CGFloat) -> Int {
        let bottom = height - verticalInset
        var count = rects(for: entries, width: 0).prefix { $0.maxY <= bottom }.count
        if count < entries.count {
            while count > 0, entries[count - 1].kind == .separator { count -= 1 }
        }
        return count
    }
}
