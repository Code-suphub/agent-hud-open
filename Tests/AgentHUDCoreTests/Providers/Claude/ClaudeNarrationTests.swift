import XCTest
@testable import AgentHUDCore

/// The words the agent says between its calls when the Claude desktop app asks for updates, which Claude Code writes as
/// thinking blocks a signature names narrations: they are what the user reads, so they are the turn's words, while any
/// other thinking block stays the agent's reasoning.
final class ClaudeNarrationTests: XCTestCase {
    /// A length-delimited protobuf field shorter than 128 bytes.
    private func field(_ number: UInt8, _ bytes: [UInt8]) -> [UInt8] { [number << 3 | 2, UInt8(bytes.count)] + bytes }

    /// A signature shaped as the desktop app reads one: varint and fixed fields around the nested kind, base64 without
    /// its padding. The real ones carry more, which a reader passes over the same way.
    private func signature(_ kind: String) -> String {
        let named: [UInt8] = [0x08, 0x12, 0x18, 0x02, 0x38, 0x01] + field(8, Array(kind.utf8))
        let block = field(1, named) + field(2, Array(repeating: 0xAB, count: 40))
        let outer: [UInt8] = [0x08, 0x04] + field(2, block) + [0x29] + Array(repeating: 0, count: 8)
        return Data(outer).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// A line Claude Code 2.1.299 wrote in the desktop app with updates on, kept key for key; only its words, the folder
    /// and the session were replaced, and its signature with one of the same shape.
    private func line(_ text: String, signature: String) -> String {
        #"{"parentUuid":"44f763c2-2157-4f89-af92-0a94fa5092dc","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_011Cg7NQk4YwBwLvY1h6tPmm","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"\#(text)","signature":"\#(signature)"}],"container":null,"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"usage":{"input_tokens":2,"cache_creation_input_tokens":2970,"cache_read_input_tokens":574242,"output_tokens":958,"output_tokens_details":{"thinking_tokens":461},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":2970,"ephemeral_5m_input_tokens":0},"inference_geo":"global","iterations":[{"input_tokens":2,"output_tokens":958,"cache_read_input_tokens":574242,"cache_creation_input_tokens":2970,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":2970},"type":"message"}],"speed":"standard","fallback_credit":null},"input_transformations":[],"diagnostics":null,"context_management":null},"thinkingDurationMs":3,"thinkingDisplay":"updates","serverClassifierRequest":"00000000-0000-0000-0000-000000000000","apiBlockIndex":1,"requestId":"req_011Cg7NQigiDG2skqgjLmDfR","requestedModel":"claude-opus-5-5","type":"assistant","uuid":"fb9dc843-ada7-4755-9321-b4b644635c58","timestamp":"2026-10-17T06:54:20.607Z","advisorModel":"claude-opus-5-5","effort":"xhigh","perTurnEffort":"xhigh","userType":"external","entrypoint":"claude-desktop","cwd":"/Users/dev/project","sessionId":"5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10","version":"2.1.299","gitBranch":"main"}"#
    }

    private let words = "The watch fix is on main; it shows once the new build is installed."

    func testTheSignatureNamesItsKindAsTheAppReadsIt() {
        XCTAssertEqual(ClaudeNarration.kind(ofSignature: signature("narration")), "narration")
        XCTAssertEqual(ClaudeNarration.kind(ofSignature: signature("thinking")), "thinking")
        XCTAssertTrue(ClaudeNarration.isNarration(signature: signature("narration")))
        XCTAssertFalse(ClaudeNarration.isNarration(signature: signature("thinking")))
        XCTAssertFalse(ClaudeNarration.isNarration(signature: ""))
        XCTAssertFalse(ClaudeNarration.isNarration(signature: "not base64 at all"))
        let cut = Data(base64Encoded: signature("narration") + "==")!.prefix(20).base64EncodedString()
        XCTAssertNil(ClaudeNarration.kind(ofSignature: cut), "a message that does not read to its end names nothing")
    }

    func testANarrationIsTheAgentsWordsAndOtherThinkingIsNot() throws {
        let narration = line(words + "\\n\\n", signature: signature("narration"))
        let thinking = line("", signature: signature("thinking"))
        let unread = line("Weighing it", signature: "bm90IGEgc2lnbmF0dXJl")
        let lines = [narration, thinking, unread]
        let fast = FastTranscriptParser.parse(Data((lines.joined(separator: "\n") + "\n").utf8))
        let slow = ClaudeTranscriptParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(fast.map(\.isThinking), [false, true, true])
        XCTAssertEqual(slow.map(\.isThinking), [false, true, true])
        XCTAssertEqual(fast[0].text, words + "\n\n")
        XCTAssertEqual(fast[1].text, nil)
        XCTAssertEqual(fast[2].text, nil, "a thinking block's own words are never shown")
    }

    func testANarrationIsTheTurnsMessage() throws {
        let session = "5b1c0d2e-7a41-4f3e-9c55-0d6e2f8a9b10"
        let prompt = #"{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"Fix the watch."},"uuid":"u1","timestamp":"2026-10-17T06:54:11.251Z","cwd":"/Users/dev/project","sessionId":"\#(session)"}"#
        var accumulator = TranscriptAccumulator(path: "/logs/\(session).jsonl", isSubagent: false)
        accumulator.ingest(FastTranscriptParser.parse(Data((prompt + "\n" + line(words + "\\n\\n", signature: signature("narration")) + "\n").utf8)))
        let read = try XCTUnwrap(accumulator.build())
        XCTAssertEqual(read.turn?.message, words)
        XCTAssertEqual(read.activity?.line, .text, "the agent said something and went on")
    }
}
