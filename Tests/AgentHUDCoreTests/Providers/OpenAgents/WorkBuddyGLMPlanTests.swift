import XCTest
@testable import AgentHUDCore

/// A GLM Coding Plan whose key WorkBuddy keeps in `~/.workbuddy/models.json`: which entries are read, the group its rows
/// are shown in, and what stays with GLM, its provider.
final class WorkBuddyGLMPlanTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_800_000)
    let chinaCoding = "https://open.bigmodel.cn/api/coding/paas/v4"

    func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    func write(_ value: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: file)
    }
    func models(_ entries: [(vendor: String, url: String, key: String)], in home: URL) throws {
        let list = entries.map { #"{"id":"m","vendor":"\#($0.vendor)","url":"\#($0.url)","apiKey":"\#($0.key)"}"# }
        try write("[" + list.joined(separator: ",") + "]", to: home.appendingPathComponent(".workbuddy/models.json"))
    }
    func workBuddyKey(_ key: String = "wb-key") -> OpenAgentCredential {
        OpenAgentCredentials.credential(.glmChina, token: key, client: "WorkBuddy")
    }
    static func window(_ c: OpenAgentCredential, remaining: Double = 70) -> ProviderQuota {
        ProviderQuota(windows: [.init(id: c.pool.windowID("5h"), label: "5 hours", remaining: remaining)], plan: "Pro")
    }
    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    struct Fixed: UsageProvider {
        let report: UsageReport
        func fetchUsage(agents: [AgentDescriptor], historyHours: Int) async throws -> UsageReport { report }
    }

    // MARK: models.json

    func testOnlyAGLMCodingPlanEntryAtZhipusCodingEndpointsIsRead() throws {
        let home = try temp()
        try models([("GLM Coding Plan", chinaCoding, "china-key"),
                    ("GLM Coding Plan", "https://api.z.ai/api/anthropic", "global-key"),
                    ("GLM Coding Plan", "https://proxy.example/api/coding/paas/v4", "proxy-key"),
                    ("GLM Coding Plan", "https://open.bigmodel.cn/api/paas/v4", "api-key"),
                    ("GLM Coding Plan", "https://api.kimi.com/coding", "kimi-key"),
                    ("GLM Coding Plan", "https://opencode.ai/zen/go/v1", "go-key"),
                    ("Kimi", chinaCoding, "other-vendor-key"),
                    ("GLM Coding Plan", chinaCoding, "")], in: home)
        let found = OpenAgentCredentials.discover(home: home, environment: [:], now: now)
        XCTAssertEqual(Set(found.map(\.token)), ["china-key", "global-key"],
                       "a custom URL, Zhipu's API endpoint, Kimi's and OpenCode Go's, and another vendor's entry are not read")
        XCTAssertEqual(found.first { $0.token == "china-key" }?.service, .glmChina)
        XCTAssertEqual(found.first { $0.token == "global-key" }?.service, .glmGlobal)
        XCTAssertTrue(found.allSatisfy { $0.clients == ["WorkBuddy"] && $0.displayGroup == "WorkBuddy" })
        XCTAssertFalse(OpenAgentSource.glm.isInstalled(home: home, environment: [:]),
                       "a plan only WorkBuddy carries does not make GLM detected")
    }

    func testTheModelListIsReadAsATopLevelArray() throws {
        let home = try temp()
        try write(#"{"models":[{"vendor":"GLM Coding Plan","url":"\#(chinaCoding)","apiKey":"wrapped"}]}"#,
                  to: home.appendingPathComponent(".workbuddy/models.json"))
        XCTAssertTrue(OpenAgentCredentials.discover(home: home, environment: [:], now: now).isEmpty)
    }

    func testAKeyAnotherClientCarriesTooIsOnePlanUnderGLMWithWorkBuddyAmongItsClients() throws {
        let home = try temp()
        try models([("GLM Coding Plan", chinaCoding, "shared-key")], in: home)
        try write(#"{"zai-coding-cn":{"type":"api_key","key":"shared-key"}}"#, to: home.appendingPathComponent(".pi/agent/auth.json"))
        let found = OpenAgentCredentials.discover(home: home, environment: [:], now: now)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.clients, ["Pi", "WorkBuddy"])
        XCTAssertEqual(found.first?.displayGroup, "GLM")
        XCTAssertTrue(OpenAgentSource.glm.isInstalled(home: home, environment: [:]))
    }

    // MARK: The provider's report

    func testAWorkBuddyOnlyPlanShowsItsRowsInWorkBuddysGroupAndKeepsTheRestUnderGLM() async throws {
        let key = workBuddyKey(), now = now
        let provider = OpenAgentUsageProvider(credentials: { [key] }, sessions: { _ in .init() },
            fetchQuota: { c, _ in WorkBuddyGLMPlanTests.window(c) }, history: QuotaHistoryStore(), clock: { now })
        let report = try await provider.fetchAccountAndLocalUsage(agents: [], historyHours: 168)
        let row = try XCTUnwrap(report.discoveredAgents.first)
        XCTAssertEqual(row.vendor, "WorkBuddy")
        XCTAssertEqual(row.billingPool, key.pool)
        XCTAssertEqual(report.services, [AgentService(client: "WorkBuddy", provider: "GLM", product: .plan, accountID: key.pool.id,
                                                      region: .china)])
        XCTAssertEqual(report.activeQuotaPoolIDs?["GLM"], [key.pool.id])
        let account = try XCTUnwrap(report.accounts?["GLM"]?.first)
        XCTAssertEqual(account.account.id, key.pool.id)
        XCTAssertEqual(account.label, "GLM · " + key.pool.label)
        XCTAssertEqual(Set(report.accounts.map { Array($0.keys) } ?? []), Set(OpenAgentUsageProvider.poolProviders),
                       "every list this source writes is seeded, and WorkBuddy's own is not one of them")
        XCTAssertTrue(report.isCurrent(row))
        // The plan's calls are priced on BigModel's list, as the key's endpoint says.
        XCTAssertEqual(PriceRegions(report: report).region(for: "workbuddy-model:glm-5.1"), .china)
    }

    func testASharedKeyStaysUnderGLM() async throws {
        let wb = workBuddyKey("shared"), pi = OpenAgentCredentials.credential(.glmChina, token: "shared", client: "Pi"), now = now
        let provider = OpenAgentUsageProvider(credentials: { [wb, pi] }, sessions: { _ in .init() },
            fetchQuota: { c, _ in WorkBuddyGLMPlanTests.window(c) }, history: QuotaHistoryStore(), clock: { now })
        let report = try await provider.fetchAccountAndLocalUsage(agents: [], historyHours: 168)
        XCTAssertEqual(report.discoveredAgents.map(\.vendor), ["GLM"])
        XCTAssertEqual(report.discoveredAgents.first?.source, "Pi, WorkBuddy")
        XCTAssertEqual(report.services?.map(\.client), ["Pi", "WorkBuddy"])
        XCTAssertEqual(report.accounts?["GLM"]?.first?.label, wb.pool.label)
    }

    func testAReadErrorIsShownInThePlansGroup() async throws {
        let key = workBuddyKey(), now = now
        let provider = OpenAgentUsageProvider(credentials: { [key] }, sessions: { _ in .init() },
            fetchQuota: { _, _ in throw ProviderHTTPError(status: 401) }, history: QuotaHistoryStore(), clock: { now })
        let report = try await provider.fetchAccountAndLocalUsage(agents: [], historyHours: 168)
        XCTAssertNotNil(report.sourceNotices["WorkBuddy"])
        XCTAssertTrue(report.sourceNotices["WorkBuddy"]?.hasPrefix("GLM · ") == true)
        XCTAssertNil(report.sourceNotices["GLM"])
        // WorkBuddy's own notice and the plan's are both kept when the two sources are read together.
        let own = UsageReport(generatedAt: now, snapshots: [], sessions: [], sourceNotices: ["WorkBuddy": "local records"],
                              quotaNotices: [:], readingIssues: [:])
        let combined = try await CombinedUsageProvider([.init("Open Agents", provider), .init("WorkBuddy", Fixed(report: own))])
            .fetchUsage(agents: [], historyHours: 168)
        let notice = try XCTUnwrap(combined.sourceNotices["WorkBuddy"])
        XCTAssertTrue(notice.contains("local records") && notice.contains("GLM · "), notice)
    }

    func testARemovedPlanRetiresItsServiceRowsAndAccount() async throws {
        let keys = Box([workBuddyKey()]), clock = Box(now)
        let provider = RetainedUsageProvider(provider: OpenAgentUsageProvider(credentials: { keys.value }, sessions: { _ in .init() },
            fetchQuota: { c, _ in WorkBuddyGLMPlanTests.window(c) }, history: QuotaHistoryStore(), clock: { clock.value }))
        let first = try await provider.fetchAccountAndLocalUsage(agents: [], historyHours: 168)
        XCTAssertEqual(first.services?.count, 1)
        keys.value = []
        clock.value = now.addingTimeInterval(UsageRefresh.accountRequestSpacing + 1)
        let second = try await provider.fetchAccountAndLocalUsage(agents: first.discoveredAgents, historyHours: 168)
        XCTAssertEqual(second.services ?? [], [])
        XCTAssertTrue(second.discoveredAgents.isEmpty)
        XCTAssertEqual(second.accounts?["GLM"] ?? [], [])
    }

    /// The plan's account is GLM's, so WorkBuddy's own account list, which replaces itself on every pass and at a launch
    /// comes before the plan is read again, never holds it, and a plan that moves back to GLM leaves nothing behind there.
    func testWorkBuddysOwnAccountListNeverHoldsThePlan() async throws {
        let key = workBuddyKey(), clock = Box(now), cache = try temp().appendingPathComponent("report.json")
        let own = AccountObservation(account: .unresolved(provider: "WorkBuddy", home: ""), observedAt: now)
        let workBuddy = Fixed(report: UsageReport(generatedAt: now, snapshots: [], sessions: [], accounts: ["WorkBuddy": [own]]))
        func open() -> OpenAgentUsageProvider {
            OpenAgentUsageProvider(credentials: { [key] }, sessions: { _ in .init() }, fetchQuota: { c, _ in WorkBuddyGLMPlanTests.window(c) },
                                   history: QuotaHistoryStore(), clock: { clock.value })
        }
        let first = try await RetainedUsageProvider(provider: CombinedUsageProvider([.init("Open Agents", open()), .init("WorkBuddy", workBuddy)]),
                                                    cacheURL: cache, saveInterval: 0)
            .fetchAccountAndLocalUsage(agents: [], historyHours: 168)
        let row = try XCTUnwrap(first.discoveredAgents.first { $0.billingPool == key.pool })
        XCTAssertEqual(first.accounts?["WorkBuddy"], [own])
        // A launch: WorkBuddy reports its list before the plan is read again.
        clock.value = now.addingTimeInterval(60)
        let launched = try await RetainedUsageProvider(provider: CombinedUsageProvider([.init("Open Agents", open()), .init("WorkBuddy", workBuddy)]),
                                                       cacheURL: cache, saveInterval: 0)
            .fetchUsage(agents: first.discoveredAgents, historyHours: 168)
        XCTAssertEqual(launched.accounts?["WorkBuddy"], [own])
        XCTAssertTrue(launched.isCurrent(row), "the plan's rows are not shown as a former account's")
    }

    func testWorkBuddyLinksNoneOfItsOwnModelsToThePlansRows() async throws {
        let key = workBuddyKey(), now = now
        let open = OpenAgentUsageProvider(credentials: { [key] }, sessions: { _ in .init() },
            fetchQuota: { c, _ in WorkBuddyGLMPlanTests.window(c) }, history: QuotaHistoryStore(), clock: { now })
        let workBuddy = AdditionalUsageProvider(source: .workbuddy, readQuota: { ProviderQuota() }, readSessions: { _ in
            ProviderSessions(sessions: [.init(id: "s", title: "Fixture", client: "WorkBuddy",
                                              events: [.init(id: "e", model: "hunyuan-t1", timestamp: now, input: 10, output: 5)])])
        }, history: QuotaHistoryStore(), clock: { now })
        let combined = CombinedUsageProvider([.init("Open Agents", open), .init("WorkBuddy", workBuddy)])
        let first = try await combined.fetchAccountAndLocalUsage(agents: [], historyHours: 48)
        let row = try XCTUnwrap(first.discoveredAgents.first { $0.billingPool == key.pool })
        let own = AgentDescriptor(id: "workbuddy-window", vendor: "WorkBuddy", model: "Window", source: "", enabled: true)
        let second = try await combined.fetchUsage(agents: first.discoveredAgents + [own], historyHours: 48)
        XCTAssertEqual(second.consumerIdsByQuota[row.id], [], "the plan's rows count only calls that went through the plan")
        XCTAssertEqual(second.consumerIdsByQuota[own.id], ["workbuddy-model:hunyuan-t1"])
    }

    // MARK: Settings and the report

    func testSettingsShowThePlansAccountInTheGroupOfItsRows() {
        let pool = workBuddyKey().pool
        let account = AccountObservation(account: ProviderAccount(pool: pool), label: "GLM · " + pool.label, observedAt: now)
        let row = AgentDescriptor(id: pool.windowID("5h"), vendor: "WorkBuddy", model: "5 hours", source: "WorkBuddy", enabled: true,
                                  billingPool: pool, account: ProviderAccount(pool: pool))
        let glm = SourceStatus(id: "glm", name: "GLM", detail: "", state: .notDetected)
        let report = UsageReport(generatedAt: now, snapshots: [], sessions: [], accounts: ["GLM": [account]])
        let groups = AgentSettingsGroup.make(sources: [glm], agents: [row], report: report)
        XCTAssertEqual(groups.first { $0.id == "WorkBuddy" }?.accounts, [account])
        XCTAssertEqual(groups.first { $0.id == "WorkBuddy" }?.windowSections.first?.title, "GLM · " + pool.label)
        XCTAssertEqual(groups.first { $0.id == "GLM" }?.accounts, [], "GLM's group lists no plan whose rows are elsewhere")

        // The same plan, carried by Pi too, is GLM's; an entry an earlier build left in WorkBuddy's list is not shown there.
        let shared = row.moved(to: "GLM"), workBuddy = SourceStatus(id: "workbuddy", name: "WorkBuddy", detail: "", state: .installed)
        let earlier = UsageReport(generatedAt: now, snapshots: [], sessions: [], accounts: ["GLM": [account], "WorkBuddy": [account]])
        let moved = AgentSettingsGroup.make(sources: [glm, workBuddy], agents: [shared], report: earlier)
        XCTAssertEqual(moved.first { $0.id == "GLM" }?.accounts, [account])
        XCTAssertEqual(moved.first { $0.id == "WorkBuddy" }?.accounts, [])
    }

    func testARowShownInAnotherGroupIsCurrentByItsProvidersList() {
        let pool = workBuddyKey().pool
        let row = AgentDescriptor(id: pool.windowID("5h"), vendor: "WorkBuddy", model: "5 hours", source: "WorkBuddy", enabled: true,
                                  billingPool: pool, account: ProviderAccount(pool: pool))
        let plan = AccountObservation(account: ProviderAccount(pool: pool), observedAt: now)
        let own = AccountObservation(account: .unresolved(provider: "WorkBuddy", home: ""), observedAt: now)
        func report(_ accounts: [String: [AccountObservation]]?) -> UsageReport {
            UsageReport(generatedAt: now, snapshots: [], sessions: [], accounts: accounts)
        }
        XCTAssertTrue(report(["GLM": [plan], "WorkBuddy": [own]]).isCurrent(row))
        XCTAssertFalse(report(["GLM": [], "WorkBuddy": [plan]]).isCurrent(row), "the row's vendor's list does not speak for its account")
        XCTAssertFalse(report(["GLM": [plan.with(isCurrent: false)]]).isCurrent(row))
        XCTAssertTrue(report(["WorkBuddy": [own]]).isCurrent(row), "without GLM's list nothing says the account is former")
        XCTAssertTrue(report(nil).isCurrent(row))
    }

    @MainActor func testARowMovesToItsNewGroupAndKeepsItsSwitch() throws {
        let suite = "WorkBuddyGLMPlanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let pool = workBuddyKey().pool
        let row = AgentDescriptor(id: pool.windowID("5h"), vendor: "WorkBuddy", model: "5 hours", source: "WorkBuddy", enabled: true,
                                  billingPool: pool, account: ProviderAccount(pool: pool))
        let store = SettingsStore(defaults: defaults)
        store.mergeDiscovered([row])
        store.setAgent(id: row.id, enabled: false)
        store.mergeDiscovered([row.moved(to: "GLM", source: "Pi, WorkBuddy")])
        let moved = try XCTUnwrap(store.agents.first { $0.id == row.id })
        XCTAssertEqual(moved.vendor, "GLM")
        XCTAssertEqual(moved.source, "Pi, WorkBuddy")
        XCTAssertFalse(moved.enabled, "the switch survives the move")
        XCTAssertEqual(store.agents.count, 1)
    }
}

private extension AgentDescriptor {
    func moved(to vendor: String, source: String? = nil) -> AgentDescriptor {
        AgentDescriptor(id: id, vendor: vendor, model: model, shortModel: shortModel, source: source ?? self.source, enabled: enabled,
                        connected: connected, billingPool: billingPool, account: account, allModels: allModels)
    }
}
