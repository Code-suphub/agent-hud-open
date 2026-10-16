import CoreGraphics

/// Holds a detached card's shadow back until the card has arrived, for one screen's HUD (`ScreenHUD`). The glow draws a
/// card's shadow where the card ends up, with the card cut out of it, while the card is still growing out of its dock
/// or sliding to that place; on a light desktop the cut would show there as a pale pill with a shadow round it, ahead
/// of the card. So the shadow waits for the card's motion to end, `IslandAnimation.duration` after it last began, and
/// then fades in, and the dock's shadow is cut by the card from then on too: cut while the card still grows, it would
/// show the same pale place beside the panel. A card that moves once its shadow shows keeps it, which follows the card,
/// and the dock's cut, which cannot follow it, fades to the card's new place as it goes there (`cardSlides`). A card
/// placed at once, under Reduce Motion, has its shadow at once. On its way back into the dock, its shadow shown or
/// still waiting, the card drops it at once, which `cardLeaves` tells the glow (`GlowWindowController.update`); any
/// other shell's shadow that goes fades out.
@MainActor
final class CardShadowHold {
    /// Where a detached card's shadow stands.
    enum State: Equatable {
        case none
        /// Held back until the card, growing out of its dock or moving to this place, has arrived.
        case waiting(CGRect)
        /// Under the card at this place.
        case shown(CGRect)
    }

    private(set) var state = State.none
    /// Called once a held-back card has arrived, with the shells the glow is to give shadows now, the card's among
    /// them, and the look they are cast in.
    var onReveal: (_ shells: HUDShells, _ look: HUDLook) -> Void = { _, _ in }
    /// Waits as long as a card takes to arrive: the island's motion, or a test's own wait.
    private let arrival: @MainActor @Sendable () async -> Void
    private var wait: Task<Void, Never>?
    /// The shells a held-back card's shadow is given once the card has arrived, and the look they are cast in.
    private var held: (shells: HUDShells, look: HUDLook)?

    init(arrival: @escaping @MainActor @Sendable () async -> Void = {
        try? await Task.sleep(for: .seconds(IslandAnimation.duration))
    }) {
        self.arrival = arrival
    }

    /// The shells the glow gives shadows now: `shells`, less a detached card's until the card has arrived.
    /// - card: where the detached card is on screen; nil where there is none, or once it goes back into its dock.
    /// - moves: whether the card moves there, growing or sliding, rather than being placed at once.
    func shells(_ shells: HUDShells, card: CGRect?, moves: Bool,
                look: HUDLook) -> (shells: HUDShells, cardLeaves: Bool, cardSlides: Bool) {
        guard let card, moves else {
            let leaves = card == nil && state != .none
            cancel()
            held = nil
            state = card.map(State.shown) ?? .none
            return (shells, leaves, false)
        }
        switch state {
        case .shown(let place):
            state = .shown(card)
            return (shells, false, place != card)
        case .waiting(card):
            break
        case .none, .waiting:
            state = .waiting(card)
            wait?.cancel()
            wait = Task { [weak self, arrival] in
                await arrival()
                guard !Task.isCancelled, let self, self.state == .waiting(card) else { return }
                self.wait = nil
                self.reveal()
            }
        }
        held = (shells, look)
        return (HUDShells(surface: nil, dock: shells.dock), false, false)
    }

    /// Stops waiting for a card, and leaves its shadow where it stands: the HUD is closing.
    func cancel() {
        wait?.cancel()
        wait = nil
    }

    /// The card has arrived: its shadow is shown under it.
    private func reveal() {
        guard case .waiting(let card) = state, let held else { return }
        state = .shown(card)
        self.held = nil
        onReveal(held.shells, held.look)
    }
}
