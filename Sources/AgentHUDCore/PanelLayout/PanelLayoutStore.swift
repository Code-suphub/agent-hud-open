import AgentHUDSupport
import Foundation
import Observation

/// Which layout document an action is for: the shared one, or one screen's own, by its screen key.
public enum PanelLayoutScope: Hashable, Sendable {
    case shared
    case screen(String)

    /// The screen's key; nil for the shared layout.
    public var screenKey: String? {
        if case .screen(let key) = self { return key }
        return nil
    }
}

/// The hover panel's layouts on this Mac: a shared layout, and for any screen an own layout it uses whole instead. Each
/// is a document in three states: the saved layout (`current`), the one saved before it (`previous`), and a change an
/// agent proposed that no person has saved yet (`draft`). A screen's draft can also be to use the shared layout again.
///
/// A screen's panel draws `effective(for:)`, so a draft shows at once. Only a person keeps one: `save(_:)` makes the
/// draft the saved layout and the saved one the previous. A draft lives in memory, so a relaunch drops it. The saved
/// layouts are one value in the defaults the store was given (`PanelLayoutStorage`), written when any of them changes,
/// and a screen that is not attached keeps its own layout for when it returns. Nothing here reads a provider or
/// touches the agent list. The methods without a scope act on the shared layout.
@MainActor
@Observable
public final class PanelLayoutStore {
    /// The shared saved layout, normalized.
    public private(set) var current: PanelLayout
    /// The shared layout that was saved before `current`, normalized; nil while there has been none.
    private(set) var previous: PanelLayout?
    /// An agent's change to the shared layout waiting for a person to save or discard it, normalized and never equal to
    /// `current`.
    private(set) var draft: PanelLayout?
    /// The screens' own documents, by screen key, each normalized and never empty.
    private(set) var screens: [String: PanelScreenDocument]
    /// Counts the changes since launch, from 0, across every document: one more each time a saved layout, a previous
    /// one or a draft changes, so a caller can tell that something changed since it last read.
    private(set) var revision = 0

    private let defaults: UserDefaults

    /// The shared layout as the panels that use it draw it: its draft while there is one, else the saved layout.
    public var effective: PanelLayout { draft ?? current }
    /// Whether the shared layout has a draft.
    public var hasDraft: Bool { draft != nil }
    /// Whether the shared layout has a previous one to go back to.
    public var canRevert: Bool { previous != nil }

    /// Reads the saved layouts from `defaults` (`SettingsStore.Keys.panelLayout`), each side and each screen on its
    /// own, so one that cannot be read does not lose the rest.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = PanelLayoutStorage.read(defaults.data(forKey: SettingsStore.Keys.panelLayout))
        current = saved.current
        previous = saved.previous
        screens = saved.screens
    }

    // MARK: Reading a screen

    /// The layout the panel on `screen` draws: the screen's draft or its saved own layout where it has one, else the
    /// shared layout's draft or saved layout. Nil, or a screen without a document, is the shared layout.
    public func effective(for screen: String?) -> PanelLayout {
        guard let screen, let document = screens[screen] else { return effective }
        return (document.draft ?? document.current).layout ?? effective
    }

    /// Whether the panel on `screen` draws the shared layout now, a draft included.
    public func usesShared(_ screen: String?) -> Bool {
        guard let screen, let document = screens[screen] else { return true }
        return (document.draft ?? document.current) == .shared
    }

    /// The saved own layout of `screen`; nil while it uses the shared layout.
    public func ownLayout(of screen: String) -> PanelLayout? { screens[screen]?.current.layout }

    /// The draft of `screen`'s own document: a layout, or `.shared` to use the shared layout; nil without one.
    public func draft(of screen: String) -> PanelScreenLayout? { screens[screen]?.draft }

    /// The choice saved before `screen`'s saved one; nil while there has been none.
    func previous(of screen: String) -> PanelScreenLayout? { screens[screen]?.previous }

    /// The document whose draft the panel on `screen` shows, which the Save and Discard in its bar act on: the screen's
    /// own draft, else the shared draft while the screen draws the shared layout; nil when it shows none.
    public func draftScope(on screen: String?) -> PanelLayoutScope? {
        if let screen, screens[screen]?.draft != nil { return .screen(screen) }
        return usesShared(screen) && draft != nil ? .shared : nil
    }

    /// Whether the panel on `screen` shows a draft and the bar that says so.
    public func hasDraft(on screen: String?) -> Bool { draftScope(on: screen) != nil }

    /// Whether a scope has a draft of its own.
    func hasDraft(_ scope: PanelLayoutScope) -> Bool {
        switch scope {
        case .shared: draft != nil
        case .screen(let key): screens[key]?.draft != nil
        }
    }

    /// Whether a scope has a previous layout to go back to.
    public func canRevert(_ scope: PanelLayoutScope) -> Bool {
        switch scope {
        case .shared: previous != nil
        case .screen(let key): screens[key]?.previous != nil
        }
    }

    /// The screens with a document of their own, saved or a draft, in key order.
    var screenKeys: [String] { screens.keys.sorted() }

    // MARK: An agent's change

    /// Shows a layout as the shared draft, without saving it; a layout that is the saved one clears the draft instead.
    /// Returns whether a draft now waits.
    @discardableResult
    public func propose(_ layout: PanelLayout) -> Bool {
        let proposed = layout.normalized()
        set(current: current, previous: previous, draft: proposed == current ? nil : proposed)
        return hasDraft
    }

    /// Shows a choice as `screen`'s draft, without saving it: a layout of its own, or the shared layout. A choice that
    /// is the saved one clears the draft instead. Returns whether a draft now waits for the screen.
    @discardableResult
    public func propose(_ choice: PanelScreenLayout, for screen: String) -> Bool {
        var document = screens[screen] ?? PanelScreenDocument()
        let proposed = choice.normalized()
        document.draft = proposed == document.current ? nil : proposed
        set(screen: screen, document)
        return hasDraft(.screen(screen))
    }

    /// Proposes the default view for a scope: the shared layout's, or a screen's own.
    @discardableResult
    func proposeDefault(_ scope: PanelLayoutScope = .shared) -> Bool {
        switch scope {
        case .shared: propose(PanelLayout())
        case .screen(let key): propose(.own(PanelLayout()), for: key)
        }
    }

    /// Proposes a scope's previous layout. False, with nothing changed, when there is none.
    @discardableResult
    func proposePrevious(_ scope: PanelLayoutScope = .shared) -> Bool {
        switch scope {
        case .shared:
            guard let previous else { return false }
            return propose(previous)
        case .screen(let key):
            guard let previous = screens[key]?.previous else { return false }
            return propose(previous, for: key)
        }
    }

    // MARK: A person's choice

    /// Keeps a scope's draft: it becomes the saved layout and the saved one the previous. A screen's draft to use the
    /// shared layout removes the screen's own layout, which becomes its previous. Nothing without a draft.
    public func save(_ scope: PanelLayoutScope = .shared) {
        switch scope {
        case .shared:
            guard let draft else { return }
            set(current: draft, previous: current, draft: nil)
        case .screen(let key):
            guard var document = screens[key], let draft = document.draft else { return }
            document = PanelScreenDocument(current: draft, previous: document.current, draft: nil)
            set(screen: key, document)
        }
    }

    /// Drops a scope's draft; its panels show the saved layout again.
    public func discard(_ scope: PanelLayoutScope = .shared) {
        switch scope {
        case .shared:
            set(current: current, previous: previous, draft: nil)
        case .screen(let key):
            guard var document = screens[key] else { return }
            document.draft = nil
            set(screen: key, document)
        }
    }

    /// Goes back to a scope's previous layout: the saved and the previous one change places, so reverting again undoes
    /// it. Without a previous layout the saved one stays. Any draft of the scope is dropped.
    public func revert(_ scope: PanelLayoutScope = .shared) {
        switch scope {
        case .shared:
            set(current: previous ?? current, previous: previous == nil ? nil : current, draft: nil)
        case .screen(let key):
            guard let document = screens[key] else { return }
            set(screen: key, PanelScreenDocument(current: document.previous ?? document.current,
                                                 previous: document.previous == nil ? nil : document.current))
        }
    }

    /// Goes back to the default view: the saved layout becomes the previous one, unless it already is the default. For
    /// a screen, the default view becomes its own layout. Any draft of the scope is dropped.
    public func reset(_ scope: PanelLayoutScope = .shared) {
        switch scope {
        case .shared:
            set(current: PanelLayout(), previous: current.isDefault ? previous : current, draft: nil)
        case .screen(let key):
            let document = screens[key] ?? PanelScreenDocument()
            let reset = PanelScreenLayout.own(PanelLayout())
            set(screen: key, PanelScreenDocument(current: reset,
                                                 previous: document.current == reset ? document.previous : document.current))
        }
    }

    /// Lets `screen` use the shared layout again at once: its own layout becomes its previous one. Any draft of the
    /// screen is dropped.
    public func useShared(_ screen: String) {
        guard let document = screens[screen] else { return }
        set(screen: screen, PanelScreenDocument(current: .shared,
                                                previous: document.current == .shared ? document.previous : document.current))
    }

    // MARK: The panel's bar

    /// Saves the draft the panel on `screen` shows (`draftScope(on:)`).
    public func savePanel(on screen: String?) {
        if let scope = draftScope(on: screen) { save(scope) }
    }

    /// Drops the draft the panel on `screen` shows (`draftScope(on:)`).
    public func discardPanel(on screen: String?) {
        if let scope = draftScope(on: screen) { discard(scope) }
    }

    // MARK: State

    /// Takes the shared document's three states: one revision when any of them differs, and one write when a saved one
    /// does.
    private func set(current: PanelLayout, previous: PanelLayout?, draft: PanelLayout?) {
        let saves = current != self.current || previous != self.previous
        guard saves || draft != self.draft else { return }
        if current != self.current { self.current = current }
        if previous != self.previous { self.previous = previous }
        if draft != self.draft { self.draft = draft }
        revision += 1
        if saves { persist() }
    }

    /// Takes a screen's document, which an empty one removes: one revision when it differs, and one write when what
    /// it saves does.
    private func set(screen key: String, _ document: PanelScreenDocument) {
        let old = screens[key] ?? PanelScreenDocument()
        guard document != old else { return }
        screens[key] = document.isEmpty ? nil : document
        revision += 1
        if document.current != old.current || document.previous != old.previous { persist() }
    }

    /// Writes every saved layout at once, with sorted keys; nothing to keep is no stored value.
    private func persist() {
        let saved = PanelLayoutStorage.Saved(current: current, previous: previous, screens: screens)
        if let data = PanelLayoutStorage.write(saved) {
            defaults.set(data, forKey: SettingsStore.Keys.panelLayout)
        } else {
            defaults.removeObject(forKey: SettingsStore.Keys.panelLayout)
        }
    }
}
