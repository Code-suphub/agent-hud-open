import AgentHUDSupport
import Foundation
import Observation

/// The hover panel's layout on this Mac, in its three states: the saved layout (`current`), the one saved before it
/// (`previous`), and a change an agent proposed that no person has saved yet (`draft`).
///
/// The panel draws `effective`, so a draft shows at once. Only a person keeps one: `save()` makes the draft the saved
/// layout and the saved one the previous. A draft lives in memory, so a relaunch drops it. The two saved layouts are
/// one value in the defaults the store was given, written when either changes; nothing here reads a provider or
/// touches the agent list.
@MainActor
@Observable
public final class PanelLayoutStore {
    /// The saved layout, normalized.
    public private(set) var current: PanelLayout
    /// The layout that was saved before `current`, normalized; nil while there has been none.
    public private(set) var previous: PanelLayout?
    /// An agent's change waiting for a person to save or discard it, normalized and never equal to `current`.
    public private(set) var draft: PanelLayout?
    /// Counts the changes since launch, from 0: one more each time `current`, `previous` or `draft` changes, so a
    /// caller can tell that something changed since it last read.
    public private(set) var revision = 0

    private let defaults: UserDefaults
    private let encoder = RecordCoding.encoder()

    /// The layout the panel draws: the draft while there is one, else the saved layout.
    public var effective: PanelLayout { draft ?? current }
    public var hasDraft: Bool { draft != nil }
    /// Whether a previous layout exists to go back to.
    public var canRevert: Bool { previous != nil }

    /// The two saved layouts as stored: each side is a layout's JSON, and `previous` is absent while there is none.
    private struct Saved: Encodable {
        let current: PanelLayout
        let previous: PanelLayout?
    }

    /// Reads the saved layouts from `defaults` (`SettingsStore.Keys.panelLayout`), each side on its own: one that
    /// cannot be read does not lose the other. An unreadable or absent `current` is the default layout, an unreadable
    /// or absent `previous` is none.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.data(forKey: SettingsStore.Keys.panelLayout).flatMap { try? JSONValue.parse($0) }
        let sides = stored?.objectValue ?? [:]
        current = sides["current"].flatMap { PanelLayout(json: $0) }?.normalized() ?? PanelLayout()
        previous = sides["previous"].flatMap { PanelLayout(json: $0) }?.normalized()
    }

    // MARK: An agent's change

    /// Shows a layout as the draft, without saving it; a layout that is the saved one clears the draft instead.
    /// Returns whether a draft now waits.
    @discardableResult
    public func propose(_ layout: PanelLayout) -> Bool {
        let proposed = layout.normalized()
        set(current: current, previous: previous, draft: proposed == current ? nil : proposed)
        return hasDraft
    }

    /// Proposes the default view.
    @discardableResult
    public func proposeDefault() -> Bool { propose(PanelLayout()) }

    /// Proposes the previous layout. False, with nothing changed, when there is none.
    @discardableResult
    public func proposePrevious() -> Bool {
        guard let previous else { return false }
        return propose(previous)
    }

    // MARK: A person's choice

    /// Keeps the draft: it becomes the saved layout and the saved one the previous. Nothing without a draft.
    public func save() {
        guard let draft else { return }
        set(current: draft, previous: current, draft: nil)
    }

    /// Drops the draft; the panel shows the saved layout again.
    public func discard() {
        set(current: current, previous: previous, draft: nil)
    }

    /// Goes back to the previous layout: the saved and the previous layout change places, so reverting again undoes
    /// it. Without a previous layout the saved one stays. Any draft is dropped.
    public func revert() {
        set(current: previous ?? current, previous: previous == nil ? nil : current, draft: nil)
    }

    /// Goes back to the default view: the saved layout becomes the previous one, unless it already is the default. Any
    /// draft is dropped.
    public func reset() {
        set(current: PanelLayout(), previous: current.isDefault ? previous : current, draft: nil)
    }

    // MARK: State

    /// Takes the three states: one revision when any of them differs, and one write when a saved one does.
    private func set(current: PanelLayout, previous: PanelLayout?, draft: PanelLayout?) {
        let saves = current != self.current || previous != self.previous
        guard saves || draft != self.draft else { return }
        if current != self.current { self.current = current }
        if previous != self.previous { self.previous = previous }
        if draft != self.draft { self.draft = draft }
        revision += 1
        if saves { persist() }
    }

    /// Writes both saved layouts at once, with sorted keys. The default layout with no previous one is no stored value.
    private func persist() {
        guard previous != nil || !current.isDefault else {
            defaults.removeObject(forKey: SettingsStore.Keys.panelLayout)
            return
        }
        guard let data = try? encoder.encode(Saved(current: current, previous: previous)) else { return }
        defaults.set(data, forKey: SettingsStore.Keys.panelLayout)
    }
}
