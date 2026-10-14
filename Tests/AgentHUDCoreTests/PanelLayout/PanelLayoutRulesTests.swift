import XCTest
@testable import AgentHUDCore

/// What a block accepts, which blocks a report view has, and what a proposed layout is told about itself.
final class PanelLayoutRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Two quota blocks and a balance, as `ReportView.panelBlocks` lists them.
    private let blocks = [
        PanelBlockInfo(key: "Claude", kind: .quota, rowKeys: ["claude-session", "claude-weekly"]),
        PanelBlockInfo(key: "Codex", kind: .quota, rowKeys: ["codex"]),
        PanelBlockInfo(key: "api:DeepSeek", kind: .billing),
    ]

    override func setUp() {
        super.setUp()
        L10n.setLanguage(.en)
    }

    override func tearDown() {
        L10n.setLanguage(.system)
        super.tearDown()
    }

    // MARK: What a kind accepts

    func testQuotaWindowsTakeEveryWidgetAndABalanceOnlyANumber() {
        XCTAssertEqual(PanelBlockKind.quota.widgets, [.bar, .ring, .number, .chart])
        XCTAssertEqual(PanelBlockKind.billing.widgets, [.number], "a balance has no ceiling for a bar or a ring to fill")
        XCTAssertEqual(PanelBlockKind.quota.defaultWidget, .bar)
        XCTAssertEqual(PanelBlockKind.billing.defaultWidget, .number)
        XCTAssertEqual(Set(PanelBlockKind.quota.widgets), Set(PanelWidget.allCases))
    }

    func testTheMeasuresOfferedFollowTheKindAndTheWidget() {
        for widget in [PanelWidget.bar, .ring, .number] {
            XCTAssertEqual(PanelBlockKind.quota.measures(under: widget), [.quota, .burnRate, .tokens, .cost], "\(widget)")
        }
        XCTAssertEqual(PanelBlockKind.quota.measures(under: .chart), [.tokens, .cost])
        XCTAssertEqual(PanelBlockKind.billing.measures(under: .number), [.quota])
        for widget in [PanelWidget.bar, .ring, .chart] {
            XCTAssertEqual(PanelBlockKind.billing.measures(under: widget), [], "\(widget) is not a balance's widget")
        }
    }

    func testTheDefaultMeasureIsTheFirstOneOffered() {
        XCTAssertEqual(PanelBlockKind.quota.defaultMeasure(under: .bar), .quota)
        XCTAssertEqual(PanelBlockKind.quota.defaultMeasure(under: .chart), .tokens)
        XCTAssertEqual(PanelBlockKind.billing.defaultMeasure(under: .number), .quota)
        for kind in [PanelBlockKind.quota, .billing] {
            for widget in kind.widgets {
                XCTAssertEqual(kind.defaultMeasure(under: widget), kind.measures(under: widget).first, "\(kind) \(widget)")
            }
        }
    }

    func testWhatAKindDoesNotAcceptFallsBackToItsDefault() {
        XCTAssertEqual(PanelBlockKind.quota.widget(for: .ring), .ring)
        XCTAssertEqual(PanelBlockKind.quota.widget(for: nil), .bar)
        XCTAssertEqual(PanelBlockKind.billing.widget(for: .ring), .number)
        XCTAssertEqual(PanelBlockKind.quota.measure(for: .cost, under: .ring), .cost)
        XCTAssertEqual(PanelBlockKind.quota.measure(for: .quota, under: .chart), .tokens)
        XCTAssertEqual(PanelBlockKind.quota.measure(for: nil, under: .number), .quota)
        XCTAssertEqual(PanelBlockKind.billing.measure(for: .cost, under: .number), .quota)
    }

    // MARK: The blocks of a view

    func testTheDemoHasABlockForEachAccountsWindowsAndOneForItsBalance() {
        let report = DemoUsageProvider.report(agents: DemoData.agents, historyHours: 24, now: now, stage: nil)
        let view = ReportView(report: report, agents: DemoData.agents, settings: Settings(), now: now)
        XCTAssertEqual(view.panelBlocks, [
            PanelBlockInfo(key: "Claude", kind: .quota, rowKeys: ["claude-session", "claude-weekly", "claude-weekly-fable"]),
            PanelBlockInfo(key: "Codex", kind: .quota, rowKeys: ["codex", "codex:spark:primary", "codex:spark:secondary"]),
            PanelBlockInfo(key: "api:DeepSeek", kind: .billing, rowKeys: []),
        ])
        XCTAssertEqual(view.panelBlocks.filter { $0.kind == .quota }.map(\.key), view.rowGroups.map(\.vendor))
    }

    /// Two accounts of one vendor share a window, one row is switched off, and two API accounts are billed by one provider.
    func testAWindowIsOneRowHoweverManyAccountsHaveItAndAccountsOfOneProviderShareABlock() {
        let accounts = ["one@example.com", "two@example.com"].map {
            ProviderAccount.identified(provider: "Codex", user: $0, workspace: nil)!
        }
        let pools = ["first", "second"].map {
            BillingPool(provider: "Moonshot", realm: "CN", product: .api, scope: $0, evidence: .credential, entitlement: "api")
        }
        func window(_ account: ProviderAccount, _ key: String) -> AgentDescriptor {
            AgentDescriptor(id: account.windowID(key), vendor: "Codex", model: key, source: "", enabled: true, account: account)
        }
        let agents = [
            window(accounts[0], "codex"), window(accounts[0], "codex:spark"), window(accounts[1], "codex"),
            AgentDescriptor(id: "claude-session", vendor: "Claude", model: "5h", source: "", enabled: true),
            AgentDescriptor(id: "claude-weekly", vendor: "Claude", model: "Weekly", source: "", enabled: false),
            AgentDescriptor(id: "deepseek", vendor: "DeepSeek", model: "API", source: "", enabled: true),
        ] + pools.map {
            AgentDescriptor(id: $0.windowID("kimi-k3"), vendor: "Kimi", model: "K3", source: "", enabled: true, billingPool: $0)
        }
        func balance(_ vendor: String, pool: BillingPool? = nil) -> APIBilling {
            APIBilling(vendor: vendor, balances: [AccountBalance(currency: "CNY", total: 20, granted: 0, toppedUp: 20)],
                       isAvailable: true, updatedAt: now, notice: nil, billingPool: pool)
        }
        let report = UsageReport(generatedAt: now, snapshots: [], sessions: [],
                                 billing: [balance("Kimi", pool: pools[0]), balance("DeepSeek"), balance("Kimi", pool: pools[1])])
        let view = ReportView(report: report, agents: agents, settings: Settings(), now: now)

        XCTAssertEqual(view.billing.count, 3)
        XCTAssertEqual(view.billing.map(\.panelBlockKey), ["api:Moonshot", "api:DeepSeek", "api:Moonshot"],
                       "a pool's balance is keyed by the provider that bills it, any other by its vendor")
        XCTAssertEqual(view.panelBlocks, [
            PanelBlockInfo(key: "Codex", kind: .quota, rowKeys: ["codex", "codex:spark"]),
            PanelBlockInfo(key: "Claude", kind: .quota, rowKeys: ["claude-session"]),
            PanelBlockInfo(key: "api:Moonshot", kind: .billing),
            PanelBlockInfo(key: "api:DeepSeek", kind: .billing),
        ])
        XCTAssertEqual(ReportView(report: nil, agents: agents, settings: Settings(), now: now).panelBlocks.map(\.key), ["Codex", "Claude"],
                       "before any report there are rows and no balances")
        XCTAssertEqual(ReportView(report: report, agents: [], settings: Settings(), now: now).panelBlocks, [])
    }

    // MARK: What a proposed layout is told

    func testALayoutThePanelCanDoAsAskedHasNoIssues() {
        XCTAssertEqual(PanelLayout().issues(against: blocks), [])
        let layout = PanelLayout(blocks: [
            "Claude": PanelLayout.Block(widget: .ring, measure: .burnRate, hiddenRows: ["claude-weekly"]),
            "Codex": PanelLayout.Block(widget: .chart, measure: .cost, hidden: true),
            "api:DeepSeek": PanelLayout.Block(widget: .number, measure: .quota),
        ], order: ["api:DeepSeek", "Codex", "Codex"], sections: [.sessions], hiddenSections: [.tokens])
        XCTAssertEqual(layout.issues(against: blocks), [])
    }

    func testABlockKeyOrOrderEntryThatNamesNoBlockListsTheBlocksThereAre() {
        let layout = PanelLayout(blocks: ["Cursor": PanelLayout.Block(widget: .ring)], order: ["Claude", "claude", "Cursor"])
        func unknown(_ key: String) -> String {
            "No block has the key \"\(key)\". The panel's blocks now: \"Claude\", \"Codex\", \"api:DeepSeek\"."
        }
        XCTAssertEqual(layout.issues(against: blocks), [
            PanelLayoutIssue(path: "blocks.Cursor", message: unknown("Cursor")),
            PanelLayoutIssue(path: "order[1]", message: unknown("claude")),
            PanelLayoutIssue(path: "order[2]", message: unknown("Cursor")),
        ])
        XCTAssertEqual(PanelLayout(order: ["Claude"]).issues(against: []), [
            PanelLayoutIssue(path: "order[0]", message: #"No block has the key "Claude". The panel has no blocks now."#),
        ])
    }

    func testAWidgetABalanceCannotTakeSaysWhyAndWhatItAccepts() {
        func issues(_ widget: PanelWidget) -> [PanelLayoutIssue] {
            PanelLayout(blocks: ["api:DeepSeek": PanelLayout.Block(widget: widget)]).issues(against: blocks)
        }
        func noCeiling(_ widget: String) -> String {
            "\"api:DeepSeek\" is an API balance, which has no ceiling, so the \"\(widget)\" widget has nothing to measure it against."
                + " It accepts: \"number\"."
        }
        XCTAssertEqual(issues(.number), [])
        XCTAssertEqual(issues(.ring), [PanelLayoutIssue(path: "blocks.api:DeepSeek.widget", message: noCeiling("ring"))])
        XCTAssertEqual(issues(.bar).map(\.message), [noCeiling("bar")])
        XCTAssertEqual(issues(.chart).map(\.message), [
            #""api:DeepSeek" is an API balance, and a chart of money is not drawn yet. It accepts: "number"."#,
        ])
        for widget in PanelWidget.allCases {
            XCTAssertEqual(PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: widget)]).issues(against: blocks), [], "\(widget)")
        }
    }

    func testAMeasureIsCheckedUnderTheWidgetTheBlockIsDrawnWith() {
        func issues(_ key: String, _ block: PanelLayout.Block) -> [PanelLayoutIssue] {
            PanelLayout(blocks: [key: block]).issues(against: blocks)
        }
        XCTAssertEqual(issues("Claude", PanelLayout.Block(widget: .chart, measure: .burnRate)), [
            PanelLayoutIssue(path: "blocks.Claude.measure", message:
                #"The "chart" widget of "Claude" does not offer the measure "burn". It offers: "tokens", "cost"."#),
        ])
        XCTAssertEqual(issues("Claude", PanelLayout.Block(widget: .chart, measure: .tokens)), [])
        XCTAssertEqual(issues("Claude", PanelLayout.Block(measure: .cost)), [], "without a widget the default one decides")
        let together = [
            #"The "number" widget of "api:DeepSeek" does not offer the measure "cost"."#,
            #" An API balance shows its balance and its estimated cost together, as "quota". It offers: "quota"."#,
        ].joined()
        XCTAssertEqual(issues("api:DeepSeek", PanelLayout.Block(measure: .cost)), [
            PanelLayoutIssue(path: "blocks.api:DeepSeek.measure", message: together),
        ])
        // A widget the block cannot take is drawn as its default, and the measure is weighed under that one.
        XCTAssertEqual(issues("api:DeepSeek", PanelLayout.Block(widget: .ring, measure: .burnRate)).map(\.path),
                       ["blocks.api:DeepSeek.widget", "blocks.api:DeepSeek.measure"])
        XCTAssertEqual(issues("api:DeepSeek", PanelLayout.Block(widget: .ring, measure: .quota)).map(\.path), ["blocks.api:DeepSeek.widget"])
    }

    func testAHiddenRowTheBlockDoesNotHaveListsItsRows() {
        let layout = PanelLayout(blocks: [
            "Claude": PanelLayout.Block(hiddenRows: ["claude-weekly", "codex", "weekly"]),
            "api:DeepSeek": PanelLayout.Block(hiddenRows: ["CNY"]),
        ])
        func noRow(_ row: String) -> String {
            "\"Claude\" has no row \"\(row)\". Its rows: \"claude-session\", \"claude-weekly\"."
        }
        XCTAssertEqual(layout.issues(against: blocks), [
            PanelLayoutIssue(path: "blocks.Claude.hiddenRows[1]", message: noRow("codex")),
            PanelLayoutIssue(path: "blocks.Claude.hiddenRows[2]", message: noRow("weekly")),
            PanelLayoutIssue(path: "blocks.api:DeepSeek.hiddenRows[0]",
                             message: #""api:DeepSeek" has no row "CNY". It has no rows to hide."#),
        ])
    }

    func testIssuesComeBlockByBlockInKeyOrderThenTheOrderList() {
        let layout = PanelLayout(blocks: [
            "api:DeepSeek": PanelLayout.Block(widget: .bar, measure: .tokens, hiddenRows: ["x"]),
            "Zed": PanelLayout.Block(hidden: true),
            "Claude": PanelLayout.Block(widget: .chart, measure: .quota, hiddenRows: ["x"]),
        ], order: ["Zed"])
        XCTAssertEqual(layout.issues(against: blocks).map(\.path), [
            "blocks.Claude.measure", "blocks.Claude.hiddenRows[0]", "blocks.Zed",
            "blocks.api:DeepSeek.widget", "blocks.api:DeepSeek.measure", "blocks.api:DeepSeek.hiddenRows[0]", "order[0]",
        ])
        // A layout with issues still resolves: what cannot be done as asked falls back or waits.
        XCTAssertEqual(PanelLayoutPlan(layout: layout, blocks: blocks).blocks.map(\.key), ["Claude", "Codex", "api:DeepSeek"])
    }
}
