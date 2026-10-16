import Foundation

/// The looping state a mark shows: what its agents are doing, as far as its bot acts it out. Cases run from the
/// highest to the lowest, the order a mark's sessions are merged in.
enum BotLook: Hashable, Sendable, CaseIterable {
    /// A tool waits for the user's approval.
    case permission
    /// The agent has asked the user a question.
    case question
    /// A plan waits for the user's approval.
    case plan
    /// Claude is compacting its context.
    case compacting
    /// A turn runs and no tool is open: the model is working something out.
    case thinking
    /// A turn runs a tool. Clawd plays a clip for each kind; every other bot has one motion for them all.
    case tool(BotTool)
    /// A turn runs, for a client whose logs carry no tool calls.
    case plain
    /// A session is in flight by evidence older than half an hour: nothing says what it is doing now.
    case noNews
    /// Nothing is in flight: the mark rests as its logo, with a brief bot visit now and then.
    case idle
    /// Every session of the mark has been idle for an hour or more, or it has none: a doze now and then.
    case asleep
    /// A turn just ended, on its reply card: the bot smiles. A dock never shows it.
    case done

    static let allCases: [BotLook] = [.permission, .question, .plan, .compacting, .thinking]
        + BotTool.allCases.map { .tool($0) } + [.plain, .noNews, .idle, .asleep, .done]

    /// A request waits on the user.
    var isAttention: Bool { self == .permission || self == .question || self == .plan }

    /// A turn runs.
    var isWorking: Bool {
        switch self {
        case .compacting, .thinking, .tool, .plain: true
        default: false
        }
    }

    /// The mark rests as its logo.
    var isCalm: Bool { self == .noNews || self == .idle || self == .asleep }

    /// The mark stays where its logo is, with no hop and nothing raised.
    var staysInPlace: Bool { isWorking || isCalm }
}

/// The tool a working turn has open, or opened last.
enum BotTool: Hashable, Sendable, CaseIterable {
    case edit, command, read
    /// A shell command open for twenty seconds or more.
    case longCommand
}

/// Something that just happened to a mark's agent, played once over its look, which then carries on.
enum BotEvent: Hashable, Sendable, CaseIterable {
    /// Work begins after a long rest.
    case start
    /// A turn ended in an error.
    case failed
    /// A turn ended on a usage limit.
    case limitHit

    /// An event that waits longer than this to play, because the bot was busy or not yet up, is let go.
    static let freshness: TimeInterval = 3

    /// Of two events, the one to keep: failed over a limit hit over a start.
    var rank: Int {
        switch self {
        case .start: 0
        case .limitHit: 1
        case .failed: 2
        }
    }
}

/// A still sign a mark wears after an event, until its agent moves on. It never animates and needs no clock.
enum BotBadge: Hashable, Sendable {
    /// The agent's last turn failed.
    case failed
    /// The agent is held up by a usage limit.
    case limited
}

/// Everything a mark is told about its agents at one moment.
struct BotState: Hashable, Sendable {
    var look: BotLook = .idle
    /// Sub-agents are running for the working session: a small, still copy of the body stands beside it.
    var subagents = false
    var badge: BotBadge? = nil
    /// The pointer rests on the mark, or its card is open. A resting mark, or one with a badge, comes up and greets;
    /// a busy one only turns its eyes to the pointer.
    var hovered = false
    /// The look holds still, with no clock: a turn quiet for three minutes, or a request being retried.
    var holds = false

    /// The phase that tells the same story, for callers that still speak in phases.
    var phase: BotPhase {
        if look.isAttention { return .asking }
        if look.isWorking { return .working }
        if look == .done { return .done }
        return hovered ? .opened : .idle
    }

    /// The sign a still logo shows for this state, with bots off or motion reduced: a waiting request's or a badge's,
    /// never one that belongs to a moving bot.
    var stillSign: BotSign? {
        var sign: BotSign?
        switch look {
        case .permission: sign = .exclamation
        case .question: sign = .question
        case .plan: sign = .lines
        default: break
        }
        return BotSign.shown(sign, badge.map(BotSign.init))
    }
}

/// One event as a view is told of it: what happened and when, so a mark built again later does not play it twice,
/// and a mark told too late lets it go.
struct BotCue: Hashable, Sendable {
    var event: BotEvent
    var at: Date
}

/// What the agent behind a mark is doing, in the five phases marks were first told: each is now a `BotState`.
enum BotPhase: Sendable, Equatable {
    /// Nothing in flight: the mark rests as its logo, with a brief bot visit now and then.
    case idle
    /// A turn is running: the bot stays awake and acts in place.
    case working
    /// A turn is blocked on the user: the bot hops, stays raised and turns to face them.
    case asking
    /// A turn just ended: the bot smiles.
    case done
    /// The agent's own card is open, from a hover or a click: the bot is up and watches the pointer for as long as
    /// the card stays open.
    case opened

    /// The mark stays where its logo is, with no hop and nothing raised.
    var staysInPlace: Bool { self == .working || self == .idle || self == .opened }

    /// The state this phase stands for: working is the plain working look, asking a permission, opened an idle mark
    /// under the pointer.
    var state: BotState {
        switch self {
        case .idle: BotState()
        case .working: BotState(look: .plain)
        case .asking: BotState(look: .permission)
        case .done: BotState(look: .done)
        case .opened: BotState(look: .idle, hovered: true)
        }
    }
}
