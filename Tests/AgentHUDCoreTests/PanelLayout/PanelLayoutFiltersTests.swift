import AgentHUDSupport
import XCTest
@testable import AgentHUDCore

/// A layout's sessions and tokens, their period and their models among them: their JSON, what reading them forgives, when
/// two are the same, what an agent is told it cannot list, and the plan they resolve to.
final class PanelLayoutFiltersTests: XCTestCase {
    private func decode(_ json: String) throws -> PanelLayout {
        try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
    }

    private func encode(_ layout: PanelLayout) throws -> String {
        String(decoding: try RecordCoding.encoder().encode(layout), as: UTF8.self)
    }

    // MARK: Coding

    func testTheDocumentedShapeReadsAndWritesBack() throws {
        let json = #"{"sessions":{"agents":["Codex"],"limit":3,"states":["waiting","running"]},"tokens":{"agents":["Claude"],"period":"week"}}"#
        let layout = PanelLayout(sessions: PanelLayout.Sessions(limit: 3, agents: ["Codex"], states: [.waiting, .running]),
                                 tokens: PanelLayout.Tokens(period: .week, agents: ["Claude"]))
        XCTAssertEqual(try decode(json), layout)
        XCTAssertEqual(try encode(layout), json, "keys are sorted and nothing unset is written")
        XCTAssertEqual(try encode(try decode(json)), json)
    }

    func testTheDefaultsAreNotWritten() throws {
        XCTAssertEqual(try encode(PanelLayout(sessions: PanelLayout.Sessions(limit: 5), tokens: PanelLayout.Tokens(period: .day))), "{}")
        XCTAssertEqual(try encode(PanelLayout(sessions: PanelLayout.Sessions(states: PanelSessionState.allCases))), "{}",
                       "every state is what no state means")
        XCTAssertTrue(PanelLayout(sessions: PanelLayout.Sessions(limit: 5, states: PanelSessionState.allCases)).isDefault)
        XCTAssertEqual(try encode(PanelLayout(sessions: PanelLayout.Sessions(limit: 10))), #"{"sessions":{"limit":10}}"#)
        XCTAssertEqual(try encode(PanelLayout(tokens: PanelLayout.Tokens(period: .month))), #"{"tokens":{"period":"month"}}"#)
        XCTAssertEqual(try decode("{}").sessions.rowLimit, 5)
        XCTAssertEqual(try decode("{}").tokens.chartPeriod, .day)
    }

    /// A stored layout from a newer build still loads: what this build cannot read in them counts as not given.
    func testStoredSessionsAndTokensAreReadForgivingly() throws {
        let layout = try decode("""
            {"sessions": {"limit": 11, "agents": ["Claude", 4], "states": ["idle", "ended"], "project": "x"},
             "tokens": {"period": "year", "agents": "Codex"}}
            """)
        XCTAssertEqual(layout.sessions, PanelLayout.Sessions(agents: ["Claude"], states: [.ended]))
        XCTAssertEqual(layout.tokens, PanelLayout.Tokens())
        for limit in ["0", "2.5", "\"3\"", "-1", "true"] {
            XCTAssertNil(try decode(#"{"sessions": {"limit": \#(limit)}}"#).sessions.limit, limit)
        }
        XCTAssertEqual(try decode(#"{"sessions": {"limit": 7.0}}"#).sessions.limit, 7)
        XCTAssertEqual(try decode(#"{"sessions": [1], "tokens": "week"}"#), PanelLayout(), "neither is an object")
    }

    func testTheSameFilterIsTheSameLayout() {
        let spelled = PanelLayout(sessions: PanelLayout.Sessions(limit: 5, agents: ["DeepSeek", "Codex", "ChatGPT", ""],
                                                                 states: [.ended, .waiting, .ended]),
                                  tokens: PanelLayout.Tokens(period: .day, agents: ["Codex", "Claude", "ChatGPT"]))
        let plain = PanelLayout(sessions: PanelLayout.Sessions(agents: ["Codex", "DeepSeek"], states: [.waiting, .ended]),
                                tokens: PanelLayout.Tokens(agents: ["Claude", "Codex"]))
        XCTAssertEqual(spelled.normalized(), plain.normalized(),
                       "a filter has no order, and Codex and ChatGPT are one mark, named as first given")
        XCTAssertEqual(spelled.normalized().sessions, PanelLayout.Sessions(agents: ["Codex", "DeepSeek"], states: [.waiting, .ended]))
        XCTAssertEqual(PanelLayout(sessions: PanelLayout.Sessions(limit: 0)).normalized(), PanelLayout())
    }

    // MARK: What an agent is told

    func testAnAgentWithNoSessionsOrTokensNowIsAnIssueUnlessTheLayoutHoldsIt() {
        let layout = PanelLayout(sessions: PanelLayout.Sessions(agents: ["ChatGPT", "Grok", ""]),
                                 tokens: PanelLayout.Tokens(agents: ["Claude", "Gemini"]))
        let issues = layout.filterIssues(sessionAgents: ["Claude", "Codex"], tokenAgents: ["Claude", "Codex"])
        XCTAssertEqual(issues.map(\.path), ["sessions.agents[1]", "tokens.agents[1]"], "ChatGPT is Codex's mark")
        XCTAssertEqual(issues.first?.message, "\"Grok\" has no session now. Agents with sessions now: \"Claude\", \"Codex\".")
        XCTAssertEqual(issues.last?.message,
                       "\"Gemini\" has no model in the token chart now. Agents in the chart now: \"Claude\", \"Codex\".")
        XCTAssertEqual(layout.filterIssues(sessionAgents: [], tokenAgents: []).map(\.message).last,
                       "\"Gemini\" has no model in the token chart now. The chart has no agent's tokens now.")

        let held = PanelLayout(sessions: PanelLayout.Sessions(agents: ["Grok CLI"]), tokens: PanelLayout.Tokens(agents: ["Gemini"]))
        XCTAssertTrue(layout.filterIssues(sessionAgents: ["Claude", "Codex"], tokenAgents: ["Claude"], holding: [held]).isEmpty,
                      "what a layout holds for an agent that is away may come back, matched by mark")
    }

    // MARK: The plan

    func testThePlanResolvesTheFiltersAndTheDefaultViewNarrowsNothing() {
        let plain = PanelLayoutPlan(layout: PanelLayout(), blocks: [])
        XCTAssertEqual(plain.sessions.limit, 5)
        XCTAssertEqual(plain.tokens.period, .day)
        XCTAssertFalse(plain.tokens.narrows)
        XCTAssertTrue(plain.sessions.keeps(vendor: nil, state: .ended))

        let plan = PanelLayoutPlan(layout: PanelLayout(
            sessions: PanelLayout.Sessions(limit: 8, agents: ["ChatGPT", "Grok CLI"], states: [.running]),
            tokens: PanelLayout.Tokens(period: .month, agents: ["Codex"])), blocks: [])
        XCTAssertEqual(plan.sessions.limit, 8)
        XCTAssertTrue(plan.sessions.keeps(vendor: "Codex", state: .running), "matched by mark")
        XCTAssertTrue(plan.sessions.keeps(vendor: "Grok CLI", state: .running))
        XCTAssertFalse(plan.sessions.keeps(vendor: "Grok Bot", state: .running), "Grok's clients are apart")
        XCTAssertFalse(plan.sessions.keeps(vendor: "Codex", state: .waiting))
        XCTAssertFalse(plan.sessions.keeps(vendor: nil, state: .running), "a session of no agent is no listed agent's")
        XCTAssertEqual(plan.tokens.period, .month)
        let codex = AgentDescriptor(id: "codex-model:gpt", vendor: "Codex", model: "GPT", source: "", enabled: true)
        let claude = AgentDescriptor(id: "claude-model:opus", vendor: "Claude", model: "Opus", source: "", enabled: true)
        XCTAssertTrue(plan.tokens.keeps(codex))
        XCTAssertFalse(plan.tokens.keeps(claude))
        XCTAssertEqual(PanelSessionFilter(PanelLayout.Sessions(states: PanelSessionState.allCases)).states.count, 3)
    }

    // MARK: The sessions' period and the chart's models

    func testThePeriodAndTheModelsReadAndWriteBack() throws {
        let json = #"{"sessions":{"period":"7d"},"tokens":{"models":["claude-model:claude-opus-5-5","codex-model:gpt-6.1-sol"]}}"#
        let layout = PanelLayout(sessions: PanelLayout.Sessions(period: .week),
                                 tokens: PanelLayout.Tokens(models: ["claude-model:claude-opus-5-5", "codex-model:gpt-6.1-sol"]))
        XCTAssertEqual(try decode(json), layout)
        XCTAssertEqual(try encode(layout), json)
        XCTAssertEqual(try encode(PanelLayout(sessions: PanelLayout.Sessions(period: .day))), "{}", "a day is the default view's")
        XCTAssertEqual(try decode("{}").sessions.listedPeriod, .day)
        XCTAssertEqual(try decode(#"{"sessions": {"period": "1h"}}"#).sessions.period, .hour)

        // A stored layout from a newer build still loads.
        let stored = try decode(#"{"sessions": {"period": "30d"}, "tokens": {"models": ["claude-model:a", 4, null]}}"#)
        XCTAssertNil(stored.sessions.period, "a period this build does not know is not given")
        XCTAssertEqual(stored.tokens.models, ["claude-model:a"], "an id that is not a string is left out")
        XCTAssertTrue(try decode(#"{"tokens": {"models": "claude-model:a"}}"#).isDefault)
    }

    func testTheSameModelsAreTheSameLayout() {
        let spelled = PanelLayout(tokens: PanelLayout.Tokens(models: ["codex-model:b", "claude-model:a", "codex-model:b", ""]))
        XCTAssertEqual(spelled.normalized().tokens.models, ["claude-model:a", "codex-model:b"], "a filter has no order")
        XCTAssertEqual(PanelLayout(tokens: PanelLayout.Tokens(models: [""])).normalized(), PanelLayout())
        XCTAssertEqual(PanelLayout(sessions: PanelLayout.Sessions(period: .day)).normalized(), PanelLayout())
    }

    func testTheSessionPeriodsReachAsFarBackAsSessionsAreReported() {
        XCTAssertEqual(PanelSessionPeriod.allCases.map(\.rawValue), ["1h", "2h", "6h", "12h", "24h", "3d", "7d"])
        XCTAssertEqual(PanelSessionPeriod.allCases.map(\.duration), [1, 2, 6, 12, 24, 72, 168].map { Double($0) * 3600 })
        XCTAssertEqual(PanelSessionPeriod.week.duration, SessionWindow.recency, "no older session is reported")
        XCTAssertEqual(PanelSessionPeriod.day.duration, PanelTokenPeriod.day.duration)
    }

    /// A model the chart has no tokens of now is an issue, unless a layout holds it, and so is one of an agent the
    /// layout's agents leave out, which the chart would not draw.
    func testAModelTheChartCannotDrawIsAnIssueUnlessTheLayoutHoldsIt() {
        let opus = AgentDescriptor(id: "claude-model:opus", vendor: "Claude", model: "Opus", source: "", enabled: true)
        let gpt = AgentDescriptor(id: "codex-model:gpt", vendor: "Codex", model: "GPT", source: "", enabled: true)
        let layout = PanelLayout(tokens: PanelLayout.Tokens(agents: ["Claude"],
                                                            models: ["claude-model:opus", "codex-model:gpt", "gemini-model:pro", ""]))
        let issues = layout.filterIssues(sessionAgents: [], tokenAgents: ["Claude", "Codex"], tokenModels: [opus, gpt])
        XCTAssertEqual(issues.map(\.path), ["tokens.models[1]", "tokens.models[2]"])
        XCTAssertEqual(issues.first?.message, "\"codex-model:gpt\" is Codex's, and tokens.agents leaves Codex out, so the chart "
                       + "would not draw it. Name \"Codex\" in tokens.agents too, or name no agent.")
        XCTAssertEqual(issues.last?.message, "\"gemini-model:pro\" is no model in the token chart now. Models in the chart now: "
                       + "\"claude-model:opus\", \"codex-model:gpt\".")
        XCTAssertEqual(PanelLayout(tokens: PanelLayout.Tokens(models: ["x"])).filterIssues(sessionAgents: [], tokenAgents: [])
            .map(\.message), ["\"x\" is no model in the token chart now. The chart has no model's tokens now."])
        XCTAssertTrue(PanelLayout(tokens: PanelLayout.Tokens(agents: ["ChatGPT"], models: ["codex-model:gpt"]))
            .filterIssues(sessionAgents: [], tokenAgents: ["Codex"], tokenModels: [opus, gpt]).isEmpty, "matched by mark")

        let held = PanelLayout(tokens: PanelLayout.Tokens(models: ["gemini-model:pro"]))
        XCTAssertEqual(layout.filterIssues(sessionAgents: [], tokenAgents: ["Claude", "Codex"], tokenModels: [opus, gpt], holding: [held])
            .map(\.path), ["tokens.models[1]"], "a model a layout holds may come back while it spends no tokens")
    }

    func testThePlanResolvesThePeriodAndTheModels() {
        let opus = AgentDescriptor(id: "claude-model:opus", vendor: "Claude", model: "Opus", source: "", enabled: true)
        let sonnet = AgentDescriptor(id: "claude-model:sonnet", vendor: "Claude", model: "Sonnet", source: "", enabled: true)
        let gpt = AgentDescriptor(id: "codex-model:gpt", vendor: "Codex", model: "GPT", source: "", enabled: true)
        XCTAssertEqual(PanelLayoutPlan(layout: PanelLayout(), blocks: []).sessions.period, .day)
        let plan = PanelLayoutPlan(layout: PanelLayout(sessions: PanelLayout.Sessions(period: .hours6),
                                                       tokens: PanelLayout.Tokens(models: ["claude-model:opus"])), blocks: [])
        XCTAssertEqual(plan.sessions.period, .hours6)
        XCTAssertTrue(plan.tokens.narrows)
        XCTAssertTrue(plan.tokens.keeps(opus))
        XCTAssertFalse(plan.tokens.keeps(sonnet))
        let both = PanelTokenFilter(PanelLayout.Tokens(agents: ["Codex"], models: ["claude-model:opus", "codex-model:gpt"]))
        XCTAssertFalse(both.keeps(opus), "the agents and the models both apply")
        XCTAssertTrue(both.keeps(gpt))
        XCTAssertNotEqual(PanelTokenFilter(PanelLayout.Tokens(models: ["claude-model:opus"])), PanelTokenFilter(),
                          "another chart, whose picker starts again from the layout's period")
    }

    func testThePeriodsAreTheStatisticsRangesInTheirOwnColumns() {
        XCTAssertEqual(PanelTokenPeriod.allCases.map(\.label), ["24h", "7d", "30d"])
        XCTAssertEqual(PanelTokenPeriod.allCases.map(\.duration), [86400, 7 * 86400, 30 * 86400] as [TimeInterval])
        XCTAssertEqual(PanelTokenPeriod.allCases.map(\.bucketSize), [.minutes15, .day1, .day1])
        XCTAssertEqual(PanelTokenPeriod.allCases.map(\.range), [.hours24, .days7, .days30])
    }
}
