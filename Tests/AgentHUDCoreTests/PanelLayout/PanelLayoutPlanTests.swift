import XCTest
@testable import AgentHUDCore

/// What the hover panel shows under a layout, against the blocks it has.
final class PanelLayoutPlanTests: XCTestCase {
    /// Three quota blocks and a balance, in default order.
    private let blocks = [
        PanelBlockInfo(key: "Claude", kind: .quota, rowKeys: ["claude-session", "claude-weekly"]),
        PanelBlockInfo(key: "Codex", kind: .quota, rowKeys: ["codex"]),
        PanelBlockInfo(key: "Cursor", kind: .quota, rowKeys: []),
        PanelBlockInfo(key: "api:DeepSeek", kind: .billing),
    ]

    private func plan(_ layout: PanelLayout) -> PanelLayoutPlan { PanelLayoutPlan(layout: layout, blocks: blocks) }

    private func block(_ key: String, in layout: PanelLayout) -> PanelBlockPlan? {
        plan(layout).blocks.first { $0.key == key }
    }

    private let everyMeasure: [PanelMeasure] = [.quota, .burnRate, .tokens, .cost]

    func testTheDefaultLayoutIsTheDefaultView() {
        let planned = plan(PanelLayout())
        XCTAssertEqual(planned.blocks, [
            PanelBlockPlan(key: "Claude", kind: .quota, widget: .bar, measure: .quota, measures: everyMeasure),
            PanelBlockPlan(key: "Codex", kind: .quota, widget: .bar, measure: .quota, measures: everyMeasure),
            PanelBlockPlan(key: "Cursor", kind: .quota, widget: .bar, measure: .quota, measures: everyMeasure),
            PanelBlockPlan(key: "api:DeepSeek", kind: .billing, widget: .number, measure: .quota, measures: [.quota]),
        ])
        XCTAssertEqual(planned.sections, [.blocks, .tokens, .sessions])
        XCTAssertEqual(planned.blocks.map(\.id), blocks.map(\.key))
        XCTAssertEqual(planned, PanelLayoutPlan(layout: PanelLayout(blocks: ["Claude": PanelLayout.Block()], order: [""]), blocks: blocks),
                       "a layout that normalizes to the default plans as the default")
        XCTAssertEqual(PanelLayoutPlan(layout: PanelLayout(), blocks: []).blocks, [])
    }

    func testNamedBlocksComeFirstInTheOrderNamedAndTheOthersFollowInDefaultOrder() {
        XCTAssertEqual(plan(PanelLayout(order: ["api:DeepSeek", "Codex"])).blocks.map(\.key), ["api:DeepSeek", "Codex", "Claude", "Cursor"])
        XCTAssertEqual(plan(PanelLayout(order: ["Cursor", "Claude", "Cursor", "Codex", "Claude"])).blocks.map(\.key),
                       ["Cursor", "Claude", "Codex", "api:DeepSeek"], "a key named twice counts where it is named first")
        XCTAssertEqual(plan(PanelLayout(order: ["Codex"])).blocks.map(\.key), ["Codex", "Claude", "Cursor", "api:DeepSeek"])
    }

    func testEntriesThatNameNoBlockArePassedOverAndStayInTheDocument() {
        let layout = PanelLayout(blocks: ["Grok": PanelLayout.Block(widget: .ring, hidden: true)], order: ["Grok", "Codex", "Kimi"])
        XCTAssertEqual(plan(layout).blocks.map(\.key), ["Codex", "Claude", "Cursor", "api:DeepSeek"])
        XCTAssertEqual(layout.normalized(), layout, "nothing about a block that is away is dropped")
        // The block returns, and what the layout says about it applies again.
        let returned = blocks + [PanelBlockInfo(key: "Grok", kind: .quota, rowKeys: ["grok"]), PanelBlockInfo(key: "Kimi", kind: .quota)]
        XCTAssertEqual(PanelLayoutPlan(layout: layout, blocks: returned).blocks.map(\.key), ["Codex", "Kimi", "Claude", "Cursor", "api:DeepSeek"])
        let shown = PanelLayout(blocks: ["Grok": PanelLayout.Block(widget: .ring)], order: ["Grok"])
        XCTAssertEqual(PanelLayoutPlan(layout: shown, blocks: returned).blocks.first,
                       PanelBlockPlan(key: "Grok", kind: .quota, widget: .ring, measure: .quota, measures: everyMeasure))
    }

    func testAHiddenBlockIsLeftOut() {
        let layout = PanelLayout(blocks: ["Codex": PanelLayout.Block(hidden: true), "api:DeepSeek": PanelLayout.Block(hidden: true)],
                                 order: ["Codex"])
        XCTAssertEqual(plan(layout).blocks.map(\.key), ["Claude", "Cursor"])
    }

    func testABlockWithEveryRowHiddenIsLeftOutAndOneWithoutRowsIsNot() {
        XCTAssertNil(block("Claude", in: PanelLayout(blocks: ["Claude": PanelLayout.Block(hiddenRows: ["claude-weekly", "claude-session"])])))
        XCTAssertNil(block("Codex", in: PanelLayout(blocks: ["Codex": PanelLayout.Block(hiddenRows: ["codex", "codex", "gone"])])))
        XCTAssertEqual(block("Claude", in: PanelLayout(blocks: ["Claude": PanelLayout.Block(hiddenRows: ["claude-weekly", "gone"])]))?.hiddenRows,
                       ["claude-weekly"], "a row the block does not have hides nothing")
        // No row keys: nothing covers them, whatever is named.
        XCTAssertEqual(block("Cursor", in: PanelLayout(blocks: ["Cursor": PanelLayout.Block(hiddenRows: ["cursor"])]))?.hiddenRows, [])
        XCTAssertEqual(block("api:DeepSeek", in: PanelLayout(blocks: ["api:DeepSeek": PanelLayout.Block(hiddenRows: ["CNY"])]))?.hiddenRows, [])
        XCTAssertEqual(block("Cursor", in: PanelLayout(blocks: ["Cursor": PanelLayout.Block(hiddenRows: [])]))?.hiddenRows, [])
    }

    func testAWidgetItsKindDoesNotAcceptFallsBackToTheKindsDefault() {
        for widget in PanelWidget.allCases {
            let quota = block("Claude", in: PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: widget)]))
            XCTAssertEqual(quota?.widget, widget, "quota windows take \(widget)")
            let balance = block("api:DeepSeek", in: PanelLayout(blocks: ["api:DeepSeek": PanelLayout.Block(widget: widget)]))
            XCTAssertEqual(balance?.widget, .number, "a balance asked for \(widget) is a number: it has no ceiling")
            XCTAssertEqual(balance?.measures, [.quota])
        }
    }

    func testAMeasureTheWidgetDoesNotOfferFallsBackToTheWidgetsDefault() {
        let ofAChart: [PanelMeasure] = [.tokens, .cost]
        func expect(_ key: String, _ change: PanelLayout.Block, shows measure: PanelMeasure, among measures: [PanelMeasure],
                    line: UInt = #line) {
            let planned = block(key, in: PanelLayout(blocks: [key: change]))
            XCTAssertEqual(planned?.measure, measure, line: line)
            XCTAssertEqual(planned?.measures, measures, line: line)
        }
        expect("Claude", PanelLayout.Block(widget: .ring, measure: .cost), shows: .cost, among: everyMeasure)
        expect("Claude", PanelLayout.Block(measure: .burnRate), shows: .burnRate, among: everyMeasure)
        expect("Claude", PanelLayout.Block(widget: .chart), shows: .tokens, among: ofAChart)
        expect("Claude", PanelLayout.Block(widget: .chart, measure: .cost), shows: .cost, among: ofAChart)
        expect("Claude", PanelLayout.Block(widget: .chart, measure: .quota), shows: .tokens, among: ofAChart)
        expect("Claude", PanelLayout.Block(widget: .chart, measure: .burnRate), shows: .tokens, among: ofAChart)
        expect("api:DeepSeek", PanelLayout.Block(measure: .cost), shows: .quota, among: [.quota])
        // The widget falls back first, and the measure is weighed under the widget that results.
        expect("api:DeepSeek", PanelLayout.Block(widget: .chart, measure: .tokens), shows: .quota, among: [.quota])
    }

    func testEveryPlannedMeasureIsOneItsWidgetOffers() {
        var widgets: [PanelWidget?] = [nil]
        widgets.append(contentsOf: PanelWidget.allCases)
        var measures: [PanelMeasure?] = [nil]
        measures.append(contentsOf: PanelMeasure.allCases)
        for widget in widgets {
            for measure in measures {
                let change = PanelLayout.Block(widget: widget, measure: measure)
                for planned in plan(PanelLayout(blocks: ["Claude": change, "api:DeepSeek": change])).blocks {
                    XCTAssertTrue(planned.kind.widgets.contains(planned.widget), "\(planned)")
                    XCTAssertEqual(planned.measures, planned.kind.measures(under: planned.widget), "\(planned)")
                    XCTAssertTrue(planned.measures.contains(planned.measure), "\(planned)")
                }
            }
        }
    }

    func testSectionsFollowTheSameOrderRuleWithoutTheHiddenOnes() {
        XCTAssertEqual(plan(PanelLayout(sections: [.sessions])).sections, [.sessions, .blocks, .tokens])
        XCTAssertEqual(plan(PanelLayout(sections: [.tokens, .sessions, .tokens, .blocks])).sections, [.tokens, .sessions, .blocks])
        XCTAssertEqual(plan(PanelLayout(hiddenSections: [.tokens])).sections, [.blocks, .sessions])
        XCTAssertEqual(plan(PanelLayout(sections: [.sessions, .tokens], hiddenSections: [.sessions, .sessions])).sections, [.tokens, .blocks],
                       "a hidden section is left out wherever it is named")
        XCTAssertEqual(plan(PanelLayout(hiddenSections: PanelSection.allCases)).sections, [])
        XCTAssertEqual(plan(PanelLayout(hiddenSections: [.blocks])).blocks.count, 4,
                       "hiding the section says nothing about its blocks, which a reader of the plan then does not draw")
    }

    func testABlockListedTwiceIsPlannedOnce() {
        let twice = blocks + [PanelBlockInfo(key: "Claude", kind: .quota, rowKeys: ["other"])]
        let planned = PanelLayoutPlan(layout: PanelLayout(blocks: ["Claude": PanelLayout.Block(hiddenRows: ["claude-session"])]), blocks: twice)
        XCTAssertEqual(planned.blocks.map(\.key), ["Claude", "Codex", "Cursor", "api:DeepSeek"])
        XCTAssertEqual(planned.blocks.first?.hiddenRows, ["claude-session"])
    }

    func testTheDemosViewPlansAsItsDefault() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = DemoUsageProvider.report(agents: DemoData.agents, historyHours: 24, now: now, stage: nil)
        let view = ReportView(report: report, agents: DemoData.agents, settings: Settings(), now: now)
        let plan = PanelLayoutPlan(layout: PanelLayout(), blocks: view.panelBlocks)
        XCTAssertEqual(plan.blocks.map(\.key), ["Claude", "Codex", "api:DeepSeek"])
        XCTAssertEqual(plan.blocks.map(\.widget), [.bar, .bar, .number])
        let changed = PanelLayout(blocks: ["Codex": PanelLayout.Block(widget: .ring, hiddenRows: ["codex:spark:primary"])],
                                  order: ["api:DeepSeek"], hiddenSections: [.sessions])
        XCTAssertEqual(changed.issues(against: view.panelBlocks), [])
        let custom = PanelLayoutPlan(layout: changed, blocks: view.panelBlocks)
        XCTAssertEqual(custom.blocks.map(\.key), ["api:DeepSeek", "Claude", "Codex"])
        XCTAssertEqual(custom.blocks.last?.hiddenRows, ["codex:spark:primary"])
        XCTAssertEqual(custom.sections, [.blocks, .tokens])
    }
}
