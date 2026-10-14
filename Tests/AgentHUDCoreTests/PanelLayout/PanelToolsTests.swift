import AgentHUDSupport
import Foundation
import XCTest
@testable import AgentHUDCore

/// What the MCP tools do in the application, over the sample's panel: Claude and Codex quota blocks and DeepSeek's
/// balance.
@MainActor
final class PanelToolsTests: XCTestCase {
    private var suite = ""
    private var settings: SettingsStore!
    private var store: UsageStore!
    private var tools: PanelTools!
    private var changes = 0

    override func setUp() async throws {
        L10n.setLanguage(.en)
        suite = "app.agenthud.tests.panel-tools.\(UUID().uuidString)"
        settings = SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), defaultAgents: DemoData.agents)
        store = UsageStore(provider: DemoUsageProvider(), settings: settings, clock: { DemoClock.now })
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: 48, now: DemoClock.now, stage: nil))
        tools = PanelTools(store: store)
        changes = 0
        settings.onChange = { [weak self] _ in self?.changes += 1 }
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        L10n.setLanguage(.system)
    }

    private var layout: PanelLayoutStore { settings.panelLayout }

    private func result(_ tool: String, _ arguments: [String: JSONValue] = [:], line: UInt = #line) throws -> [String: JSONValue] {
        guard case .result(let result) = tools.answer(MCPToolRequest(tool: tool, arguments: arguments)) else {
            XCTFail("\(tool) was refused", line: line)
            throw CancellationError()
        }
        return result
    }

    private func refusal(_ arguments: [String: JSONValue], line: UInt = #line) throws -> String {
        let before = (layout.revision, layout.draft)
        guard case .failure(let sentence) = tools.answer(MCPToolRequest(tool: MCPTools.setPanelLayout, arguments: arguments)) else {
            XCTFail("the proposal was taken", line: line)
            throw CancellationError()
        }
        XCTAssertEqual(layout.revision, before.0, "a refused proposal changes nothing", line: line)
        XCTAssertEqual(layout.draft, before.1, line: line)
        XCTAssertTrue(sentence.hasPrefix("Nothing was changed. "), sentence, line: line)
        return sentence
    }

    private func blocks(_ panel: [String: JSONValue]) -> [[String: JSONValue]] {
        (panel["blocks"]?.arrayValue ?? []).compactMap(\.objectValue)
    }

    private func block(_ key: String, in panel: [String: JSONValue]) throws -> [String: JSONValue] {
        try XCTUnwrap(blocks(panel).first { $0["key"] == .string(key) })
    }

    // MARK: Reading

    func testThePanelIsReadWithItsBlocksRowsAndWhatEachAccepts() throws {
        let panel = try result(MCPTools.getPanel)
        XCTAssertEqual(panel["revision"], .integer(0))
        XCTAssertEqual(panel["unsaved"], .bool(false))
        XCTAssertEqual(panel["hasPrevious"], .bool(false))
        XCTAssertEqual(panel["layout"], .object([:]))
        XCTAssertNil(panel["note"])
        XCTAssertEqual(blocks(panel).map { $0["key"] }, [.string("Claude"), .string("Codex"), .string("api:DeepSeek")])
        XCTAssertEqual(panel["sections"]?.arrayValue?.compactMap { $0.objectValue?["key"]?.stringValue }, ["blocks", "tokens", "sessions"])

        let claude = try block("Claude", in: panel)
        XCTAssertEqual(claude["kind"], .string("quota"))
        XCTAssertEqual(claude["shown"], .bool(true))
        XCTAssertEqual(claude["widget"], .string("bar"))
        XCTAssertEqual(claude["measure"], .string("quota"))
        XCTAssertEqual(claude["widgets"], .array(["bar", "ring", "number", "chart"].map(JSONValue.string)))
        XCTAssertEqual(claude["measures"], .array(["quota", "burn", "tokens", "cost"].map(JSONValue.string)))
        let rows = (claude["rows"]?.arrayValue ?? []).compactMap(\.objectValue)
        XCTAssertEqual(rows.map { $0["key"] }, [.string("claude-session"), .string("claude-weekly"), .string("claude-weekly-fable")])
        let session = try XCTUnwrap(rows.first)
        XCTAssertEqual(session["usedPercent"], .number(12))
        XCTAssertEqual(session["level"], .string("ok"))
        XCTAssertEqual(session["state"], .string("normal"))
        XCTAssertEqual(session["shown"], .bool(true))
        XCTAssertNotNil(session["resetsAt"]?.stringValue.flatMap { try? Date($0, strategy: .iso8601) })

        let deepseek = try block("api:DeepSeek", in: panel)
        XCTAssertEqual(deepseek["kind"], .string("billing"))
        XCTAssertEqual(deepseek["widgets"], .array([.string("number")]))
        let balance = try XCTUnwrap(deepseek["balances"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(balance["currency"], .string("CNY"))
        XCTAssertEqual(balance["amount"], .string("8.85"))
        XCTAssertEqual(balance["level"], .string("warning"))
    }

    /// An agent's model is another vendor's service: it is told numbers and window names, never whose account it is.
    func testWhatIsReadNamesNoAccount() throws {
        let text = String(decoding: try RecordCoding.encoder().encode(JSONValue.object(try result(MCPTools.getPanel))), as: UTF8.self)
        let labels = (store.report?.accounts ?? [:]).values.flatMap { $0 }.flatMap { [$0.displayName, $0.account.id] }
        XCTAssertFalse(labels.isEmpty)
        for label in labels { XCTAssertFalse(text.contains(label), label) }
        XCTAssertFalse(text.contains("@"))
    }

    func testASectionSwitchedOffInSettingsIsToldAsSuch() throws {
        settings.update { $0.showIslandTokens = false }
        let sections = (try result(MCPTools.getPanel)["sections"]?.arrayValue ?? []).compactMap(\.objectValue)
        let tokens = try XCTUnwrap(sections.first { $0["key"] == .string("tokens") })
        XCTAssertEqual(tokens["shown"], .bool(true), "the layout does not hide it")
        XCTAssertEqual(tokens["onInSettings"], .bool(false))
    }

    // MARK: Proposing

    func testAProposalIsADraftThatNothingSavesAndNothingElseHears() throws {
        let agents = settings.agents
        changes = 0
        let panel = try result(MCPTools.setPanelLayout, [
            "blocks": .object(["Claude": .object(["widget": .string("ring"), "measure": .string("burn"),
                                                  "hiddenRows": .array([.string("claude-weekly-fable")])]),
                               "api:DeepSeek": .object(["hidden": .bool(true)])]),
            "order": .array([.string("Codex")]), "hiddenSections": .array([.string("tokens")]),
        ])
        XCTAssertTrue(layout.hasDraft)
        XCTAssertTrue(layout.current.isDefault, "only a person's Save keeps it")
        XCTAssertNil(UserDefaults(suiteName: suite)?.data(forKey: SettingsStore.Keys.panelLayout))
        XCTAssertEqual(settings.agents, agents)
        XCTAssertEqual(changes, 0, "a proposal wakes no collection")

        XCTAssertEqual(panel["unsaved"], .bool(true))
        XCTAssertEqual(panel["revision"], .integer(1))
        XCTAssertTrue(panel["note"]?.stringValue?.contains("unsaved draft") == true)
        XCTAssertEqual(blocks(panel).map { $0["key"] }, [.string("Codex"), .string("Claude"), .string("api:DeepSeek")],
                       "shown blocks in the layout's order, then the hidden ones")
        let claude = try block("Claude", in: panel)
        XCTAssertEqual(claude["widget"], .string("ring"))
        XCTAssertEqual(claude["measure"], .string("burn"))
        let fable = try XCTUnwrap(claude["rows"]?.arrayValue?.compactMap(\.objectValue).first { $0["key"] == .string("claude-weekly-fable") })
        XCTAssertEqual(fable["shown"], .bool(false))
        XCTAssertEqual(try block("api:DeepSeek", in: panel)["shown"], .bool(false))
        let tokens = try XCTUnwrap(panel["sections"]?.arrayValue?.compactMap(\.objectValue).first { $0["key"] == .string("tokens") })
        XCTAssertEqual(tokens["shown"], .bool(false))
    }

    func testProposingTheSavedLayoutLeavesNoDraft() throws {
        let panel = try result(MCPTools.setPanelLayout, ["sections": .array(["blocks", "tokens", "sessions"].map(JSONValue.string))])
        XCTAssertFalse(layout.hasDraft)
        XCTAssertEqual(panel["unsaved"], .bool(false))
        XCTAssertTrue(panel["note"]?.stringValue?.contains("already saved") == true)
    }

    func testTheBuiltInAndThePreviousLayoutCanBeProposed() throws {
        XCTAssertTrue(try refusal(["from": .string("previous")]).contains("no previous saved layout"))
        layout.propose(PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)]))
        layout.save()
        XCTAssertEqual(try result(MCPTools.setPanelLayout, ["from": .string("default")])["unsaved"], .bool(true))
        XCTAssertEqual(layout.draft, PanelLayout())
        layout.save()
        XCTAssertEqual(try result(MCPTools.setPanelLayout, ["from": .string("previous")])["unsaved"], .bool(true))
        XCTAssertEqual(layout.draft, PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)]))
        XCTAssertTrue(try refusal(["from": .string("last")]).contains("\"default\" or \"previous\""))
        XCTAssertTrue(try refusal(["from": .string("default"), "order": .array([])]).contains("either from or a layout"))
    }

    func testARevisionThatIsNoLongerCurrentIsRefused() throws {
        _ = try result(MCPTools.setPanelLayout, ["order": .array([.string("Codex")]), "revision": .integer(0)])
        XCTAssertEqual(layout.revision, 1)
        XCTAssertTrue(try refusal(["order": .array([.string("Claude")]), "revision": .integer(0)]).contains("revision is now 1"))
        XCTAssertTrue(try refusal(["revision": .string("1")]).contains("whole number"))
        _ = try result(MCPTools.setPanelLayout, ["order": .array([.string("Claude")]), "revision": .integer(1)])
    }

    /// What stored layouts forgive, an agent is told: a forgiven name would be a change that silently did not happen.
    func testAProposalThePanelCannotDoAsAskedIsRefusedWholeWithEveryReason() throws {
        let unknown = try refusal(["block": .object([:])])
        XCTAssertTrue(unknown.contains("Unknown: \"block\""), unknown)
        let names = try refusal(["blocks": .object(["Claude": .object(["widget": .string("gauge"), "measure": .string("speed"),
                                                                     "hide": .bool(true), "hidden": .string("yes")])]),
                                 "sections": .array([.string("weather")]), "order": .string("Codex")])
        for part in ["blocks.Claude.widget is one of \"bar\", \"ring\", \"number\", \"chart\"",
                     "blocks.Claude.measure is one of \"quota\", \"burn\", \"tokens\", \"cost\"",
                     "blocks.Claude has no property \"hide\"", "blocks.Claude.hidden is true or false",
                     "sections[0]: \"weather\" is not one of", "order is a list"] {
            XCTAssertTrue(names.contains(part), "\(part) — \(names)")
        }
        let rules = try refusal(["blocks": .object(["api:DeepSeek": .object(["widget": .string("ring")]),
                                                    "Zed": .object(["hidden": .bool(true)]),
                                                    "Codex": .object(["hiddenRows": .array([.string("nope")])])])])
        for part in ["blocks.api:DeepSeek.widget:", "has no ceiling", "blocks.Zed: No block has the key \"Zed\"",
                     "blocks.Codex.hiddenRows[0]:"] {
            XCTAssertTrue(rules.contains(part), "\(part) — \(rules)")
        }
    }

    func testDiscardingDropsTheDraftAndAnUnknownToolIsRefused() throws {
        layout.propose(PanelLayout(order: ["Codex"]))
        let panel = try result(MCPTools.discardPanelDraft)
        XCTAssertFalse(layout.hasDraft)
        XCTAssertEqual(panel["unsaved"], .bool(false))
        XCTAssertNotNil(panel["note"])
        XCTAssertEqual(tools.answer(MCPToolRequest(tool: "save_panel_layout")), .failure("Agent HUD has no tool named \"save_panel_layout\"."))
    }

    // MARK: Through the channel

    /// A line a client writes to the `--mcp` process reaches the tools in the application over the socket, and the
    /// draft is there when the answer comes back.
    func testAToolCallFromAClientsLineChangesTheDraftInTheApplication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pt-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let tools = try XCTUnwrap(tools)
        let channel = MCPAppChannel(directory: directory) { tools.answer($0) }
        XCTAssertTrue(channel.start())
        addTeardownBlock { await channel.stop() }
        let path = channel.path
        let line = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"set_panel_layout","arguments":{"blocks":{"Codex":{"widget":"number"}}}}}"#

        var answer: [String: JSONValue] = [:]
        for _ in 0..<300 {
            let lines = await Task.detached {
                MCPServer(version: "0", call: { MCPAppClient.call($0, socket: path, timeout: 5) }).lines(for: line)
            }.value
            answer = try XCTUnwrap(JSONValue.parse(Data(try XCTUnwrap(lines.first).utf8)).objectValue)
            let text = answer["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? ""
            // The listener comes up on the main queue, so the first calls may find nobody serving yet.
            guard text.contains("not running") else { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(answer["id"], .integer(7))
        let result = try XCTUnwrap(answer["result"]?.objectValue)
        XCTAssertNotEqual(result["isError"], .bool(true))
        let text = try XCTUnwrap(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let panel = try XCTUnwrap(JSONValue.parse(Data(text.utf8)).objectValue)
        XCTAssertEqual(panel["unsaved"], .bool(true))
        XCTAssertEqual(layout.draft, PanelLayout(blocks: ["Codex": PanelLayout.Block(widget: .number)]))
    }
}
