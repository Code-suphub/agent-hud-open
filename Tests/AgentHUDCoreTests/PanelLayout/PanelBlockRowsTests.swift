import XCTest
@testable import AgentHUDCore

/// A block's rows in the layout's order and its accounts as the layout chooses them, against the blocks the panel has:
/// a Claude block of two accounts, Personal with three windows and Work with two, and an API provider billing two.
final class PanelBlockRowsTests: XCTestCase {
    private let blocks = [
        PanelBlockInfo(key: "Claude", kind: .quota, rowKeys: ["claude-session", "claude-weekly", "claude-weekly-fable"], accounts: [
            .init(id: "account:personal", name: "Personal", rowKeys: ["claude-session", "claude-weekly", "claude-weekly-fable"]),
            .init(id: "account:work", name: "jazzen@work.example", rowKeys: ["claude-session", "claude-weekly"]),
        ]),
        PanelBlockInfo(key: "Codex", kind: .quota, rowKeys: ["codex"], accounts: [.init(id: "", rowKeys: ["codex"])]),
        PanelBlockInfo(key: "api:Moonshot", kind: .billing, accounts: [
            .init(id: "pool:first", name: "Moonshot · API"), .init(id: "pool:second", name: "Moonshot · API"),
        ]),
    ]

    private func plan(_ layout: PanelLayout) -> PanelLayoutPlan { PanelLayoutPlan(layout: layout, blocks: blocks) }

    private func block(_ key: String, in layout: PanelLayout) -> PanelBlockPlan? { plan(layout).blocks.first { $0.key == key } }

    private func claude(_ change: PanelLayout.Block) -> PanelLayout { PanelLayout(blocks: ["Claude": change]) }

    // MARK: The order of a block's rows

    /// The rows a layout names come first, in its order, and the others keep their own order after them.
    func testNamedRowsComeFirstAndTheOthersKeepTheirOrder() throws {
        let rows = ["claude-session", "claude-weekly", "claude-weekly-fable"]
        let unordered = try XCTUnwrap(block("Claude", in: PanelLayout()))
        XCTAssertEqual(unordered.rowOrder, [])
        XCTAssertEqual(unordered.ordered(rows) { $0 }, rows, "without an order, the rows' own")
        let ordered = try XCTUnwrap(block("Claude", in: claude(PanelLayout.Block(rows: ["claude-weekly-fable", "nope", "claude-session",
                                                                                         "claude-weekly-fable"]))))
        XCTAssertEqual(ordered.rowOrder, ["claude-weekly-fable", "claude-session"], "a row the block has not is passed over")
        XCTAssertEqual(ordered.ordered(rows) { $0 }, ["claude-weekly-fable", "claude-session", "claude-weekly"])
        XCTAssertEqual(ordered.ordered(["claude-weekly", "claude-session"]) { $0 }, ["claude-session", "claude-weekly"],
                       "each account's windows in that order, whichever it has")
        XCTAssertEqual(PanelLayout(blocks: ["Claude": PanelLayout.Block(rows: ["b", "", "a", "b"])]).normalized().blocks["Claude"]?.rows,
                       ["b", "a"], "each row once, where first named, in the order named")
    }

    func testAnOrderTheBlockHasAnywayIsLeftOut() {
        func reduced(_ rows: [String]) -> [String]? {
            claude(PanelLayout.Block(rows: rows)).reduced(against: blocks).blocks["Claude"]?.rows
        }
        XCTAssertNil(reduced(["claude-session", "claude-weekly", "claude-weekly-fable"]), "the rows' own order is no change")
        XCTAssertNil(reduced(["claude-session"]))
        XCTAssertEqual(reduced(["claude-weekly", "claude-session", "claude-weekly-fable"]), ["claude-weekly"],
                       "the session after the week is where it comes anyway")
        XCTAssertEqual(reduced(["claude-weekly-fable", "claude-opus"]), ["claude-weekly-fable", "claude-opus"],
                       "a row that is away stays as written")
    }

    func testARowTheBlockDoesNotHaveIsAnIssue() {
        let issues = claude(PanelLayout.Block(rows: ["claude-weekly", "claude-opus"])).issues(against: blocks)
        XCTAssertEqual(issues, [PanelLayoutIssue(path: "blocks.Claude.rows[1]", message: "\"Claude\" has no row \"claude-opus\". Its rows: "
                                                 + "\"claude-session\", \"claude-weekly\", \"claude-weekly-fable\".")])
        let held = [claude(PanelLayout.Block(hiddenRows: ["claude-opus"]))]
        XCTAssertEqual(claude(PanelLayout.Block(rows: ["claude-opus"])).issues(against: blocks, holding: held), [],
                       "a row the layout holds hidden, away now, may come back in the order")
        XCTAssertEqual(PanelLayout(blocks: ["api:Moonshot": PanelLayout.Block(rows: ["x"])]).issues(against: blocks).map(\.message),
                       ["\"api:Moonshot\" has no row \"x\". It has no rows to order."])
    }

    // MARK: The accounts a block shows

    func testABlockShowsTheAccountsItsLayoutNames() throws {
        let every = try XCTUnwrap(block("Claude", in: PanelLayout()))
        XCTAssertTrue(every.shows(account: "account:personal"))
        XCTAssertTrue(every.shows(account: ""), "without a filter, rows of no account too")
        let work = try XCTUnwrap(block("Claude", in: claude(PanelLayout.Block(accounts: ["account:work"]))))
        XCTAssertEqual(work.accounts, ["account:work"])
        XCTAssertTrue(work.shows(account: "account:work"))
        XCTAssertFalse(work.shows(account: "account:personal"))
        XCTAssertFalse(work.shows(account: ""), "a filter leaves out the rows of no account, which no id names")
        let first = try XCTUnwrap(block("api:Moonshot",
                                        in: PanelLayout(blocks: ["api:Moonshot": PanelLayout.Block(accounts: ["pool:first"])])))
        XCTAssertFalse(first.shows(account: "pool:second"), "a balance block chooses among its API accounts alike")
    }

    /// A block whose accounts keep none it has now, or whose rows of those it keeps are all hidden, is left out, as a
    /// block with every row hidden is.
    func testABlockWhoseAccountsKeepNothingIsLeftOut() {
        XCTAssertNil(block("Claude", in: claude(PanelLayout.Block(accounts: ["account:away"]))))
        XCTAssertNil(block("Claude", in: claude(PanelLayout.Block(hiddenRows: ["claude-session", "claude-weekly"],
                                                                  accounts: ["account:work"]))),
                     "Work's two windows are hidden, and Fable's is Personal's")
        XCTAssertNotNil(block("Claude", in: claude(PanelLayout.Block(hiddenRows: ["claude-session", "claude-weekly"]))),
                        "every account keeps Personal's Fable week")
        XCTAssertNil(block("Codex", in: PanelLayout(blocks: ["Codex": PanelLayout.Block(accounts: ["account:any"])])))
        XCTAssertNil(block("api:Moonshot", in: PanelLayout(blocks: ["api:Moonshot": PanelLayout.Block(accounts: ["pool:third"])])))
        XCTAssertNotNil(block("api:Moonshot", in: PanelLayout(blocks: ["api:Moonshot": PanelLayout.Block(accounts: ["pool:second"])])))
    }

    func testAccountsAreAFilterAndEveryAccountIsNoChange() {
        XCTAssertEqual(claude(PanelLayout.Block(accounts: ["b", "", "a", "b"])).normalized().blocks["Claude"]?.accounts, ["a", "b"],
                       "each once, in id order, since a filter has no order")
        func reduced(_ key: String, _ accounts: [String]) -> [String]? {
            PanelLayout(blocks: [key: PanelLayout.Block(accounts: accounts)]).reduced(against: blocks).blocks[key]?.accounts
        }
        XCTAssertNil(reduced("Claude", ["account:work", "account:personal"]), "every account the block has is every account")
        XCTAssertNil(reduced("Claude", ["account:work", "account:personal", "account:away"]))
        XCTAssertEqual(reduced("Claude", ["account:work"]), ["account:work"])
        XCTAssertEqual(reduced("Codex", ["account:away"]), ["account:away"], "rows of no account leave a filter something to change")
        XCTAssertNil(reduced("api:Moonshot", ["pool:first", "pool:second"]))
    }

    func testAnAccountTheBlockDoesNotHaveIsAnIssueThatNamesItsAccounts() {
        let issues = claude(PanelLayout.Block(accounts: ["account:work", "account:other", ""])).issues(against: blocks)
        let accounts = "Its accounts: \"account:personal\" (Personal), \"account:work\" (jazzen@work.example)."
        XCTAssertEqual(issues, [
            PanelLayoutIssue(path: "blocks.Claude.accounts[1]", message: "\"Claude\" has no account \"account:other\". \(accounts)"),
            PanelLayoutIssue(path: "blocks.Claude.accounts[2]", message: "\"Claude\" has no account \"\". \(accounts)"),
        ])
        XCTAssertEqual(PanelLayout(blocks: ["Codex": PanelLayout.Block(accounts: [""])]).issues(against: blocks).map(\.message),
                       ["\"Codex\" has no account \"\". It has no account to choose now."], "rows of no account are not one")
        let held = [claude(PanelLayout.Block(accounts: ["account:other"]))]
        XCTAssertEqual(claude(PanelLayout.Block(accounts: ["account:other"])).issues(against: blocks, holding: held), [],
                       "an account the layout holds, away now, may come back")
    }

    // MARK: Countdowns

    /// A quota block shows its reset times as its own countdown says, else as the layout's; a balance has none.
    func testABlocksCountdownOverridesTheLayouts() throws {
        XCTAssertEqual(try XCTUnwrap(block("Claude", in: PanelLayout())).countdown, true)
        XCTAssertEqual(try XCTUnwrap(block("Claude", in: PanelLayout(countdown: false))).countdown, false)
        let shown = PanelLayout(blocks: ["Claude": PanelLayout.Block(countdown: true)], countdown: false)
        XCTAssertEqual(try XCTUnwrap(block("Claude", in: shown)).countdown, true)
        XCTAssertEqual(try XCTUnwrap(block("Codex", in: shown)).countdown, false)
        XCTAssertEqual(try XCTUnwrap(block("api:Moonshot", in: shown)).countdown, true, "a balance has no countdown to hide")
        XCTAssertNil(PanelLayout(blocks: ["Claude": PanelLayout.Block(countdown: false)], countdown: false).reduced(against: blocks)
            .blocks["Claude"], "a block's countdown that is the layout's changes nothing")
        XCTAssertEqual(shown.reduced(against: blocks), shown)
        XCTAssertEqual(PanelLayout(blocks: ["api:Moonshot": PanelLayout.Block(countdown: true)]).issues(against: blocks).map(\.path),
                       ["blocks.api:Moonshot.countdown"])
    }
}
