import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

/// The hover panel under a layout's row order and account filter, over the sample with a second Claude account, Work,
/// signed in from another home with the session and the week, measured and drawn as the island measures the panel: a
/// fresh view tree at the panel's width.
@MainActor
final class PanelBlockRowsViewTests: XCTestCase {
    private static let work = ProviderAccount.identified(provider: "Claude", user: "demo-claude-work", workspace: nil)!

    private lazy var store: UsageStore = {
        _ = NSApplication.shared
        let suite = "app.agenthud.tests.panel-rows-view.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let work = PanelBlockRowsViewTests.work
        let workRows = DemoData.claudeRows.prefix(2).map {
            AgentDescriptor(id: work.windowID($0.windowKey), vendor: $0.vendor, model: $0.model, shortModel: $0.shortModel,
                            source: $0.source, enabled: true, account: work)
        }
        let agents = DemoData.claudeRows + workRows + DemoData.agents.filter { $0.vendor != "Claude" }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: agents)
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, clock: { DemoClock.now })
        let now = DemoClock.now
        let sample = DemoUsageProvider.report(agents: DemoData.agents, historyHours: UsageStore.historyHours, now: now, stage: nil)
        var accounts = sample.accounts ?? [:]
        accounts["Claude", default: []].append(AccountObservation(account: work, home: "work", label: "jazzen@work.example",
                                                                  plan: "pro", observedAt: now))
        let snapshots = workRows.map {
            UsageSnapshot(agentId: $0.id, remainingPct: 70, resetAt: now.addingTimeInterval(3600), updatedAt: now)
        }
        store.replace(report: UsageReport(generatedAt: now, snapshots: sample.snapshots + snapshots, sessions: sample.sessions,
                                          discoveredAgents: sample.discoveredAgents + workRows, consumers: sample.consumers,
                                          usage: sample.usage, insightsByAgent: sample.insightsByAgent,
                                          subscriptions: sample.subscriptions, consumerIdsByQuota: sample.consumerIdsByQuota,
                                          billing: sample.billing, accounts: accounts))
        // The blocks alone, so that what changes is theirs.
        settings.panelLayout.setSwitches { $0.tokenUsage = false; $0.sessionList = false }
        return store
    }()
    private var layout: PanelLayoutStore { store.settings.panelLayout }

    override func setUp() {
        super.setUp()
        L10n.setLanguage(.en)
    }

    override func tearDown() {
        L10n.setLanguage(.system)
        super.tearDown()
    }

    /// The saved layout becomes the blocks alone with `blocks` changed.
    private func keep(_ blocks: [String: PanelLayout.Block]) {
        layout.propose(PanelLayout(blocks: blocks, hiddenSections: [.tokens, .sessions]))
        layout.save()
    }

    private func hosted() -> NSHostingView<some View> {
        let view = NSHostingView(rootView: HoverPanelView(store: store, onOpenStats: {}).frame(width: IslandController.expandedWidth))
        view.frame.size = view.fittingSize
        return view
    }

    private func height() -> CGFloat { hosted().fittingSize.height }

    /// What the panel draws, pixel by pixel.
    private func pixels() -> Data? {
        let view = hosted()
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
    }

    /// A block's account filter draws the block as hiding the other account in Settings → Agents draws it.
    func testAnAccountFilterDrawsTheBlockWithTheAccountsItKeeps() {
        let both = height()
        keep(["Claude": PanelLayout.Block(accounts: [Self.work.id])])
        let work = height()
        XCTAssertLessThan(work, both - 40, "Personal's three windows and its heading are left out")
        keep([:])
        XCTAssertEqual(height(), both, accuracy: 0.5)
        store.settings.setAccount(id: DemoData.claudeAccount.id, visible: false)
        XCTAssertEqual(height(), work, accuracy: 0.5)
    }

    /// Another order of a block's rows is the same rows, as tall, drawn in another order; two spellings of one order
    /// draw the same.
    func testARowOrderMovesTheRowsAndKeepsTheirHeight() {
        let unordered = (height(), pixels())
        keep(["Claude": PanelLayout.Block(rows: ["claude-weekly-fable", "claude-weekly"])])
        let ordered = (height(), pixels())
        XCTAssertEqual(ordered.0, unordered.0, accuracy: 0.5)
        XCTAssertNotEqual(ordered.1, unordered.1)
        keep(["Claude": PanelLayout.Block(rows: ["claude-weekly-fable", "claude-weekly", "claude-session"])])
        XCTAssertEqual(pixels(), ordered.1, "the rows left out keep their order after the named ones")
        keep(["Claude": PanelLayout.Block(rows: ["claude-session", "claude-weekly"])])
        XCTAssertEqual(pixels(), unordered.1, "the rows' own order")
    }
}
