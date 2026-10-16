import Foundation
import Observation

/// The holds agents' edits put on screens' hover panels: while a hold is on, that screen's panel stays open whether or not
/// the pointer is over it, so a person sees an agent's change as it is made. A hold is one screen's, by screen key, and
/// lasts `duration` from the last edit that started or renewed it (`hold(_:agent:)`). A call that changes only the
/// screen's resting HUD pauses it (`pause(_:)`): the panel closes so the HUD shows, and the next layout edit opens it
/// again. A hold ends when its time passes (`expire()`), when the agent says its edit is done (`end(_:)`, `endAll()`),
/// and at once when a person takes over: a person's choice about a layout (`end(_:in:)`) or anything the person does on
/// the HUD, which its host tells it of. From then on the panel behaves as a hovered panel does.
///
/// Holds live in memory and are no part of the layouts: they count no revision, write no settings and start no read.
/// The host opens and closes the panels that follow them, and opens a held panel without the account read a hover's
/// opening starts. They run on a clock of their own, the wall clock, since the store's may be a demo's.
@MainActor
@Observable
public final class PanelHolds {
    /// How long a hold lasts after the edit that started or renewed it.
    public static let duration: TimeInterval = 120

    /// One screen's hold.
    public struct Hold: Equatable, Sendable {
        /// When it ends unless an edit renews it first.
        public let until: Date
        /// Whether a call that changed only the screen's resting HUD closed the panel, so the HUD shows.
        public let paused: Bool
        /// The agent the edits touched first, by vendor, whose own card a dock that separates its agents opens; nil opens
        /// the first agent that dock shows.
        public let agent: String?
    }

    private var holds: [String: Hold] = [:]
    /// The time holds run on, and the wait until it reaches a time; a test sets both, so two minutes pass on its own
    /// clock without waiting.
    @ObservationIgnored var clock: @MainActor () -> Date = { Date() }
    @ObservationIgnored var sleep: @MainActor (Date) async -> Void = { until in
        try? await Task.sleep(for: .seconds(max(0.001, until.timeIntervalSinceNow)))
    }
    /// Ends the holds whose time has passed, once the earliest of them has.
    @ObservationIgnored private var expiry: Task<Void, Never>?

    public init() {}

    /// The hold on `screen` while its time has not passed; nil without one.
    public func hold(on screen: String) -> Hold? {
        guard let hold = holds[screen], hold.until > clock() else { return nil }
        return hold
    }

    /// The time the hold on `screen` has left; nil without one.
    public func remaining(on screen: String) -> TimeInterval? {
        hold(on: screen).map { $0.until.timeIntervalSince(clock()) }
    }

    /// The screens a hold is on now, in key order.
    public var screens: [String] { holds.keys.filter { hold(on: $0) != nil }.sorted() }

    // MARK: An agent's edit

    /// Starts the hold on `screen`, or renews it, for `duration` from now, and opens it again where it was paused.
    /// - agent: the agent the edit touched first, by vendor; nil keeps the one the hold has.
    func hold(_ screen: String, agent: String?) {
        holds[screen] = Hold(until: clock().addingTimeInterval(Self.duration), paused: false,
                             agent: agent ?? hold(on: screen)?.agent)
        schedule()
    }

    /// Pauses the hold on `screen`, if any: its panel closes, so the resting HUD an agent restyled shows, and its time
    /// runs on.
    func pause(_ screen: String) {
        guard let held = hold(on: screen), !held.paused else { return }
        holds[screen] = Hold(until: held.until, paused: true, agent: held.agent)
    }

    // MARK: Ending

    /// Ends the hold on `screen` at once: the agent said its edit is done, or a person took over.
    public func end(_ screen: String) {
        guard holds[screen] != nil else { return }
        holds[screen] = nil
        schedule()
    }

    /// Ends every hold at once.
    public func endAll() {
        guard !holds.isEmpty else { return }
        holds = [:]
        schedule()
    }

    /// Ends the holds a person's choice about `scope`'s layout takes over: a screen's own, or for the shared layout
    /// every screen that draws it.
    func end(_ scope: PanelLayoutScope, in layout: PanelLayoutStore) {
        switch scope {
        case .screen(let key): end(key)
        case .shared:
            for key in holds.keys where layout.usesShared(key) { end(key) }
        }
    }

    /// Ends the holds whose time has passed, which the panels that follow them see; the host's panels close then.
    func expire() {
        let now = clock()
        for key in holds.filter({ $0.value.until <= now }).keys { holds[key] = nil }
        schedule()
    }

    /// Waits for the earliest hold's time to pass, in place of any wait before.
    private func schedule() {
        expiry?.cancel()
        expiry = nil
        guard let next = holds.values.map(\.until).min() else { return }
        let sleep = sleep
        expiry = Task { [weak self] in
            await sleep(next)
            guard !Task.isCancelled else { return }
            self?.expire()
        }
    }
}
