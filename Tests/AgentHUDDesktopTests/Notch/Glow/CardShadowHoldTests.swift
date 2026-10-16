import XCTest
@testable import AgentHUDDesktop

/// A detached card's shadow waits until the card has arrived (`CardShadowHold`), step by step: the test says when each
/// wait for a card ends.
@MainActor
final class CardShadowHoldTests: XCTestCase {
    /// The hold's waits for a card, which end one at a time, oldest first, when the test says so.
    @MainActor
    private final class Arrivals {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        var count: Int { waiting.count }

        func wait() async { await withCheckedContinuation { waiting.append($0) } }
        func arrive() { waiting.removeFirst().resume() }
        func arriveAll() { while !waiting.isEmpty { arrive() } }
    }

    private let dock = HUDShell(frame: CGRect(x: 400, y: 100, width: 35, height: 120), radius: 12, flare: 0,
                                floats: true, bare: false)
    private let first = CGRect(x: 270, y: 140, width: 120, height: 26)
    private let second = CGRect(x: 270, y: 190, width: 120, height: 26)
    private let look = HUDLook(appearance: .light, material: .glass, transparency: 0.5)

    private func shells(_ card: CGRect) -> HUDShells {
        HUDShells(surface: HUDShell(frame: card, radius: 13, flare: 0, floats: true, bare: false), dock: dock)
    }

    /// A hold whose waits the test ends, and what it has revealed so far.
    private func makeHold() -> (CardShadowHold, Arrivals, () -> [(HUDShells, HUDLook)]) {
        let arrivals = Arrivals()
        let hold = CardShadowHold { await arrivals.wait() }
        var revealed: [(HUDShells, HUDLook)] = []
        hold.onReveal = { revealed.append(($0, $1)) }
        addTeardownBlock { @MainActor in arrivals.arriveAll() }
        return (hold, arrivals, { revealed })
    }

    /// Lets the hold's waits run up to where they wait, or past where they ended.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    /// A card that grows out of its dock has its shadow once it has arrived, the dock's kept meanwhile.
    func testACardThatMovesHasItsShadowOnceItHasArrived() async {
        let (hold, arrivals, revealed) = makeHold()
        let given = hold.shells(shells(first), card: first, moves: true, look: look)
        XCTAssertEqual(given.shells, HUDShells(surface: nil, dock: dock), "the dock's alone while the card grows")
        XCTAssertFalse(given.cardLeaves)
        XCTAssertFalse(given.cardSlides)
        XCTAssertEqual(hold.state, .waiting(first))
        await settle()
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertTrue(revealed().isEmpty, "nothing before the card has arrived")

        arrivals.arrive()
        await settle()
        XCTAssertEqual(hold.state, .shown(first))
        XCTAssertEqual(revealed().map { $0.0 }, [shells(first)])
        XCTAssertEqual(revealed().map { $0.1 }, [look])
    }

    /// A card placed at once, under Reduce Motion, has its shadow at once.
    func testACardPlacedAtOnceHasItsShadowAtOnce() async {
        let (hold, arrivals, revealed) = makeHold()
        let given = hold.shells(shells(first), card: first, moves: false, look: look)
        XCTAssertEqual(given.shells, shells(first))
        XCTAssertFalse(given.cardLeaves)
        XCTAssertFalse(given.cardSlides)
        XCTAssertEqual(hold.state, .shown(first))
        await settle()
        XCTAssertEqual(arrivals.count, 0, "nothing to wait for")
        XCTAssertTrue(revealed().isEmpty)
    }

    /// A shown shadow follows its card to another place, and the dock's cut fades to the card's new place; another pass
    /// with the card where it was changes nothing.
    func testAShownShadowFollowsItsCard() async {
        let (hold, arrivals, _) = makeHold()
        _ = hold.shells(shells(first), card: first, moves: false, look: look)
        let slid = hold.shells(shells(second), card: second, moves: true, look: look)
        XCTAssertEqual(slid.shells, shells(second), "the shadow goes with the card")
        XCTAssertTrue(slid.cardSlides)
        XCTAssertFalse(slid.cardLeaves)
        XCTAssertEqual(hold.state, .shown(second))
        let again = hold.shells(shells(second), card: second, moves: true, look: look)
        XCTAssertEqual(again.shells, shells(second))
        XCTAssertFalse(again.cardSlides, "nothing moved")
        await settle()
        XCTAssertEqual(arrivals.count, 0)
    }

    /// A card sent elsewhere while its shadow still waits waits again, for the new place: the old wait's end shows no
    /// shadow, and the new one's shows the shadow where the card is now.
    func testACardSentElsewhereWhileItsShadowWaitsWaitsForTheNewPlace() async {
        let (hold, arrivals, revealed) = makeHold()
        _ = hold.shells(shells(first), card: first, moves: true, look: look)
        await settle()
        let retargeted = hold.shells(shells(second), card: second, moves: true, look: look)
        XCTAssertEqual(retargeted.shells, HUDShells(surface: nil, dock: dock), "still the dock's alone")
        XCTAssertFalse(retargeted.cardSlides, "no shadow to slide yet")
        XCTAssertEqual(hold.state, .waiting(second))
        await settle()
        XCTAssertEqual(arrivals.count, 2, "a wait for the new place")

        arrivals.arrive()
        await settle()
        XCTAssertEqual(hold.state, .waiting(second), "the first place's wait is over, not the card's")
        XCTAssertTrue(revealed().isEmpty)

        arrivals.arrive()
        await settle()
        XCTAssertEqual(hold.state, .shown(second))
        XCTAssertEqual(revealed().map { $0.0 }, [shells(second)])
    }

    /// Another pass while the card is still on its way to the same place keeps the wait it has, and the shadow comes
    /// with the shells and the look of the latest pass.
    func testAnotherPassToTheSamePlaceKeepsTheWait() async {
        let (hold, arrivals, revealed) = makeHold()
        _ = hold.shells(shells(first), card: first, moves: true, look: look)
        await settle()
        let dark = HUDLook(appearance: .dark, material: .glass, transparency: 0.5)
        let given = hold.shells(shells(first), card: first, moves: true, look: dark)
        XCTAssertEqual(given.shells, HUDShells(surface: nil, dock: dock))
        await settle()
        XCTAssertEqual(arrivals.count, 1, "the same wait")

        arrivals.arrive()
        await settle()
        XCTAssertEqual(hold.state, .shown(first))
        XCTAssertEqual(revealed().map { $0.1 }, [dark])
    }

    /// A card going back into its dock drops its shadow at once, shown or still waiting; with no card there was nothing
    /// to drop.
    func testACardGoingBackDropsItsShadowAtOnce() async {
        let (hold, arrivals, revealed) = makeHold()
        let dockOnly = HUDShells(surface: nil, dock: dock)
        XCTAssertFalse(hold.shells(dockOnly, card: nil, moves: true, look: look).cardLeaves, "no card yet")

        _ = hold.shells(shells(first), card: first, moves: false, look: look)
        let back = hold.shells(dockOnly, card: nil, moves: true, look: look)
        XCTAssertTrue(back.cardLeaves)
        XCTAssertEqual(back.shells, dockOnly)
        XCTAssertEqual(hold.state, .none)

        _ = hold.shells(shells(first), card: first, moves: true, look: look)
        await settle()
        XCTAssertTrue(hold.shells(dockOnly, card: nil, moves: true, look: look).cardLeaves, "while it waits too")
        XCTAssertEqual(hold.state, .none)
        arrivals.arriveAll()
        await settle()
        XCTAssertTrue(revealed().isEmpty, "the wait ends with no shadow")
        XCTAssertEqual(hold.state, .none)
    }

    /// A card placed at once while its shadow still waits, as Reduce Motion is turned on, has it at once; the wait ends
    /// with nothing more.
    func testACardPlacedAtOnceWhileItsShadowWaitsHasItAtOnce() async {
        let (hold, arrivals, revealed) = makeHold()
        _ = hold.shells(shells(first), card: first, moves: true, look: look)
        await settle()
        let given = hold.shells(shells(second), card: second, moves: false, look: look)
        XCTAssertEqual(given.shells, shells(second))
        XCTAssertEqual(hold.state, .shown(second))
        arrivals.arriveAll()
        await settle()
        XCTAssertTrue(revealed().isEmpty)
        XCTAssertEqual(hold.state, .shown(second))
    }

    /// A closing HUD stops the wait: no shadow comes after it.
    func testCancellingStopsTheWait() async {
        let (hold, arrivals, revealed) = makeHold()
        _ = hold.shells(shells(first), card: first, moves: true, look: look)
        await settle()
        hold.cancel()
        arrivals.arriveAll()
        await settle()
        XCTAssertTrue(revealed().isEmpty)
        XCTAssertEqual(hold.state, .waiting(first))
    }
}
