import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

/// The hover panel under a layout: what a layout changes about the panel's natural height, which is what the island is
/// sized from, and what the cost measure reads.
@MainActor
final class PanelLayoutViewTests: XCTestCase {
    private var suite = ""
    private var settings: SettingsStore!
    private var store: UsageStore!

    override func setUp() async throws {
        _ = NSApplication.shared
        L10n.setLanguage(.en)
        suite = "app.agenthud.tests.panel-layout-view.\(UUID().uuidString)"
        settings = SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), defaultAgents: DemoData.agents)
        store = UsageStore(provider: DemoUsageProvider(), settings: settings, clock: { DemoClock.now })
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours, now: DemoClock.now))
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        L10n.setLanguage(.system)
    }

    private var layout: PanelLayoutStore { settings.panelLayout }
    private var quotaKeys: [String] { store.view.panelBlocks.filter { $0.kind == .quota }.map(\.key) }

    /// The panel's natural height, as the island measures it: a fresh view tree at the panel's width.
    private func height() -> CGFloat {
        NSHostingView(rootView: HoverPanelView(store: store, onOpenStats: {}).frame(width: IslandController.expandedWidth))
            .fittingSize.height
    }

    private func every(_ widget: PanelWidget, _ measure: PanelMeasure? = nil) -> PanelLayout {
        PanelLayout(blocks: Dictionary(uniqueKeysWithValues: quotaKeys.map { ($0, PanelLayout.Block(widget: widget, measure: measure)) }))
    }

    /// The saved layout becomes `layout`, whatever was saved before.
    private func keep(_ proposal: PanelLayout) {
        layout.propose(proposal)
        layout.save()
        XCTAssertFalse(layout.hasDraft)
    }

    func testTheSampleHasQuotaBlocksToArrange() {
        XCTAssertGreaterThanOrEqual(quotaKeys.count, 2)
        XCTAssertGreaterThan(height(), 200)
    }

    /// The picker flips a block's measure in place and the island is sized from the measure shown first, so a widget
    /// must be as tall in every measure it offers.
    func testAWidgetIsAsTallInEveryMeasure() {
        for widget in PanelBlockKind.quota.widgets {
            let heights = PanelBlockKind.quota.measures(under: widget).map { measure -> CGFloat in
                keep(every(widget, measure))
                return height()
            }
            XCTAssertEqual(heights.max() ?? 0, heights.min() ?? 1, accuracy: 0.5, "\(widget) \(heights)")
        }
    }

    func testTheDefaultLayoutIsTheBarsAndAResetReturnsToIt() {
        let bars = height()
        keep(every(.bar))
        XCTAssertEqual(height(), bars, accuracy: 0.5, "bars are the default view of a quota block")
        keep(every(.number, .cost))
        XCTAssertFalse(layout.current.isDefault)
        layout.reset()
        XCTAssertEqual(height(), bars, accuracy: 0.5)
        XCTAssertTrue(layout.canRevert)
    }

    func testHidingABlockARowOrASectionShortensThePanelAndOrderDoesNot() throws {
        let full = height()
        let first = try XCTUnwrap(quotaKeys.first), last = try XCTUnwrap(quotaKeys.last)
        keep(PanelLayout(order: [last]))
        XCTAssertEqual(height(), full, accuracy: 0.5, "another order is the same blocks")

        keep(PanelLayout(blocks: [first: PanelLayout.Block(hidden: true)]))
        let withoutBlock = height()
        XCTAssertLessThan(withoutBlock, full - 20)

        let rows = try XCTUnwrap(store.view.panelBlocks.first { $0.key == first }).rowKeys
        XCTAssertGreaterThan(rows.count, 1)
        keep(PanelLayout(blocks: [first: PanelLayout.Block(hiddenRows: [rows[0]])]))
        let withoutRow = height()
        XCTAssertLessThan(withoutRow, full - 10)
        XCTAssertGreaterThan(withoutRow, withoutBlock)

        keep(PanelLayout(hiddenSections: [.tokens]))
        XCTAssertLessThan(height(), full - 20)
        keep(PanelLayout(hiddenSections: [.blocks, .tokens, .sessions]))
        XCTAssertLessThan(height(), 120, "only the footer is left")
    }

    /// The layout hides and orders what the Settings switches leave: a section a switch turned off stays off.
    func testASettingsSwitchStillDecidesWhatExists() {
        settings.update { $0.showIslandTokens = false }
        let withoutTokens = height()
        keep(PanelLayout(sections: [.tokens, .blocks, .sessions]))
        XCTAssertEqual(height(), withoutTokens, accuracy: 0.5)
    }

    /// An unsaved draft is drawn at once, with the bar that says so above the footer; saving or discarding it takes
    /// the bar away.
    func testADraftIsDrawnWithItsBarUntilItIsSavedOrDiscarded() throws {
        let bars = height()
        keep(every(.ring))
        let rings = height()
        layout.reset()
        XCTAssertEqual(height(), bars, accuracy: 0.5)

        XCTAssertTrue(layout.propose(every(.ring)))
        let draft = height()
        XCTAssertGreaterThan(draft, rings + 20, "the draft's rings and the bar that says it is unsaved")
        layout.discard()
        XCTAssertEqual(height(), bars, accuracy: 0.5)

        layout.propose(every(.ring))
        layout.save()
        XCTAssertEqual(height(), rings, accuracy: 0.5)
    }

    /// The cost measure of a window that counts a priced model is the list price of its cycle so far and the pace per
    /// hour; a row asks for it only while the measure is shown.
    func testTheCostMeasureReadsTheCyclesListPrice() throws {
        let row = try XCTUnwrap(store.rows.first { store.view.listCost(for: $0.id) != nil }, "the sample has a priced window")
        let cost = try XCTUnwrap(store.view.listCost(for: row.id))
        let currency = try XCTUnwrap(cost.currencies.first)
        let metrics = QuotaRowMetrics(row: row, insights: nil, outlook: nil, now: store.now, tokensPerHour: nil, cost: cost)
        XCTAssertEqual(metrics.value(.cost), MoneyFormat.short(try XCTUnwrap(cost.amounts[currency]), currency: currency))
        if cost.currencies.count == 1 {
            XCTAssertEqual(metrics.detail(.cost, isLoading: false),
                           MoneyFormat.short(try XCTUnwrap(cost.perHour(currency)), currency: currency) + "/h")
        }
        let without = QuotaRowMetrics(row: row, insights: nil, outlook: nil, now: store.now, tokensPerHour: nil)
        XCTAssertNil(without.value(.cost))
        XCTAssertEqual(without.detail(.cost, isLoading: false), "—")
    }

    func testEveryMeasureHasALabelAndASymbolForThePicker() {
        XCTAssertEqual(Set(PanelMeasure.allCases.map(\.symbol)).count, PanelMeasure.allCases.count)
        XCTAssertFalse(PanelMeasure.allCases.contains { $0.label.isEmpty })
    }
}
