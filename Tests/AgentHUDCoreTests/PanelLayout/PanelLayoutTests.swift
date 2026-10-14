import AgentHUDSupport
import XCTest
@testable import AgentHUDCore

/// The layout document: its JSON, what reading it forgives, and when two layouts are the same layout.
final class PanelLayoutTests: XCTestCase {
    private func decode(_ json: String) throws -> PanelLayout {
        try JSONDecoder().decode(PanelLayout.self, from: Data(json.utf8))
    }

    private func encode(_ layout: PanelLayout) throws -> String {
        String(decoding: try RecordCoding.encoder().encode(layout), as: UTF8.self)
    }

    /// Every field set, in the shape an agent sends.
    private let full = PanelLayout(
        blocks: ["Claude": PanelLayout.Block(widget: .ring, measure: .burnRate, hidden: true, hiddenRows: ["claude-weekly"]),
                 "api:DeepSeek": PanelLayout.Block(widget: .number)],
        order: ["Codex", "Claude"], sections: [.blocks, .tokens, .sessions], hiddenSections: [.sessions])

    // MARK: Coding

    func testTheDocumentedShapeReadsIntoEveryField() throws {
        let json = """
            {"blocks": {"Claude": {"widget": "ring", "measure": "burn", "hidden": true, "hiddenRows": ["claude-weekly"]},
                        "api:DeepSeek": {"widget": "number"}},
             "order": ["Codex", "Claude"], "sections": ["blocks", "tokens", "sessions"], "hiddenSections": ["sessions"]}
            """
        XCTAssertEqual(try decode(json), full)
    }

    func testALayoutRoundTripsAndEqualLayoutsAreTheSameBytes() throws {
        let written = try encode(full)
        let expected = [
            #"{"blocks":{"Claude":{"hidden":true,"hiddenRows":["claude-weekly"],"measure":"burn","widget":"ring"},"#,
            #""api:DeepSeek":{"widget":"number"}},"hiddenSections":["sessions"],"order":["Codex","Claude"],"#,
            #""sections":["blocks","tokens","sessions"]}"#,
        ].joined()
        XCTAssertEqual(written, expected, "keys are sorted and nothing unset is written")
        XCTAssertEqual(try decode(written), full)
        XCTAssertEqual(try encode(try decode(written)), written)

        // Equal layouts whose blocks were put in by different routes.
        let keys = (0..<40).map { "vendor-\($0)" }
        var forwards = PanelLayout(), backwards = PanelLayout()
        for key in keys { forwards.blocks[key] = PanelLayout.Block(measure: .tokens) }
        for key in keys.reversed() { backwards.blocks[key] = PanelLayout.Block(measure: .tokens) }
        XCTAssertEqual(forwards, backwards)
        XCTAssertEqual(try RecordCoding.encoder().encode(forwards), try RecordCoding.encoder().encode(backwards))
    }

    /// A tool call's arguments arrive as a JSON value, and a layout goes back as one.
    func testALayoutReadsFromAJSONValueAsFromItsTextAndWritesToOne() throws {
        let arguments = try JSONValue.parse(Data(#"{"blocks": {"Claude": {"widget": "ring", "measure": "pace"}}, "order": ["Codex", 1]}"#.utf8))
        let layout = PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)], order: ["Codex"])
        XCTAssertEqual(try arguments.decode(PanelLayout.self), layout)
        XCTAssertEqual(try JSONValue.from(layout),
                       .object(["blocks": .object(["Claude": .object(["widget": .string("ring")])]), "order": .array([.string("Codex")])]))
        XCTAssertEqual(try JSONValue.from(PanelLayout()), .object([:]))
        XCTAssertThrowsError(try JSONValue.array([]).decode(PanelLayout.self))
    }

    func testAnEmptyObjectIsTheDefaultLayoutAndTheDefaultLayoutIsAnEmptyObject() throws {
        XCTAssertEqual(try decode("{}"), PanelLayout())
        XCTAssertEqual(try encode(PanelLayout()), "{}")
        XCTAssertTrue(try decode("{}").isDefault)
    }

    func testWritingLeavesOutWhatIsUnsetOrEmpty() throws {
        XCTAssertEqual(try encode(PanelLayout(blocks: [:], order: [], sections: [], hiddenSections: [])), "{}")
        let blocks = ["a": PanelLayout.Block(widget: .chart), "b": PanelLayout.Block(hidden: false, hiddenRows: []),
                      "c": PanelLayout.Block(hidden: true), "d": PanelLayout.Block(hiddenRows: ["x"])]
        XCTAssertEqual(try encode(PanelLayout(blocks: blocks)),
                       #"{"blocks":{"a":{"widget":"chart"},"b":{},"c":{"hidden":true},"d":{"hiddenRows":["x"]}}}"#)
        XCTAssertEqual(try encode(PanelLayout(hiddenSections: [.tokens])), #"{"hiddenSections":["tokens"]}"#)
    }

    // MARK: Forgiving what it reads

    func testAnUnknownWidgetOrMeasureLeavesOnlyThatFieldUnset() throws {
        let layout = try decode("""
            {"blocks": {"Claude": {"widget": "gauge", "measure": "burn", "hidden": true},
                        "Codex": {"widget": "ring", "measure": "velocity", "hiddenRows": ["codex"]}}}
            """)
        XCTAssertEqual(layout.blocks["Claude"], PanelLayout.Block(measure: .burnRate, hidden: true))
        XCTAssertEqual(layout.blocks["Codex"], PanelLayout.Block(widget: .ring, hiddenRows: ["codex"]))
        // The measure is written "burn", not by its case name.
        XCTAssertEqual(try decode(#"{"blocks": {"Claude": {"measure": "burnRate"}}}"#).blocks["Claude"], PanelLayout.Block())
    }

    func testAnUnknownSectionIsLeftOut() throws {
        let layout = try decode(#"{"sections": ["sessions", "weather", "blocks"], "hiddenSections": ["weather", "tokens"]}"#)
        XCTAssertEqual(layout.sections, [.sessions, .blocks])
        XCTAssertEqual(layout.hiddenSections, [.tokens])
    }

    func testABlockThatIsNotAnObjectIsLeftOutAndTheOthersStay() throws {
        let layout = try decode(#"{"blocks": {"a": "ring", "b": 3, "c": ["ring"], "d": null, "e": true, "f": {"widget": "ring"}}}"#)
        XCTAssertEqual(layout.blocks, ["f": PanelLayout.Block(widget: .ring)])
        XCTAssertEqual(try decode(#"{"blocks": ["Claude"], "order": ["Claude"]}"#), PanelLayout(order: ["Claude"]),
                       "blocks that are not an object are none, and the rest of the layout stays")
    }

    func testUnknownKeysAreIgnored() throws {
        let layout = try decode("""
            {"version": 2, "theme": {"accent": "red"}, "order": ["Claude"],
             "blocks": {"Claude": {"widget": "ring", "size": "large", "rows": 3}}}
            """)
        XCTAssertEqual(layout, PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)], order: ["Claude"]))
    }

    func testAValueOfTheWrongTypeCountsAsNotGiven() throws {
        XCTAssertEqual(try decode(#"{"order": "Claude", "sections": {"blocks": 1}, "hiddenSections": 4}"#), PanelLayout())
        XCTAssertEqual(try decode(#"{"order": ["Claude", 7, null, ["Codex"], "Codex"], "sections": ["tokens", 2]}"#),
                       PanelLayout(order: ["Claude", "Codex"], sections: [.tokens]), "what is not a string is left out of a list")
        let block = try decode(#"{"blocks": {"Claude": {"widget": 1, "measure": ["cost"], "hidden": "yes", "hiddenRows": "all"}}}"#)
        XCTAssertEqual(block.blocks, ["Claude": PanelLayout.Block()])
        XCTAssertEqual(try decode(#"{"blocks": {"Claude": {"hidden": 1, "hiddenRows": ["a", 2, "b"]}}}"#).blocks["Claude"],
                       PanelLayout.Block(hiddenRows: ["a", "b"]))
    }

    func testOnlyJSONThatIsNotAnObjectFails() {
        for json in ["[]", #"["blocks"]"#, #""ring""#, "3", "true", "null", "", "{", #"{"order": ["Claude"]"#] {
            XCTAssertThrowsError(try decode(json), json)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(PanelLayout.Block.self, from: Data(#""ring""#.utf8)))
        XCTAssertEqual(try JSONDecoder().decode(PanelLayout.Block.self, from: Data(#"{"widget": "bar"}"#.utf8)),
                       PanelLayout.Block(widget: .bar))
    }

    // MARK: The same layout

    func testNormalizingDropsBlocksThatChangeNothing() {
        let layout = PanelLayout(blocks: [
            "nothing": PanelLayout.Block(), "shown": PanelLayout.Block(hidden: false), "no-rows": PanelLayout.Block(hiddenRows: []),
            "empty-rows": PanelLayout.Block(hiddenRows: ["", ""]), "widget": PanelLayout.Block(widget: .bar),
            "measure": PanelLayout.Block(measure: .quota), "hidden": PanelLayout.Block(hidden: true),
            "rows": PanelLayout.Block(hiddenRows: ["a"]),
        ])
        XCTAssertEqual(layout.normalized().blocks.keys.sorted(), ["hidden", "measure", "rows", "widget"],
                       "a widget or measure that is its block's default is still a recorded choice")
    }

    func testNormalizingKeepsTheFirstOfRepeatedKeysAndDropsEmptyOnes() {
        let layout = PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring, hiddenRows: ["b", "", "a", "b", "a"])],
                                 order: ["Codex", "", "Claude", "Codex", "Claude", "Cursor"],
                                 sections: [.sessions, .blocks, .sessions, .blocks],
                                 hiddenSections: [.sessions, .tokens, .sessions])
        XCTAssertEqual(layout.normalized(), PanelLayout(
            blocks: ["Claude": PanelLayout.Block(widget: .ring, hiddenRows: ["a", "b"])], order: ["Codex", "Claude", "Cursor"],
            sections: [.sessions, .blocks, .tokens], hiddenSections: [.tokens, .sessions]))
        XCTAssertEqual(layout.normalized().normalized(), layout.normalized())
    }

    func testListsThatSayTheSameInAnotherOrderAreTheSameLayout() {
        let one = PanelLayout(blocks: ["Claude": PanelLayout.Block(hiddenRows: ["weekly", "session"])],
                              sections: [.tokens], hiddenSections: [.sessions, .blocks])
        let other = PanelLayout(blocks: ["Claude": PanelLayout.Block(hiddenRows: ["session", "weekly"])],
                                sections: [.tokens, .blocks, .sessions], hiddenSections: [.blocks, .sessions])
        XCTAssertEqual(one.normalized(), other.normalized())
        XCTAssertNotEqual(PanelLayout(order: ["Claude", "Codex"]).normalized(), PanelLayout(order: ["Codex", "Claude"]).normalized(),
                          "the order of blocks is what `order` says")
    }

    func testAHiddenSectionKeepsItsPlaceInTheOrder() {
        let layout = PanelLayout(sections: [.sessions, .tokens], hiddenSections: [.sessions])
        XCTAssertEqual(layout.normalized(), PanelLayout(sections: [.sessions, .tokens, .blocks], hiddenSections: [.sessions]))
    }

    func testTwoLayoutsAreTheSameLayoutWhenTheirNormalizedValuesAreEqual() {
        let written = PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring), "Codex": PanelLayout.Block()],
                                  order: ["Claude", "Claude"], hiddenSections: [.tokens, .tokens])
        let same = PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)], order: ["Claude"], hiddenSections: [.tokens])
        XCTAssertNotEqual(written, same)
        XCTAssertEqual(written.normalized(), same.normalized())
        XCTAssertNotEqual(same.normalized(), PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .number)], order: ["Claude"],
                                                         hiddenSections: [.tokens]).normalized())
    }

    func testALayoutIsTheDefaultWhenNothingIsLeftOfItNormalized() {
        XCTAssertTrue(PanelLayout().isDefault)
        XCTAssertTrue(PanelLayout(blocks: ["Claude": PanelLayout.Block(), "Codex": PanelLayout.Block(hiddenRows: [""])], order: [""]).isDefault)
        XCTAssertTrue(PanelLayout(sections: [.blocks, .tokens, .sessions]).isDefault, "the default order, written out")
        XCTAssertTrue(PanelLayout(sections: [.blocks]).isDefault)
        let changes = [
            PanelLayout(blocks: ["Claude": PanelLayout.Block(hidden: true)]), PanelLayout(order: ["Claude"]),
            PanelLayout(sections: [.tokens]), PanelLayout(hiddenSections: [.tokens]),
        ]
        for layout in changes { XCTAssertFalse(layout.isDefault, "\(layout)") }
    }
}
