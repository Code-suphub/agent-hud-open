import AgentHUDSupport
import XCTest
@testable import AgentHUDCore

/// The questions the Claude desktop app asks through its own tools, which no permission hook reports: read from the call
/// that asks them, standing until the log says they were answered, and shown on the HUD without answers to give.
///
/// The fixtures are lines Claude Code wrote in the desktop app, kept key for key; only the words, the folder and the
/// session were replaced.
@MainActor
final class ClaudeDesktopAsksTests: XCTestCase {
    private let session = "5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10"

    /// Claude Code 2.1.299: the next-step box's call, its result, which ends the turn, and the prompt its first button sent.
    private let newLines = [
        #"{"parentUuid":"2d49ae76-18e8-43ac-8c3a-c8632de1c21e","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg6L42uzxBrMyoiA5q98A","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01B46399NiDSNkLaGssQPzWp","name":"mcp__ccd_turn__wrap_up","input":{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."},{"label":"Not yet","message":"Leave it uncommitted for now."}]},"caller":{"type":"direct"}}],"container":null,"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":1731,"cache_read_input_tokens":361651,"output_tokens":316,"output_tokens_details":{"thinking_tokens":0},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":1731,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":316,"cache_read_input_tokens":361651,"cache_creation_input_tokens":1731,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1731},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"wireToolInputs":{"toolu_01B46399NiDSNkLaGssQPzWp":{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."},{"label":"Not yet","message":"Leave it uncommitted for now."}]}},"serverClassifierRequest":"45af2749-a66d-4cbb-8507-5a70f3bdea5e","apiBlockIndex":0,"requestId":"req_011Cg6L41jKU8vTdwGf1eXNb","requestedModel":"claude-opus-5-5","attributionMcpServer":"ccd_session","attributionMcpTool":"start_session","type":"assistant","uuid":"685bc2ca-b40f-42e3-99a3-ecd9e9458bb6","timestamp":"2026-10-16T17:42:46.919Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.299","gitBranch":"main","slug":"quiet-river"}"#,
        #"{"parentUuid":"685bc2ca-b40f-42e3-99a3-ecd9e9458bb6","isSidechain":false,"promptId":"ef86bc36-7b2d-4732-b881-e42fe123e2f8","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01B46399NiDSNkLaGssQPzWp","type":"tool_result","content":[{"type":"text","text":"Shown in the next-step box. The box ends your turn: write no text after this call, since the recap and question already say what the user needs."}]}]},"uuid":"df12db2a-3e37-4230-9bab-8a5e99adcfcf","timestamp":"2026-10-16T17:42:46.928Z","toolUseResult":[{"type":"text","text":"Shown in the next-step box. The box ends your turn: write no text after this call, since the recap and question already say what the user needs."}],"mcpMeta":{"_meta":{"claude/endTurn":true}},"sourceToolAssistantUUID":"685bc2ca-b40f-42e3-99a3-ecd9e9458bb6","permissionDecision":{"decision":"accept","source":"config","reasonType":"rule"},"userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.299","gitBranch":"main","slug":"quiet-river"}"#,
        #"{"parentUuid":"df12db2a-3e37-4230-9bab-8a5e99adcfcf","isSidechain":false,"promptId":"b1180fc6-f000-4302-a0bc-6991af9cb1a8","type":"user","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>\nLinked sessions now: none.\n</system-reminder>\n\n"},{"type":"text","text":"Commit the parser change now."}]},"uuid":"692cb8a3-373a-42f0-9c9c-975e3d7f87aa","timestamp":"2026-10-16T18:10:24.371Z","permissionMode":"auto","origin":{"kind":"human"},"promptSource":"sdk","turnOrigin":"human","turnPosition":{"promptIndex":58,"turnIndex":93},"userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.299","gitBranch":"main","slug":"quiet-river"}"#,
    ]

    /// Claude Code 2.1.295: the same box, whose turn still ended with an answer of its own and a Stop hook summary.
    private let oldLines = [
        #"{"parentUuid":"764e4c92-f31d-4326-a434-6d7d867fdc58","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg61vPgrQ86wRL6errFUi","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01AR3dzCuVf3Xd4UwYWZmiSa","name":"mcp__ccd_turn__wrap_up","input":{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."}]},"caller":{"type":"direct"}}],"container":null,"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":1303,"cache_read_input_tokens":289699,"output_tokens":318,"output_tokens_details":{"thinking_tokens":0},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":1303,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":318,"cache_read_input_tokens":289699,"cache_creation_input_tokens":1303,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":1303},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"wireToolInputs":{"toolu_01AR3dzCuVf3Xd4UwYWZmiSa":{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."}]}},"serverClassifierRequest":"efa273a0-1b6c-4ed3-b09a-d55b162f19fd","apiBlockIndex":0,"requestId":"req_011Cg61vPFnsqZ8tkudRBtZx","requestedModel":"claude-opus-5-5","attributionMcpServer":"ccd_pr","attributionMcpTool":"get_status","type":"assistant","uuid":"d0df444a-3db7-438d-bea6-015823b2a673","timestamp":"2026-10-16T13:44:59.683Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main","slug":"quiet-river"}"#,
        #"{"parentUuid":"d0df444a-3db7-438d-bea6-015823b2a673","isSidechain":false,"promptId":"ba188790-fd22-4460-84c7-1300b36b4924","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01AR3dzCuVf3Xd4UwYWZmiSa","type":"tool_result","content":[{"type":"text","text":"Shown in the next-step box. The box ends your turn: write no text after this call, since the recap and question already say what the user needs."}]}]},"uuid":"4f00c6e4-7cbf-4ab7-a68b-54a94dd6fbc7","timestamp":"2026-10-16T13:44:59.696Z","toolUseResult":[{"type":"text","text":"Shown in the next-step box. The box ends your turn: write no text after this call, since the recap and question already say what the user needs."}],"sourceToolAssistantUUID":"d0df444a-3db7-438d-bea6-015823b2a673","permissionDecision":{"decision":"accept","source":"config","reasonType":"rule"},"userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main","slug":"quiet-river"}"#,
        #"{"parentUuid":"4f00c6e4-7cbf-4ab7-a68b-54a94dd6fbc7","isSidechain":false,"attachment":{"type":"total_tokens_reminder","text":"<total_tokens>1000 tokens left</total_tokens>"},"type":"attachment","uuid":"3b6dd513-9cd1-4915-bd12-0ab79f3f6a9a","timestamp":"2026-10-16T13:45:00.184Z","rendered":[{"content":"<system-reminder>\n<total_tokens>1000 tokens left</total_tokens>\n</system-reminder>"}],"renderedRole":"system","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main","slug":"quiet-river"}"#,
        #"{"parentUuid":"3b6dd513-9cd1-4915-bd12-0ab79f3f6a9a","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg61vovcWULpLW31DWhHw","type":"message","role":"assistant","content":[{"type":"text","text":"__RAW_PASSTHROUGH__"}],"container":null,"stop_reason":"end_turn","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":575,"cache_read_input_tokens":291002,"output_tokens":17,"output_tokens_details":{"thinking_tokens":0},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":575,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":17,"cache_read_input_tokens":291002,"cache_creation_input_tokens":575,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":575},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"serverClassifierRequest":"e46edb6e-0255-43d1-8eb6-676126449042","apiBlockIndex":0,"requestId":"req_011Cg61vnnQrFAayJjHLdbDo","requestedModel":"claude-opus-5-5","attributionMcpServer":"ccd_turn","attributionMcpTool":"wrap_up","type":"assistant","uuid":"f5a9b3b0-018d-449d-b0d0-7ccd8e1acf03","timestamp":"2026-10-16T13:45:02.750Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main","slug":"quiet-river"}"#,
        #"{"parentUuid":"f5a9b3b0-018d-449d-b0d0-7ccd8e1acf03","isSidechain":false,"type":"system","subtype":"stop_hook_summary","hookCount":2,"hookInfos":[{"command":"callback"},{"command":"callback"}],"hookErrors":[],"hookAdditionalContext":[],"preventedContinuation":false,"stopReason":"","hasOutput":false,"level":"suggestion","timestamp":"2026-10-16T13:45:06.230Z","uuid":"47688d14-a7f8-42cc-aada-1fc36c2bbfa2","toolUseID":"3adefb54-5bdd-41a5-b64e-380422ba00d6","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main","slug":"quiet-river"}"#,
    ]

    /// Claude Code 2.1.295: a card offering a task its own session, answered 64 seconds later by the user writing instead.
    private let offerLines = [
        #"{"parentUuid":"ae283af9-0ada-4b62-82ee-39c41fe45a7e","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg5ctT8yyLEHhWW2jQGrm","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01RKvY63FebVFQyZ6JbZfacn","name":"mcp__ccd_session__start_session","input":{"initiation":"offer","title":"Split the parser into two files"},"caller":{"type":"direct"}}],"container":null,"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":600,"cache_read_input_tokens":211988,"output_tokens":1658,"output_tokens_details":{"thinking_tokens":1561},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":600,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":1658,"cache_read_input_tokens":211988,"cache_creation_input_tokens":600,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":600},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"wireToolInputs":{"toolu_01RKvY63FebVFQyZ6JbZfacn":{"initiation":"offer","title":"Split the parser into two files"}},"serverClassifierRequest":"b951deee-c60f-4152-8b69-1d0d2ad9d490","apiBlockIndex":1,"requestId":"req_011Cg5ctN9bV8QNzxh3tdED4","requestedModel":"claude-opus-5-5","type":"assistant","uuid":"e8f8a31c-5dc3-4de4-a8d3-2bbcd5e504d9","timestamp":"2026-10-16T08:43:14.463Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main"}"#,
        #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-10-16T08:44:18.199Z","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","content":"Leave the parser in one file."}"#,
        #"{"parentUuid":"e8f8a31c-5dc3-4de4-a8d3-2bbcd5e504d9","isSidechain":false,"promptId":"ebaadcfd-b659-432f-a75d-faa5b85e953c","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01RKvY63FebVFQyZ6JbZfacn","type":"tool_result","content":[{"type":"text","text":"The user did not answer the card: they sent a new message instead."}]}]},"uuid":"da7e9ace-47f4-425f-9903-367973911b32","timestamp":"2026-10-16T08:44:18.200Z","toolUseResult":[{"type":"text","text":"The user did not answer the card: they sent a new message instead."}],"serverClassifierContext":{},"sourceToolAssistantUUID":"e8f8a31c-5dc3-4de4-a8d3-2bbcd5e504d9","permissionDecision":{"decision":"accept","source":"hook","reasonType":"hook"},"userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.295","gitBranch":"main"}"#,
    ]

    /// Claude Code 2.1.299: the task list's last tick and the next-step box, two calls of one response.
    private let pairLines = [
        #"{"parentUuid":"f2fcdb92-e931-4bf1-b884-6d988400487d","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg6GhdL2R4XVneM7tG4oN","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01GLPbHpuZ2BWBDqSa2avXHJ","name":"mcp__ccd_turn__update_plan","input":{"items":[{"content":"Write the parser","status":"completed"}],"scope":"continuation"},"caller":{"type":"direct"}}],"container":null,"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":3161,"cache_read_input_tokens":932001,"output_tokens":2631,"output_tokens_details":{"thinking_tokens":1941},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":3161,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":2631,"cache_read_input_tokens":932001,"cache_creation_input_tokens":3161,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":3161},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"wireToolInputs":{"toolu_01GLPbHpuZ2BWBDqSa2avXHJ":{"items":[{"content":"Write the parser","status":"completed"}],"scope":"continuation"}},"serverClassifierRequest":"95e35b59-0636-4861-936d-84f34edb81bc","apiBlockIndex":3,"requestId":"req_011Cg6GhcoGWvtDeUSzywKTf","requestedModel":"claude-opus-5-5","type":"assistant","uuid":"13796701-091f-4bc7-ad3d-6751d7900c48","timestamp":"2026-10-16T16:59:08.406Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.299","gitBranch":"main"}"#,
        #"{"parentUuid":"13796701-091f-4bc7-ad3d-6751d7900c48","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg6GhdL2R4XVneM7tG4oN","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_01TYbNDsdLwek4btH85g571J","name":"mcp__ccd_turn__wrap_up","input":{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."},{"label":"Not yet","message":"Leave it uncommitted for now."}]},"caller":{"type":"direct"}}],"container":null,"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":3161,"cache_read_input_tokens":932001,"output_tokens":2631,"output_tokens_details":{"thinking_tokens":1941},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":3161,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":2631,"cache_read_input_tokens":932001,"cache_creation_input_tokens":3161,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":3161},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"wireToolInputs":{"toolu_01TYbNDsdLwek4btH85g571J":{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."},{"label":"Not yet","message":"Leave it uncommitted for now."}]}},"serverClassifierRequest":"95e35b59-0636-4861-936d-84f34edb81bc","apiBlockIndex":4,"requestId":"req_011Cg6GhcoGWvtDeUSzywKTf","requestedModel":"claude-opus-5-5","type":"assistant","uuid":"3444e8b1-16d5-4176-8226-4ac3b590d05c","timestamp":"2026-10-16T16:59:10.860Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.299","gitBranch":"main"}"#,
    ]

    private func parse(_ lines: [String]) -> [TranscriptEvent] {
        FastTranscriptParser.parse(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private func accumulate(_ lines: [String]) -> TranscriptAccumulator {
        var accumulator = TranscriptAccumulator(path: "/logs/\(session).jsonl", isSubagent: false)
        accumulator.ingest(parse(lines))
        return accumulator
    }

    private func date(_ text: String) -> Date { ISO8601Fast.parse(text)! }

    /// What each line asks, dated to the millisecond: the two parsers read fractions of a second a little differently.
    private func asks(_ events: [TranscriptEvent]) -> [SessionActivity.Ask?] {
        events.map { event in
            event.ask.map { .init(id: $0.id, response: $0.response, kind: $0.kind, question: $0.question, recap: $0.recap,
                                  options: $0.options, at: RecordCoding.date(RecordCoding.milliseconds($0.at))) }
        }
    }

    // MARK: Reading the call

    func testBothParsersReadTheNextStepBoxFromItsCallAndTheTurnsEndFromItsResult() throws {
        let fast = parse(newLines), slow = ClaudeTranscriptParser.parse(newLines.joined(separator: "\n"))
        XCTAssertEqual(asks(fast), asks(slow))
        XCTAssertEqual(fast.map(\.endsTurn), slow.map(\.endsTurn))
        let ask = try XCTUnwrap(fast[0].ask)
        XCTAssertEqual(ask.kind, .nextStep)
        XCTAssertEqual(ask.id, "toolu_01B46399NiDSNkLaGssQPzWp")
        XCTAssertEqual(ask.response, "msg_011Cg6L42uzxBrMyoiA5q98A")
        XCTAssertEqual(ask.question, "Should I commit it now?")
        XCTAssertEqual(ask.recap, "The parser change is in; the tests pass. Nothing is committed yet.")
        XCTAssertEqual(ask.options, [.init(label: "Commit it", message: "Commit the parser change now."),
                                     .init(label: "Not yet", message: "Leave it uncommitted for now.")])
        XCTAssertEqual(ask.at, date("2026-10-16T17:42:46.919Z"))
        XCTAssertEqual(fast.map(\.endsTurn), [false, true, false], "only the box's result carries the client's end of the turn")
        XCTAssertEqual(fast[1].toolResultID, ask.id)
        XCTAssertTrue(fast[2].isPrompt, "the button's words arrive as the user's next prompt")
    }

    func testAnOfferNamesItsTaskAndTheAppsTwoButtons() throws {
        let fast = parse(offerLines), slow = ClaudeTranscriptParser.parse(offerLines.joined(separator: "\n"))
        XCTAssertEqual(asks(fast), asks(slow))
        let ask = try XCTUnwrap(fast[0].ask)
        XCTAssertEqual(ask.kind, .offer)
        XCTAssertEqual(ask.question, "Split the parser into two files")
        XCTAssertEqual(ask.options.map(\.label), ["New session", "Do it here"])
        XCTAssertNil(ask.recap)
        XCTAssertFalse(fast[2].endsTurn, "the offer's answer hands the turn back to the agent")
    }

    func testOnlyAQuestionAsksAndOnlyTheDesktopsOwnToolsAreRead() {
        // The box with a recap alone leaves nothing to answer.
        let recapOnly = newLines[0].replacingOccurrences(of: #""ask":"Should I commit it now?","#, with: "")
        XCTAssertNotEqual(recapOnly, newLines[0])
        XCTAssertNil(parse([recapOnly])[0].ask)
        // A session started on the agent's own initiative asks nothing either.
        let started = offerLines[0].replacingOccurrences(of: #""initiation":"offer""#, with: #""initiation":"user_asked""#)
        XCTAssertNotEqual(started, offerLines[0])
        XCTAssertNil(parse([started])[0].ask)
        // Any other tool with the same input is not read.
        let other = newLines[0].replacingOccurrences(of: #""name":"mcp__ccd_turn__wrap_up""#, with: #""name":"mcp__notes__save""#)
        XCTAssertNotEqual(other, newLines[0])
        XCTAssertNil(parse([other])[0].ask)
        XCTAssertNil(ClaudeTranscriptParser.parseLine(other)?.ask)
    }

    func testAnAppActionsButtonShowsTheAppsOwnWords() throws {
        let line = newLines[0].replacingOccurrences(of: #"{"label":"Commit it","message":"Commit the parser change now."}"#,
                                                    with: #"{"label":"Ship","action":"commit"}"#)
        XCTAssertNotEqual(line, newLines[0])
        let ask = try XCTUnwrap(parse([line])[0].ask)
        XCTAssertEqual(ask.options.map(\.label), ["Commit", "Not yet"])
        XCTAssertNil(ask.options[0].message, "the app does the action itself; no words are sent")
    }

    /// The box's input with `fields` in place of the real call's.
    private func box(_ fields: String) -> String {
        let real = #"{"recap":"The parser change is in; the tests pass. Nothing is committed yet.","ask":"Should I commit it now?","actions":[{"label":"Commit it","message":"Commit the parser change now."},{"label":"Not yet","message":"Leave it uncommitted for now."}]}"#
        XCTAssertNotNil(newLines[0].range(of: real))
        return newLines[0].replacingOccurrences(of: real, with: fields)
    }

    func testTheQuestionShowsOnlyAsTheAppDrawsIt() throws {
        XCTAssertNil(parse([box(#"{"ask":"Commit?","actions":[{"label":"Yes"}]}"#)])[0].ask, "the app refuses a box without a recap")
        XCTAssertNil(parse([box(#"{"recap":"Done.","ask":"Commit?"}"#)])[0].ask, "a question with no button is dropped")
        XCTAssertNil(parse([box(#"{"recap":"Done.","ask":"Commit?","actions":[{"label":"/commit"},{"label":"No"}]}"#)])[0].ask,
                     "a first reply the app will not send takes the question with it")
        XCTAssertNil(parse([box(#"{"recap":"Done.","ask":"Commit?","actions":[{"action":"deploy"}]}"#)])[0].ask)
        let blocked = try XCTUnwrap(parse([box(#"{"recap":"Done.","ask":"Which key?","blocked":true,"actions":[{"label":"Ask @ops"},{"label":"Use mine","message":"Use my key."}]}"#)])[0].ask,
                                    "a blocked call keeps its question")
        XCTAssertEqual(blocked.options, [.init(label: "Use mine", message: "Use my key.")], "and the app drops the reply it will not send")
        let many = try XCTUnwrap(parse([box(#"{"recap":"Done.","ask":"Next?","actions":[{"action":"create_pr"},{"action":"new_session"},{"label":"Stop"}]}"#)])[0].ask)
        XCTAssertEqual(many.options.map(\.label), ["Create PR"], "two buttons at most, and a new session is no longer one")
        let spaced = try XCTUnwrap(parse([box(#"{"recap":"Done.","ask":"Next?","actions":[{"label":"  Ship\n it  "}]}"#)])[0].ask)
        XCTAssertEqual(spaced.options.map(\.label), ["Ship it"])
        let earlier = try XCTUnwrap(parse([box(#"{"outcome":"Done.","next_ask":"Commit?","next_actions":[{"label":"Yes"}]}"#)])[0].ask,
                                    "the app still reads the fields' earlier names")
        XCTAssertEqual([earlier.recap, earlier.question], ["Done.", "Commit?"])
    }

    func testABoxTheAppRefusedAsksNothing() throws {
        let refused = newLines[1].replacingOccurrences(of: #""type":"tool_result","content""#, with: #""type":"tool_result","is_error":true,"content""#)
        XCTAssertNotEqual(refused, newLines[1])
        XCTAssertTrue(parse([refused])[0].failed)
        XCTAssertEqual(ClaudeTranscriptParser.parseLine(refused)?.failed, true)
        XCTAssertNil(accumulate([newLines[0], refused]).build()?.activity?.ask)
    }

    // MARK: Standing until answered

    func testTheNextStepBoxEndsTheTurnAndAsksUntilTheNextPrompt() throws {
        let asked = try XCTUnwrap(accumulate(Array(newLines.prefix(2))).build())
        XCTAssertEqual(asked.turn?.state, .completed, "2.1.299 writes no answer and no Stop hook summary after the box")
        XCTAssertEqual(asked.turn?.outcome, .completed)
        XCTAssertEqual(asked.turn?.observedAtMs, RecordCoding.milliseconds(date("2026-10-16T17:42:46.928Z")))
        XCTAssertEqual(asked.activity?.ask?.question, "Should I commit it now?")
        XCTAssertEqual(asked.activity?.line, .answer, "the model has nothing to go on with")
        XCTAssertFalse(asked.activity?.hasOpenCall ?? true)
        let answered = try XCTUnwrap(accumulate(newLines).build())
        XCTAssertNil(answered.activity?.ask, "the next prompt is the answer")
        XCTAssertEqual(answered.turn?.state, .running)
    }

    func testTheOlderBoxStillAsksAfterTheAnswerAndTheStopHookSummaryItsTurnEndedWith() throws {
        let read = try XCTUnwrap(accumulate(oldLines).build())
        XCTAssertEqual(read.turn?.state, .completed)
        XCTAssertEqual(read.activity?.ask?.id, "toolu_01AR3dzCuVf3Xd4UwYWZmiSa")
    }

    func testAnOfferAsksWhileItsCallWaitsAndItsResultAnswersIt() throws {
        let waiting = try XCTUnwrap(accumulate([offerLines[0]]).build())
        XCTAssertEqual(waiting.activity?.ask?.kind, .offer)
        XCTAssertEqual(waiting.turn?.state, .running, "the turn is held by the call, not over")
        let answered = try XCTUnwrap(accumulate(offerLines).build())
        XCTAssertNil(answered.activity?.ask)
    }

    func testTheCallsOfTheBoxsOwnResponseLeaveItAndALaterResponsesCallTakesItBack() throws {
        XCTAssertNotNil(accumulate(pairLines).build()?.activity?.ask, "the task list's tick came first in the same response")
        XCTAssertNotNil(accumulate(pairLines.reversed()).build()?.activity?.ask, "and either order is one response")
        let later = pairLines[0].replacingOccurrences(of: "msg_011Cg6GhdL2R4XVneM7tG4oN", with: "msg_later")
            .replacingOccurrences(of: "2026-10-16T16:59:08.406Z", with: "2026-10-16T16:59:20.000Z")
        XCTAssertNotEqual(later, pairLines[0])
        XCTAssertNil(accumulate(pairLines + [later]).build()?.activity?.ask, "the agent went on without the answer")
    }

    func testTheLedgerKeepsThatTheSessionWaitsButNoneOfTheQuestionsWords() throws {
        let accumulator = accumulate(Array(newLines.prefix(2)))
        let stored = try JSONEncoder().encode(accumulator)
        for words in ["Should I commit it now?", "The parser change is in", "Commit it", "Commit the parser change now."] {
            XCTAssertNil(String(decoding: stored, as: UTF8.self).range(of: words), "no conversation text is stored: \(words)")
        }
        let read = try XCTUnwrap(accumulator.build()?.activity?.ask)
        let kept = try XCTUnwrap(JSONDecoder().decode(TranscriptAccumulator.self, from: stored).build()?.activity?.ask)
        XCTAssertEqual([kept.id, kept.response], [read.id, read.response])
        XCTAssertEqual(kept.kind, read.kind)
        XCTAssertEqual(kept.at, read.at)
        XCTAssertFalse(kept.isWorded)
        XCTAssertTrue(kept.options.isEmpty)
        let session = live(asking: kept, ended: true), then = kept.at.addingTimeInterval(60)
        XCTAssertEqual(view([session], at: then).session(self.session)?.phase.state, .waitingForApproval,
                       "after a relaunch the session still waits")
        XCTAssertTrue(ClaudeDesktopAsks.requests(for: [session], now: then).isEmpty, "no words, no card")
    }

    func testAfterARelaunchTheQuestionsWordsAreReadAgainFromItsOwnLine() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("\(session).jsonl")
        let data = Data((newLines.prefix(2).joined(separator: "\n") + "\n").utf8)
        try data.write(to: log)
        var accumulator = TranscriptAccumulator(path: log.path, isSubagent: false)
        accumulator.ingest(FastTranscriptParser.parse(data, at: 0))
        XCTAssertEqual(accumulator.build()?.activity?.ask?.offset, 0, "the call is the log's first line")
        // What the ledger gives back after a relaunch: that the session asks, where, and none of the words.
        let kept = try JSONDecoder().decode(TranscriptAccumulator.self, from: JSONEncoder().encode(accumulator))
        let session = try XCTUnwrap(kept.build())
        XCTAssertEqual(session.activity?.ask?.isWorded, false)
        let reworded = ClaudeTranscriptStore.reworded(session)
        XCTAssertEqual(reworded.activity?.ask?.question, "Should I commit it now?")
        XCTAssertEqual(reworded.activity?.ask?.options.map(\.label), ["Commit it", "Not yet"])
        XCTAssertEqual(reworded.activity?.ask?.offset, 0)
        XCTAssertEqual(reworded.activity?.ask?.at, session.activity?.ask?.at)
        XCTAssertNotNil(ClaudeDesktopAsks.requests(for: [live(asking: reworded.activity?.ask, ended: true)],
                                                   now: reworded.activity!.ask!.at.addingTimeInterval(60)).first,
                        "and the card is there again")
        // A line that is another call's leaves the question without words rather than with someone else's.
        var moved = kept.build()!
        let elsewhere = SessionActivity.Ask(id: session.activity!.ask!.id, kind: .nextStep, question: "", options: [],
                                            at: session.activity!.ask!.at, offset: newLines[0].utf8.count + 1)
        moved.activity?.open("toolu_other", work: nil, at: elsewhere.at, response: nil, asking: elsewhere)
        XCTAssertEqual(ClaudeTranscriptStore.reworded(moved).activity?.ask?.isWorded, false)
    }

    // MARK: Waiting and the card

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func live(asking ask: SessionActivity.Ask?, ended: Bool) -> LiveSession {
        var activity = SessionActivity()
        activity.startTurn()
        if let ask { activity.open(ask.id, work: nil, at: ask.at, response: ask.response, asking: ask) }
        return LiveSession(id: session, agentId: "claude-model:opus", task: "Parser", terminal: "project",
                           startedAt: now.addingTimeInterval(-3600), endedAt: ended ? now.addingTimeInterval(-120) : nil,
                           pctOfWindow: nil, tokensIn: 1, tokensOut: 1, transcriptPath: "/logs/\(session).jsonl",
                           observedAt: now.addingTimeInterval(-30), workingDirectory: "/Users/dev/project", activity: activity)
    }

    private func box(at second: TimeInterval) -> SessionActivity.Ask {
        .init(id: "toolu_box", response: "msg_box", kind: .nextStep, question: "Should I commit it now?", recap: "Done.",
              options: [.init(label: "Commit it", message: "Commit the parser change now."), .init(label: "Not yet")],
              at: now.addingTimeInterval(second))
    }

    private func view(_ sessions: [LiveSession], at time: Date) -> ReportView {
        ReportView(report: UsageReport(generatedAt: time, snapshots: [], sessions: sessions, discoveredAgents: [], consumers: []),
                   agents: [], settings: Settings(), now: time)
    }

    func testAFinishedTurnsQuestionKeepsItsSessionWaitingAsAQuestion() throws {
        let asked = box(at: -60)
        let view = view([live(asking: asked, ended: true)], at: now)
        let shown = try XCTUnwrap(view.session(session))
        XCTAssertEqual(shown.phase, SessionPhase(state: .waitingForApproval, since: asked.at,
                                                 validUntil: asked.at.addingTimeInterval(ClaudeDesktopAsks.standing)))
        XCTAssertEqual(view.requests(of: shown).map(\.kind), [.question])
        XCTAssertEqual(view.requests(of: shown).map(\.at), [asked.at])
        let later = self.view([live(asking: asked, ended: true)], at: asked.at.addingTimeInterval(ClaudeDesktopAsks.standing))
        XCTAssertEqual(later.session(session)?.phase.state, .idle, "a question nobody answered for that long stops vouching for anyone")
        XCTAssertEqual(self.view([live(asking: nil, ended: true)], at: now).session(session)?.phase.state, .idle)
    }

    func testAnOfferWaitsInsteadOfRunning() throws {
        let offer = SessionActivity.Ask(id: "toolu_offer", kind: .offer, question: "Split the parser",
                                        options: ClaudeDesktopAsks.offerOptions, at: now.addingTimeInterval(-20))
        let view = view([live(asking: offer, ended: false)], at: now)
        let shown = try XCTUnwrap(view.session(session))
        XCTAssertEqual(shown.phase.state, .waitingForApproval)
        XCTAssertEqual(shown.phase.since, now.addingTimeInterval(-3600), "in flight, it waits since the work started")
        XCTAssertEqual(view.requests(of: shown).map(\.kind), [.question])
        XCTAssertEqual(self.view([live(asking: nil, ended: false)], at: now).session(session)?.phase.state, .running)
    }

    func testTheCardShowsTheQuestionAndItsButtonsAndAnswersNothing() throws {
        let asked = box(at: -60)
        let request = try XCTUnwrap(ClaudeDesktopAsks.requests(for: [live(asking: asked, ended: true)], now: now).first)
        XCTAssertEqual(request.source, .claude)
        XCTAssertEqual(request.vendor, "Claude")
        XCTAssertEqual(request.sessionID, session)
        XCTAssertEqual(request.summary, "Should I commit it now?")
        XCTAssertEqual(request.detail, "Done.")
        XCTAssertEqual(request.project, "project")
        XCTAssertEqual(request.at, asked.at)
        XCTAssertEqual(request.nativeApproval, .clientWindow)
        XCTAssertTrue(request.isQuestion)
        XCTAssertFalse(request.answersQuestion, "the app takes the click in its own window")
        XCTAssertEqual(request.badge, "ASK")
        XCTAssertEqual(request.questions.first?.options, [.init(label: "Commit it", description: "Commit the parser change now."),
                                                         .init(label: "Not yet")])
        XCTAssertEqual(PermissionDecision.answer([:]).response(for: request), PermissionDecision.noDecision)
        XCTAssertEqual(AttentionRequest(request).kind, .question)
        XCTAssertTrue(ClaudeDesktopAsks.requests(for: [live(asking: asked, ended: true)],
                                                 now: asked.at.addingTimeInterval(ClaudeDesktopAsks.standing)).isEmpty)
        XCTAssertTrue(ClaudeDesktopAsks.requests(for: [live(asking: nil, ended: true)], now: now).isEmpty)
    }

    func testWithAWayToReplyABoxIsAnsweredWithTheWordsAClickSendsAndAnOfferIsStillOnlyShown() throws {
        let asked = box(at: -60)
        let offer = SessionActivity.Ask(id: "toolu_offer", kind: .offer, question: "Split the parser",
                                        options: ClaudeDesktopAsks.offerOptions, at: now.addingTimeInterval(-20))
        let other = LiveSession(id: "other", agentId: "claude-model:opus", task: "Other", terminal: nil, startedAt: now.addingTimeInterval(-600),
                                pctOfWindow: nil, tokensIn: 1, tokensOut: 1, observedAt: now, activity: {
                                    var activity = SessionActivity()
                                    activity.open(offer.id, work: nil, at: offer.at, asking: offer)
                                    return activity
                                }())
        let requests = ClaudeDesktopAsks.requests(for: [live(asking: asked, ended: true), other], now: now, replies: true)
        XCTAssertEqual(requests.map(\.nativeApproval), [.clientReply, .clientWindow])
        XCTAssertEqual(requests.map(\.answersQuestion), [true, false], "an offer's answer cannot be put in words")
        XCTAssertNotEqual(requests[0].id, ClaudeDesktopAsks.requests(for: [live(asking: asked, ended: true)], now: now).first?.id,
                          "a card that can be answered replaces one that cannot")
        let box = requests[0], key = try XCTUnwrap(box.questions.first?.answerKey)
        func words(_ answer: PermissionQuestion.Answer?) -> String? {
            ClaudeDesktopAsks.words(answering: box, with: answer.map { [key: $0] } ?? [:])
        }
        XCTAssertEqual(words(.init(selected: ["Commit it"])), "Commit the parser change now.", "what the button sends")
        XCTAssertEqual(words(.init(selected: ["Not yet"])), "Not yet", "a button without words sends its label")
        XCTAssertEqual(words(.init(selected: ["Commit it"], custom: "  Commit, then push  ")), "Commit, then push", "the user's own words")
        XCTAssertNil(words(nil), "a box left unanswered sends nothing")
        XCTAssertNil(words(.init(selected: ["Push it"])), "nor does a label the box does not offer")
    }

    func testAnAnswerOnTheHUDIsSentIntoTheSessionAndOneThatCouldNotBeBringsTheCardBack() async throws {
        let queue = PermissionRequests(), asking = live(asking: box(at: -60), ended: true)
        var sent: [(String, String)] = [], failing = false
        let delivered = expectation(description: "sent")
        let reply: ClaudeDesktopAsks.Reply = { sessionID, words in
            if failing { throw CocoaError(.fileWriteNoPermission) }
            sent.append((sessionID, words))
            delivered.fulfill()
        }
        ClaudeDesktopAsks.show([asking], now: now, in: queue, reply: reply)
        let request = try XCTUnwrap(queue.pending.first)
        let key = try XCTUnwrap(request.questions.first?.answerKey)
        queue.resolve(request.id, .answer([key: .init(selected: ["Commit it"])]))
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(sent.map(\.0), [session])
        XCTAssertEqual(sent.map(\.1), ["Commit the parser change now."])
        XCTAssertTrue(queue.pending.isEmpty, "answered, the card goes until the next prompt takes the question away")

        // Left unanswered, nothing goes in.
        let next = SessionActivity.Ask(id: "toolu_next", response: "msg_next", kind: .nextStep, question: "Push it too?",
                                       recap: "Committed.", options: [.init(label: "Push"), .init(label: "Not yet")],
                                       at: now.addingTimeInterval(-30))
        let other = live(asking: next, ended: true)
        ClaudeDesktopAsks.show([other], now: now, in: queue, reply: reply)
        let skipped = try XCTUnwrap(queue.pending.first)
        queue.resolve(skipped.id, .answer([:]))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sent.count, 1)

        // Words that could not be left for the session leave the question to be answered again.
        failing = true
        ClaudeDesktopAsks.show([], now: now, in: queue, reply: reply)
        ClaudeDesktopAsks.show([other], now: now, in: queue, reply: reply)
        let retried = try XCTUnwrap(queue.pending.first)
        queue.resolve(retried.id, .answer([try XCTUnwrap(retried.questions.first?.answerKey): .init(selected: ["Not yet"])]))
        try await Task.sleep(for: .milliseconds(50))
        ClaudeDesktopAsks.show([other], now: now, in: queue, reply: reply)
        XCTAssertEqual(queue.pending.map(\.id), [retried.id])
    }

    func testTheQueueShowsTheCardUntilTheLogSaysItWasAnsweredAndPuttingItAwayOnlyHidesIt() throws {
        let queue = PermissionRequests()
        let asking = live(asking: box(at: -60), ended: true)
        ClaudeDesktopAsks.show([asking], now: now, in: queue)
        let id = try XCTUnwrap(queue.pending.first?.id)
        XCTAssertEqual(queue.pending.count, 1)
        ClaudeDesktopAsks.show([asking], now: now, in: queue)
        XCTAssertEqual(queue.pending.map(\.id), [id], "reading the same log again shows the same card once")
        queue.resolve(id, .leave)
        XCTAssertTrue(queue.pending.isEmpty)
        ClaudeDesktopAsks.show([asking], now: now, in: queue)
        XCTAssertTrue(queue.pending.isEmpty, "a card put away stays away while its question stands")
        ClaudeDesktopAsks.show([live(asking: nil, ended: true)], now: now, in: queue)
        ClaudeDesktopAsks.show([asking], now: now, in: queue)
        XCTAssertEqual(queue.pending.map(\.id), [id], "a dismissal lasts only as long as its question")
        ClaudeDesktopAsks.show([], now: now, in: queue)
        XCTAssertTrue(queue.pending.isEmpty)
    }
}
