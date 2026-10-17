import AgentHUDSupport
import Foundation

/// A session's state as the hover panel's rows show it on the corner of its agent's mark, and as a layout chooses rows
/// by: waiting for the user, running, or ended. A session whose live status is off, or whose reading is out of date,
/// counts as ended, as its row shows it.
public enum PanelSessionState: String, Codable, CaseIterable, Sendable {
    case waiting, running, ended

    init(_ state: SessionPhase.State) {
        switch state {
        case .waitingForApproval: self = .waiting
        case .running: self = .running
        case .idle, .unverified: self = .ended
        }
    }
}

/// How far back the hover panel's token chart reaches: the latest 24 hours in quarter-hour columns (`day`), or the last
/// 7 or 30 days, rolling, in the columns `ChartData.bucketSize(spanning:)` picks for such a span, local days. Each ends
/// with the quarter hour that holds the latest reading.
public enum PanelTokenPeriod: String, Codable, CaseIterable, Sendable, Identifiable {
    case day, week, month

    public var id: Self { self }

    /// The statistics window's range of the same length.
    public var range: StatsRange {
        switch self {
        case .day: .hours24
        case .week: .days7
        case .month: .days30
        }
    }

    public var duration: TimeInterval { Double(range.hours) * 3600 }

    /// The width of one of the chart's columns over the period.
    public var bucketSize: TokenBucketSize { ChartData.bucketSize(spanning: duration) }

    /// How the chart's header and its picker name the period, the same in every language: `24h`, `7d`, `30d`.
    public var label: String {
        switch self {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        }
    }
}

/// How long after its last event an ended session is still listed in the hover panel's session rows: from an hour to the
/// seven days sessions are reported for (`SessionWindow.recency`), each named by its length, `1h` to `7d`, as the token
/// chart's picker names its periods. A session with work in flight is listed whatever the period.
public enum PanelSessionPeriod: String, Codable, CaseIterable, Sendable, Identifiable {
    case hour = "1h", hours2 = "2h", hours6 = "6h", hours12 = "12h", day = "24h", days3 = "3d", week = "7d"

    public var id: Self { self }

    public var duration: TimeInterval {
        switch self {
        case .hour: 3600
        case .hours2: 2 * 3600
        case .hours6: 6 * 3600
        case .hours12: 12 * 3600
        case .day: 24 * 3600
        case .days3: 3 * 86400
        case .week: 7 * 86400
        }
    }
}

public extension PanelLayout {
    /// Which sessions the panel's session rows list, and how many. `Sessions()` is the default view's, five rows of every
    /// agent's sessions in every state of the last day, and is not written.
    struct Sessions: Hashable, Codable, Sendable {
        /// The rows a layout can give the section.
        static let limitRange = 1...10
        /// The rows of a section a layout gives none.
        static let defaultLimit = 5

        /// How many rows the section shows at most, within `limitRange`; nil for five.
        public var limit: Int?
        /// How long after its last event an ended session is still listed; nil for a day.
        public var period: PanelSessionPeriod?
        /// The agents whose sessions are listed, by vendor, each matched by the mark it is drawn with (`VendorMark`), as
        /// an agent's own panel matches its sessions: "Codex" names the mark Codex and ChatGPT share. Empty for every
        /// agent.
        public var agents: [String]
        /// The states whose sessions are listed; empty for every state.
        public var states: [PanelSessionState]

        public init(limit: Int? = nil, period: PanelSessionPeriod? = nil, agents: [String] = [],
                    states: [PanelSessionState] = []) {
            self.limit = limit
            self.period = period
            self.agents = agents
            self.states = states
        }

        /// The rows in effect: the layout's limit, else five.
        var rowLimit: Int { limit.flatMap { Self.limitRange.contains($0) ? $0 : nil } ?? Self.defaultLimit }

        /// The period in effect: the layout's, else a day.
        var listedPeriod: PanelSessionPeriod { period ?? .day }

        /// Whether the section lists what the default view lists.
        var isDefault: Bool { normalized() == Sessions() }

        /// The section written one way: no limit at five or outside `limitRange`; no period for a day; each mark once, by
        /// the first name given for it, in name order, since a filter has no order, and no empty name; and each state once
        /// in default order, none where all three are listed, which keeps every state as none does.
        func normalized() -> Sessions {
            let states = PanelSessionState.allCases.filter(states.contains)
            return Sessions(limit: rowLimit == Self.defaultLimit ? nil : rowLimit,
                            period: listedPeriod == .day ? nil : listedPeriod,
                            agents: VendorMark.merged(agents.filter { !$0.isEmpty }).sorted(),
                            states: states.count == PanelSessionState.allCases.count ? [] : states)
        }

        private enum CodingKeys: String, CodingKey { case limit, period, agents, states }

        /// Nil when the value is not an object. A limit that is no whole number from 1 to 10 is not given, and neither is a
        /// period this build does not know; a state it does not know is left out, and a name that is not a string too.
        init?(json: JSONValue) {
            guard let fields = json.objectValue else { return nil }
            self.init(limit: fields["limit"]?.countValue.flatMap { Self.limitRange.contains($0) ? $0 : nil },
                      period: fields["period"]?.stringValue.flatMap(PanelSessionPeriod.init(rawValue:)),
                      agents: PanelLayout.strings(fields["agents"]),
                      states: PanelLayout.strings(fields["states"]).compactMap(PanelSessionState.init(rawValue:)))
        }

        public init(from decoder: Decoder) throws {
            guard let sessions = Sessions(json: try decoder.singleValueContainer().decode(JSONValue.self)) else {
                throw DecodingError.typeMismatch(Sessions.self, DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "The sessions of a panel layout are a JSON object."))
            }
            self = sessions
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if rowLimit != Self.defaultLimit { try c.encode(rowLimit, forKey: .limit) }
            if listedPeriod != .day { try c.encode(listedPeriod, forKey: .period) }
            if !agents.isEmpty { try c.encode(agents, forKey: .agents) }
            if !states.isEmpty { try c.encode(states, forKey: .states) }
        }
    }

    /// How the panel's token chart is drawn: over which period, and whose tokens. `Tokens()` is the default view's, every
    /// model's tokens over the latest 24 hours, and is not written.
    struct Tokens: Hashable, Codable, Sendable {
        /// The period the chart starts from each time the panel opens; nil for `day`.
        public var period: PanelTokenPeriod?
        /// The agents whose models' tokens are charted, by vendor, the key `get_hud` gives a quota block, each matched by
        /// the mark it is drawn with. Empty for every agent.
        public var agents: [String]
        /// The models whose tokens are charted, by the id `get_hud` gives each among the chart's models
        /// (`AgentDescriptor.id`), among those of `agents` where it names any. Empty for every model.
        public var models: [String]

        public init(period: PanelTokenPeriod? = nil, agents: [String] = [], models: [String] = []) {
            self.period = period
            self.agents = agents
            self.models = models
        }

        /// The period in effect: the layout's, else `day`.
        var chartPeriod: PanelTokenPeriod { period ?? .day }

        /// Whether the chart is drawn as the default view draws it.
        var isDefault: Bool { normalized() == Tokens() }

        /// The chart written one way: no period for `day`, each mark once, by the first name given for it, in name order,
        /// and each model once, in id order, since a filter has no order, and no empty name or id.
        func normalized() -> Tokens {
            Tokens(period: chartPeriod == .day ? nil : chartPeriod, agents: VendorMark.merged(agents.filter { !$0.isEmpty }).sorted(),
                   models: models.filter { !$0.isEmpty }.withoutRepeats.sorted())
        }

        private enum CodingKeys: String, CodingKey { case period, agents, models }

        /// Nil when the value is not an object. A period this build does not know is not given, and a name or an id that
        /// is not a string is left out.
        init?(json: JSONValue) {
            guard let fields = json.objectValue else { return nil }
            self.init(period: fields["period"]?.stringValue.flatMap(PanelTokenPeriod.init(rawValue:)),
                      agents: PanelLayout.strings(fields["agents"]), models: PanelLayout.strings(fields["models"]))
        }

        public init(from decoder: Decoder) throws {
            guard let tokens = Tokens(json: try decoder.singleValueContainer().decode(JSONValue.self)) else {
                throw DecodingError.typeMismatch(Tokens.self, DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "The tokens of a panel layout are a JSON object."))
            }
            self = tokens
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if chartPeriod != .day { try c.encode(chartPeriod, forKey: .period) }
            if !agents.isEmpty { try c.encode(agents, forKey: .agents) }
            if !models.isEmpty { try c.encode(models, forKey: .models) }
        }
    }
}

extension PanelLayout {
    /// What is wrong with a layout's sessions and tokens, as `misreadings(of:)` tells it: not an object, a limit that is
    /// no whole number from 1 to 10, a state or period this build does not know, a name or a model's id that is not a
    /// string or is empty, a property they do not have.
    static func misreadings(ofSessions sessions: JSONValue, tokens: JSONValue) -> [String] {
        var found: [String] = []
        if sessions != .null {
            if let fields = sessions.objectValue {
                for property in fields.keys.sorted() {
                    let value = fields[property] ?? .null
                    switch property {
                    case "limit":
                        if value != .null, value.countValue.map({ Sessions.limitRange.contains($0) }) != true {
                            found.append("sessions.limit is a whole number from \(Sessions.limitRange.lowerBound) to "
                                         + "\(Sessions.limitRange.upperBound).")
                        }
                    case "period":
                        found += misnamed(value, at: "sessions.period", among: PanelSessionPeriod.allCases.map(\.rawValue))
                    case "agents":
                        found += agentNames(value, at: "sessions.agents", from: "get_hud's sessions.offeredAgents")
                    case "states":
                        found += names(value, at: "sessions.states", among: PanelSessionState.allCases.map(\.rawValue))
                    default:
                        found.append("sessions has no property \"\(property)\"; sessions take limit, period, agents and states.")
                    }
                }
            } else {
                found.append("sessions is an object.")
            }
        }
        if tokens != .null {
            if let fields = tokens.objectValue {
                for property in fields.keys.sorted() {
                    let value = fields[property] ?? .null
                    switch property {
                    case "period":
                        found += misnamed(value, at: "tokens.period", among: PanelTokenPeriod.allCases.map(\.rawValue))
                    case "agents":
                        found += agentNames(value, at: "tokens.agents", from: "get_hud's tokens.offeredAgents")
                    case "models":
                        found += names(value, at: "tokens.models", among: nil)
                        for (index, item) in (value.arrayValue ?? []).enumerated() where item.stringValue?.isEmpty == true {
                            found.append("tokens.models[\(index)] is a model's id from get_hud's tokens.offeredModels.")
                        }
                    default:
                        found.append("tokens has no property \"\(property)\"; tokens take period, agents and models.")
                    }
                }
            } else {
                found.append("tokens is an object.")
            }
        }
        return found
    }

    /// What is wrong with a list of agents' names: what `names(_:at:among:)` finds, and an empty name.
    private static func agentNames(_ value: JSONValue, at path: String, from source: String) -> [String] {
        var found = names(value, at: path, among: nil)
        for (index, item) in (value.arrayValue ?? []).enumerated() where item.stringValue?.isEmpty == true {
            found.append("\(path)[\(index)] is an agent's name from \(source).")
        }
        return found
    }

    /// Every agent of `sessions.agents` that no session has now, and of `tokens.agents` that no model spending tokens
    /// has now, by position, each matched by mark: `sessionAgents` and `tokenAgents` are the agents that have them
    /// (`ReportView.panelSessionAgents`, `ReportView.panelTokenAgents`). Then every model of `tokens.models` that is
    /// none of `tokenModels`, the models the chart can draw now (`ReportView.panelTokenModels`), and every one whose
    /// agent `tokens.agents` leaves out, which the chart would not draw. An agent or a model one of the `held` layouts
    /// already lists there is no issue: a layout keeps it for when its sessions or tokens return, so a proposal built on
    /// a layout that was read may carry it.
    func filterIssues(sessionAgents: [String], tokenAgents: [String], tokenModels: [AgentDescriptor] = [],
                      holding held: [PanelLayout] = []) -> [PanelLayoutIssue] {
        func issues(_ listed: [String], at path: String, against present: [String], kept: [String],
                    missing: (String) -> String, offered: String) -> [PanelLayoutIssue] {
            let marks = Set(present.map(VendorMark.key)), keptMarks = Set(kept.map(VendorMark.key))
            return listed.enumerated().compactMap { index, agent in
                let mark = VendorMark.key(agent)
                guard !agent.isEmpty, !marks.contains(mark), !keptMarks.contains(mark) else { return nil }
                return PanelLayoutIssue(path: "\(path)[\(index)]", message: "\(missing(agent)) \(offered)")
            }
        }
        let sessionsOffered = sessionAgents.isEmpty ? "No agent has a session now."
            : "Agents with sessions now: \(Self.quoted(sessionAgents))."
        let tokensOffered = tokenAgents.isEmpty ? "The chart has no agent's tokens now."
            : "Agents in the chart now: \(Self.quoted(tokenAgents))."
        return issues(sessions.agents, at: "sessions.agents", against: sessionAgents, kept: held.flatMap(\.sessions.agents),
                      missing: { "\"\($0)\" has no session now." }, offered: sessionsOffered)
            + issues(tokens.agents, at: "tokens.agents", against: tokenAgents, kept: held.flatMap(\.tokens.agents),
                     missing: { "\"\($0)\" has no model in the token chart now." }, offered: tokensOffered)
            + modelIssues(among: tokenModels, holding: held)
    }

    /// Every model of `tokens.models` the chart cannot draw as asked: one that is none of `offered` and that no `held`
    /// layout lists, and one of an agent `tokens.agents` leaves out, matched by mark as the chart matches its models.
    private func modelIssues(among offered: [AgentDescriptor], holding held: [PanelLayout]) -> [PanelLayoutIssue] {
        let kept = Set(held.flatMap(\.tokens.models)), agents = Set(tokens.agents.filter { !$0.isEmpty }.map(VendorMark.key))
        let ids = offered.map(\.id).withoutRepeats
        let inChart = ids.isEmpty ? "The chart has no model's tokens now." : "Models in the chart now: \(Self.quoted(ids))."
        return tokens.models.enumerated().compactMap { index, id in
            let path = "tokens.models[\(index)]"
            guard !id.isEmpty else { return nil }
            guard let model = offered.first(where: { $0.id == id }) else {
                if kept.contains(id) { return nil }
                return PanelLayoutIssue(path: path, message: "\"\(id)\" is no model in the token chart now. \(inChart)")
            }
            let vendor = model.displayVendor
            guard !agents.isEmpty, !agents.contains(VendorMark.key(vendor)) else { return nil }
            return PanelLayoutIssue(path: path, message: "\"\(id)\" is \(vendor)'s, and tokens.agents leaves \(vendor) out, so "
                                    + "the chart would not draw it. Name \"\(vendor)\" in tokens.agents too, or name no agent.")
        }
    }
}
