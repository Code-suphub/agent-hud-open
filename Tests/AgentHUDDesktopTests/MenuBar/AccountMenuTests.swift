import AppKit
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

final class AccountMenuTests: XCTestCase {
    @MainActor
    func testHostItemsAreDrawnFromTheirOwnFieldsWithoutBeingChanged() throws {
        let suite = "AccountMenuTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: [])
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        let target = NSResponder()
        let update = NSMenuItem(title: "New Version…", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "u")
        update.target = target
        update.isEnabled = false
        let custom = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        custom.view = view
        let separator = NSMenuItem.separator()
        let controller = StatusItemController(store: store, settings: settings, additionalMenuItems: { [update, separator, custom] })
        let entries = controller.menuEntries()
        let host = try XCTUnwrap(entries.first { $0.title == "New Version…" })
        XCTAssertEqual(host.value, "⌘U")
        XCTAssertFalse(host.isEnabled)
        XCTAssertFalse(host.isSelectable, "a disabled host item is drawn but cannot be chosen")
        XCTAssertEqual(entries.suffix(5).map(\.kind), [.item, .item, .separator, .item, .item])
        XCTAssertEqual(entries.suffix(2).first?.title, "Custom", "a custom view is drawn from its item's title")
        XCTAssertNil(update.view)
        XCTAssertTrue(update.target === target)
        XCTAssertEqual(update.action, #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(update.keyEquivalent, "u")
        XCTAssertFalse(update.isEnabled)
        XCTAssertTrue(custom.view === view)
        XCTAssertNil(separator.view)
    }

    @MainActor
    func testHostMenuItemsAreRebuiltWithTheirEnabledStateBetweenSettingsAndQuit() throws {
        let suite = "AccountMenuTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); L10n.setLanguage(.system) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: [])
        settings.update { $0.language = .en }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        var available = false
        let controller = StatusItemController(store: store, settings: settings, additionalMenuItems: {
            let item = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
            item.isEnabled = available
            return [item]
        })
        var entries = controller.menuEntries()
        XCTAssertEqual(entries.suffix(3).map(\.title), ["Settings…", "Check for Updates…", "Quit"])
        XCTAssertFalse(entries[entries.count - 2].isEnabled)
        available = true
        entries = controller.menuEntries()
        XCTAssertTrue(entries[entries.count - 2].isEnabled)
        XCTAssertEqual(entries.filter { $0.title == "Check for Updates…" }.count, 1)
    }

    @MainActor
    func testPiCodexAccountAppearsOnceUnderItsSubscriptionProvider() throws {
        let suite = "AccountMenuTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); L10n.setLanguage(.system) }
        let now = Date()
        let account = try XCTUnwrap(ProviderAccount.identified(provider: "Codex", user: "shared@example.com", workspace: "workspace"))
        let agents = ["5h", "Weekly"].map {
            AgentDescriptor(id: account.windowID($0), vendor: "Codex", model: $0, source: "", enabled: true, account: account)
        }
        let settings = SettingsStore(defaults: defaults, defaultAgents: agents)
        settings.update { $0.language = .en }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        store.replace(report: UsageReport(generatedAt: now, snapshots: agents.map {
            .init(agentId: $0.id, remainingPct: 60, updatedAt: now)
        }, sessions: [], discoveredAgents: agents, accounts: ["Codex": [
            .init(account: account, home: "pi:alternate", client: "Pi", label: "shared@example.com", observedAt: now),
            .init(account: account, home: "", client: "Codex", label: "shared@example.com", observedAt: now, isCurrent: false)
        ]]))
        let entries = StatusItemController(store: store, settings: settings).menuEntries()
        XCTAssertEqual(Array(entries.prefix(4)).map(\.title), ["Codex", "shared@example.com", "5h", "Weekly"])
        XCTAssertEqual(entries.filter { $0.title == "shared@example.com" }.count, 1)
        XCTAssertEqual(entries.filter { $0.title == "Codex" }.count, 1)
        XCTAssertFalse(entries.contains { $0.title == "Pi" })
    }

    @MainActor
    func testMenuHidesFormerAccountsAndShowsTheCurrentPendingReading() throws {
        _ = NSApplication.shared
        let suite = "AccountMenuTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); L10n.setLanguage(.system) }
        let now = Date()
        let current = ProviderAccount.identified(provider: "Codex", user: "current@example.com", workspace: "a")!
        let old = ProviderAccount.identified(provider: "Codex", user: "old@example.com", workspace: "b")!
        let agents = [current, old].map {
            AgentDescriptor(id: $0.windowID("codex"), vendor: "Codex", model: "Weekly", source: "", enabled: true, account: $0)
        }
        let settings = SettingsStore(defaults: defaults, defaultAgents: agents)
        settings.update { $0.language = .en }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        store.replace(report: UsageReport(generatedAt: now, snapshots: agents.map {
            .init(agentId: $0.id, remainingPct: 0, resetAt: now.addingTimeInterval(-1), updatedAt: now)
        }, sessions: [], discoveredAgents: agents, accounts: ["Codex": [
            .init(account: current, label: "current@example.com", plan: "pro", observedAt: now),
            .init(account: old, label: "old@example.com", plan: "plus", observedAt: now.addingTimeInterval(-3600), isCurrent: false)
        ]]))
        let entries = StatusItemController(store: store, settings: settings).menuEntries()
        XCTAssertEqual(Array(entries.prefix(2)).map(\.title).map { $0.components(separatedBy: " · ")[0] },
                       ["current@example.com", "Weekly"])
        XCTAssertFalse(entries.contains { $0.title.hasPrefix("old@example.com") })
        XCTAssertTrue(entries[0].accessibilityLabel.contains("Current account"))
        XCTAssertTrue(entries[1].accessibilityLabel.contains("Pending update"))
        XCTAssertNil(store.rows[0].level, "a past deadline cannot show a confirmed exhaustion status")
        let future = UsageReport(generatedAt: now, snapshots: [.init(agentId: agents[0].id, remainingPct: 50,
            resetAt: now.addingTimeInterval(20), updatedAt: now)], sessions: [], discoveredAgents: [agents[0]])
        store.replace(report: future)
        XCTAssertEqual(store.rows[0].resetLabel(now: now), "<1m")
    }

    /// The menu bar figure counts only windows whose readings show a level, and only such a row has the hover hint as its
    /// tooltip. A header says its account is current only while its readings are sound, however old: the account's own
    /// failed read and its vendor's both make it say when it was last read. Its tooltip is what the island shows above the
    /// account: the account's reason, then its client's notices.
    @MainActor
    func testMenuFigureHeadersAndTooltipsFollowEachAccountsOwnReading() throws {
        let suite = "AccountMenuTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); L10n.setLanguage(.system) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let failed = try XCTUnwrap(ProviderAccount.identified(provider: "Codex", user: "failed@example.com", workspace: "a"))
        let stale = try XCTUnwrap(ProviderAccount.identified(provider: "Codex", user: "stale@example.com", workspace: "b"))
        let old = try XCTUnwrap(ProviderAccount.identified(provider: "Codex", user: "old@example.com", workspace: "c"))
        // Each window: its account and name, what is left, when it resets and was read, and when it runs out.
        let windows: [(account: ProviderAccount, model: String, remaining: Double, resetIn: TimeInterval?, readAgo: TimeInterval,
                       exhaustsIn: TimeInterval?)] = [
            (failed, "Weekly", 10, 20, 300, 3600),
            (failed, "Credits", 70, nil, 300, nil),
            (stale, "Weekly", 40, -60, 7200, nil),
            (stale, "5h", 20, 7530, 7200, nil),
            (old, "Weekly", 2, 3 * 3600, 3 * 3600, 7200),
        ]
        let agents = windows.map {
            AgentDescriptor(id: $0.account.windowID($0.model), vendor: "Codex", model: $0.model, source: "", enabled: true, account: $0.account)
        }
        let report = UsageReport(
            generatedAt: now,
            snapshots: zip(agents, windows).map { agent, window in
                .init(agentId: agent.id, remainingPct: window.remaining, resetAt: window.resetIn.map(now.addingTimeInterval),
                      windowDuration: window.model == "5h" ? 5 * 3600 : 7 * 86400, updatedAt: now.addingTimeInterval(-window.readAgo))
            },
            sessions: [], discoveredAgents: agents,
            insightsByAgent: Dictionary(uniqueKeysWithValues: zip(agents, windows).compactMap { agent, window in
                window.exhaustsIn.map { (agent.id, UsageInsights(burnRatePctPerHour: 10, timeToExhaust: $0, weeklyCapHits: 0,
                                                                 weeklyWaitTotal: 0, weeklyWaitLongest: 0, weeklyWaitLongestAt: nil)) }
            }),
            sourceNotices: ["Codex": "Codex login failed"], quotaNotices: ["Codex": "Codex login failed"],
            accounts: ["Codex": [
                .init(account: failed, label: "failed@example.com", observedAt: now.addingTimeInterval(-300), quotaNotice: "Quota read failed"),
                .init(account: stale, label: "stale@example.com", observedAt: now.addingTimeInterval(-7200)),
                .init(account: old, label: "old@example.com", observedAt: now.addingTimeInterval(-3 * 3600), isCurrent: false),
            ]])
        let (entries, store) = buildMenu(showing: report, agents: agents, now: now, defaults: defaults)

        XCTAssertNil(store.maxUsedPct, "no window counts: the account's or the vendor's failed read, a passed reset or a signed-out account holds each back")
        XCTAssertEqual(entries.prefix(7).map { [$0.accessibilityLabel, $0.toolTip ?? "—"] }, [
            ["Codex", "—"],
            ["failed@example.com, Last read 5m ago", "Quota read failed · Codex login failed"],
            ["Weekly, 90% · <1m", "—"],
            ["Credits, 30% · —", "—"],
            ["stale@example.com, Last read 2h ago", "Codex login failed"],
            ["Weekly, 60% · Pending update", "—"],
            ["5h, 80% · 2h05m", "—"],
        ])
        XCTAssertEqual(store.accountSections(store.rows).map { store.accountNotice(for: $0) },
                       ["Quota read failed · Codex login failed", "Codex login failed"],
                       "the island shows above each account what its menu header's tooltip says")
    }

    /// A balance's figure follows its level, as a quota row's does: red when the account is unavailable or its balance is
    /// at or below zero, and without a colour when its read failed, which its tooltip explains before the cost.
    @MainActor
    func testABalanceIsRedWhenItsLevelIsCritical() throws {
        let suite = "AccountMenuTests.\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); L10n.setLanguage(.system) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Each balance: its provider and amount, whether the service allows use, and a failed read's notice and age.
        let balances: [(provider: String, total: Decimal, isAvailable: Bool?, notice: String?, readAgo: TimeInterval)] = [
            ("DeepSeek", 50, false, nil, 0),
            ("Kimi", 0, true, nil, 0),
            ("GLM", -1, nil, nil, 0),
            ("OpenAI", 5, nil, "Balance could not be read", 7200),
        ]
        let pools = balances.map {
            BillingPool(provider: $0.provider, realm: "International", product: .api, scope: $0.provider, evidence: .credential, entitlement: "api")
        }
        let agents = pools.map {
            AgentDescriptor(id: $0.windowID("api"), vendor: $0.provider, model: "API", source: "", enabled: true, billingPool: $0)
        }
        let report = UsageReport(generatedAt: now, snapshots: [], sessions: [], discoveredAgents: agents,
                                 billing: zip(balances, pools).map { balance, pool in
            APIBilling(vendor: balance.provider, balances: [.init(currency: "USD", total: balance.total, granted: 0, toppedUp: 0)],
                       isAvailable: balance.isAvailable, updatedAt: now.addingTimeInterval(-balance.readAgo), notice: balance.notice,
                       billingPool: pool)
        })
        let (entries, store) = buildMenu(showing: report, agents: agents, now: now, defaults: defaults)

        let items = entries.filter { $0.title.hasSuffix(" · Balance") }
        XCTAssertEqual(items.map(\.accessibilityLabel), [
            "DeepSeek · API · Balance, $50.00", "Kimi · API · Balance, $0.00", "GLM · API · Balance, -$1.00", "OpenAI · API · Balance, $5.00",
        ])
        XCTAssertEqual(store.enabledBilling.map { store.view.level(of: $0) }, [.critical, .critical, .critical, nil])
        XCTAssertEqual(items.map { $0.toolTip?.hasPrefix("Balance could not be read\nEst. cost") }, [false, false, false, true])
        XCTAssertEqual(items.map(\.valueInk), [.critical, .critical, .critical, .secondary])
        XCTAssertEqual([StatusLevel.warning, .ok, nil].map { StatusItemController.valueInk($0) }, [.secondary, .secondary, .secondary])
    }

    /// A critical figure takes the critical text colour of the look the menu is drawn in, light or dark, which under
    /// Match screen is the HUD's look rather than macOS's; any other figure is the look's secondary ink.
    @MainActor
    func testAFiguresColourFollowsTheMenusLook() {
        for look in [HUDLook(appearance: .light), HUDLook(appearance: .dark, material: .glass)] {
            let theme = look.theme
            XCTAssertEqual(StatusMenuEntry.Ink.critical.color(in: theme), theme.statusText(.critical))
            XCTAssertEqual(StatusMenuEntry.Ink.secondary.color(in: theme), theme.secondary)
        }
        XCTAssertNotEqual(StatusMenuEntry.Ink.critical.color(in: HUDLook(appearance: .light).theme),
                          StatusMenuEntry.Ink.critical.color(in: HUDLook(appearance: .dark).theme))
    }

    /// The lines `StatusItemController` builds over `report` at `now`, in English, with the rows of `agents` shown.
    @MainActor
    private func buildMenu(showing report: UsageReport, agents: [AgentDescriptor], now: Date,
                           defaults: UserDefaults) -> (entries: [StatusMenuEntry], store: UsageStore) {
        _ = NSApplication.shared
        let settings = SettingsStore(defaults: defaults, defaultAgents: agents)
        settings.update { $0.language = .en }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        store.replace(report: report)
        store.now = now
        return (StatusItemController(store: store, settings: settings).menuEntries(), store)
    }
}
