import Foundation

/// Which sessions the hover panel's rows list under a layout, in what order, and how many rows they take: a layout's
/// `sessions` in effect (`PanelLayout.Sessions`). `PanelSessionFilter()` lists the default view's five rows of every
/// session of the last day, those in flight first.
public struct PanelSessionFilter: Hashable, Sendable {
    /// How many rows the section shows at most.
    let limit: Int
    /// How long after its last event an ended session is still listed.
    let period: PanelSessionPeriod
    /// How the rows are ordered.
    let sort: PanelSessionSort
    /// The marks (`VendorMark.key`) of the agents whose sessions are listed; empty for every agent.
    let agents: Set<String>
    /// The ids of the projects whose sessions are listed (`SessionProject.id`); empty for every project.
    let projects: Set<String>
    /// The states listed; empty for every state.
    let states: Set<PanelSessionState>

    public init(_ sessions: PanelLayout.Sessions = PanelLayout.Sessions()) {
        limit = sessions.rowLimit
        period = sessions.listedPeriod
        sort = sessions.rowSort
        agents = Set(sessions.agents.filter { !$0.isEmpty }.map(VendorMark.key))
        projects = Set(sessions.projects.filter { !$0.isEmpty })
        states = Set(sessions.states)
    }

    /// Whether a session of the execution agent `vendor` in `state` is listed, its project aside.
    func keeps(vendor: String?, state: PanelSessionState) -> Bool {
        (agents.isEmpty || vendor.map { agents.contains(VendorMark.key($0)) } == true)
            && (states.isEmpty || states.contains(state))
    }

    /// Whether a session of `project` is listed. The project is asked for only where the filter names any, since finding
    /// one reads Git's pointers on disk.
    func keeps(project: () -> SessionProject) -> Bool {
        projects.isEmpty || projects.contains(project().id)
    }
}

/// The hover panel's token chart under a layout: the period it starts from and whose tokens it draws, a layout's
/// `tokens` in effect (`PanelLayout.Tokens`). `PanelTokenFilter()` is the default view's: every model's tokens over the
/// latest 24 hours.
public struct PanelTokenFilter: Hashable, Sendable {
    public let period: PanelTokenPeriod
    /// The marks (`VendorMark.key`) of the agents whose models are charted; empty for every agent.
    let agents: Set<String>
    /// The ids of the models charted among those agents' (`AgentDescriptor.id`); empty for every model.
    let models: Set<String>

    public init(_ tokens: PanelLayout.Tokens = PanelLayout.Tokens()) {
        period = tokens.chartPeriod
        agents = Set(tokens.agents.filter { !$0.isEmpty }.map(VendorMark.key))
        models = Set(tokens.models.filter { !$0.isEmpty })
    }

    /// Whether the chart leaves out any model.
    var narrows: Bool { !agents.isEmpty || !models.isEmpty }

    /// Whether a model's tokens are charted: those of every model while no agent and no model is named; else those of
    /// a model whose vendor as the panel's blocks show it (`AgentDescriptor.displayVendor`, as a quota block's chart
    /// matches its models) is drawn with a named agent's mark, where agents are named, and that is named itself, where
    /// models are.
    func keeps(_ consumer: AgentDescriptor) -> Bool {
        (agents.isEmpty || agents.contains(VendorMark.key(consumer.displayVendor)))
            && (models.isEmpty || models.contains(consumer.id))
    }
}

/// The sessions the hover panel lists, as `ReportView.panelSessions(_:vendor:project:)` chooses them.
public struct PanelSessionRows: Sendable {
    /// The listed sessions with work in flight, those waiting for the user first, newest started first within each;
    /// the header counts them as running, whatever the order of the rows.
    public let running: [LiveSession]
    /// The rows, in the filter's order, up to the limit: under `active` those in flight, then those ended in the
    /// filter's period, newest last event first; under `date` every one by its last event, the newest first.
    public let shown: [LiveSession]
    /// How many sessions the filter lists beyond the rows, which "+N more" counts.
    public let more: Int
    /// How many sessions of the filter's period, or in flight, each state has before the layout's agents, projects and
    /// states: what they can choose from. An agent's own panel counts its agent's alone.
    let counts: [PanelSessionState: Int]
    /// Whether the layout leaves out every session of its period, or in flight, that the panel would list without its
    /// agents, projects and states; the section then says that none matches rather than that there are none.
    public let noneMatch: Bool
}

public extension ReportView {
    /// The hover panel's session rows: of the sessions with work in flight or last active in the filter's period, a day
    /// by default, without account-wide API receipts, those `filter` keeps; in the filter's order, by default first those
    /// in flight, waiting for the user ahead of running and newest started first within each, then the ended ones by
    /// their last event, the newest first, and under `date` every one by its last event; at most `filter.limit` of them,
    /// with "+N more" counting the rest of what the filter keeps. Each step is a set operation over the view's sessions,
    /// cheap on every pass.
    /// - vendor: an agent's own panel's vendor on a dock that separates its agents: only the sessions of agents drawn
    ///   with its mark are listed, and the filter applies among them.
    /// - project: the project a session belongs to, asked for only where the filter names projects; a host passes the
    ///   one it keeps for the report (`UsageStore.panelSessions(_:vendor:)`), since finding one reads Git's pointers.
    func panelSessions(_ filter: PanelSessionFilter = PanelSessionFilter(), vendor: String? = nil,
                       project: (LiveSession) -> SessionProject = SessionProject.init) -> PanelSessionRows {
        let mark = vendor.map(VendorMark.key)
        let listed = now.addingTimeInterval(-filter.period.duration)
        let own = sessions.filter { !$0.session.accountWide && (mark == nil || $0.markVendor.map(VendorMark.key) == mark) }
        let window = own.filter { $0.phase.isInFlight || $0.lastEventAt >= listed }
        var counts: [PanelSessionState: Int] = [:]
        for session in window { counts[PanelSessionState(session.phase.state), default: 0] += 1 }
        let kept = window.filter { session in
            filter.keeps(vendor: session.markVendor, state: PanelSessionState(session.phase.state))
                && filter.keeps(project: { project(session.session) })
        }
        let active = kept.filter(\.phase.isInFlight).sorted {
            let lhsWaiting = $0.phase.state == .waitingForApproval, rhsWaiting = $1.phase.state == .waitingForApproval
            if lhsWaiting != rhsWaiting { return lhsWaiting }
            return $0.session.startedAt > $1.session.startedAt
        }
        // The view orders by the last event, so ended rows follow recent work rather than when a session was created,
        // and so does every row by date.
        let summary: [Session]
        switch filter.sort {
        case .active: summary = active + kept.filter { !$0.phase.isInFlight }
        case .date: summary = kept
        }
        let shown = summary.prefix(filter.limit).map(\.session)
        return PanelSessionRows(running: active.map(\.session), shown: shown, more: summary.count - shown.count,
                                counts: counts, noneMatch: summary.isEmpty && !window.isEmpty)
    }

    /// The agents that have sessions now, by the name of their execution client, one per mark, in name order: the names a
    /// layout's `sessions.agents` can list. Account-wide API receipts are no one's session here.
    internal var panelSessionAgents: [String] {
        VendorMark.merged(sessions.filter { !$0.session.accountWide }.compactMap(\.markVendor)).sorted()
    }

    /// The agents whose models spend the tokens the chart draws now, by the vendor the panel's blocks show
    /// (`AgentDescriptor.displayVendor`), one per mark, in the report's order: the names a layout's `tokens.agents` can
    /// list.
    internal var panelTokenAgents: [String] {
        VendorMark.merged(panelTokenModels.map(\.displayVendor))
    }

    /// The models whose tokens the chart can draw now, in the report's order: those whose ids a layout's
    /// `tokens.models` can list.
    internal var panelTokenModels: [AgentDescriptor] { report?.consumers ?? [] }
}

extension ReportView.Session {
    /// The execution agent the session belongs to, whose mark its row is drawn with: Grok's clients apart, Codex's
    /// clients as Codex.
    var markVendor: String? { source.agentVendor ?? source.vendor }
}
