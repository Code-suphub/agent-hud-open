import Foundation

/// What the bar a panel shows while a draft waits acts on: the layout draft that panel draws, its screen's style draft and
/// the app's draft, which every screen's bar shows, kept or dropped together. Either button is a person's choice, which
/// ends the agents' holds on the panels it reaches: that screen's, and for the shared draft every screen's that draws it
/// (`PanelHolds`).
public extension PanelLayoutStore {
    /// Saves what the panel on `screen` shows unsaved: the layout draft it draws (`draftScope(on:)`), the screen's style
    /// draft and the app's draft, which is written into the settings in a change of its own.
    func savePanel(on screen: String?) {
        if let screen { holds.end(screen) }
        if draftScope(on: screen) == .shared { save(.shared) }
        if let screen, hasDraft(.screen(screen)) { save(.screen(screen)) }
        saveApp()
    }

    /// Drops what the panel on `screen` shows unsaved: the layout draft it draws (`draftScope(on:)`), the screen's style
    /// draft and the app's draft.
    func discardPanel(on screen: String?) {
        if let screen { holds.end(screen) }
        if draftScope(on: screen) == .shared {
            holds.end(.shared, in: self)
            discard(.shared)
        }
        if let screen, hasDraft(.screen(screen)) { discard(.screen(screen)) }
        discardApp()
    }
}
