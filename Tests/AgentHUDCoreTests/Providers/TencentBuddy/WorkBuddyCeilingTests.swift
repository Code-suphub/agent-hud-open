import Foundation
import XCTest
@testable import AgentHUDCore

/// WorkBuddy's plan ceilings: when they make an account, how long a ceiling's row stays, and when the app's reading of
/// the plan a model went through wins over its 429. Also the names its models read as, and CodeBuddy Code pointed at
/// WorkBuddy's folder.
final class WorkBuddyCeilingTests: XCTestCase, @unchecked Sendable {
    let now = Date(timeIntervalSince1970: 1_788_800_000)

    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func hit(_ model: String = "glm-5.1", route: String? = nil, window: String = "5h", reset: TimeInterval) -> ProviderLimitHit {
        ProviderLimitHit(model: model, route: route, window: window, reset: now.addingTimeInterval(reset), observedAt: now)
    }

    /// A WorkBuddy provider whose transcripts hold `sessions.value` on each pass.
    func provider(_ sessions: Box<ProviderSessions>, clock: Box<Date>, ceilings: WorkBuddyCeilings = WorkBuddyCeilings()) -> AdditionalUsageProvider {
        AdditionalUsageProvider(source: .workbuddy, readQuota: { ProviderQuota() }, readSessions: { _ in sessions.value },
                                history: QuotaHistoryStore(), clock: { clock.value }, ceilings: ceilings)
    }

    func ceilingRows(_ report: UsageReport) -> [AgentDescriptor] { report.discoveredAgents.filter { $0.id.contains("/limit:") } }

    // MARK: The account

    func testWithoutACeilingToShowOrRetireWorkBuddyHasNoAccount() async throws {
        let none = try await provider(Box(ProviderSessions()), clock: Box(now)).fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(none.accounts?["WorkBuddy"], [], "no reading names an account, so the list is empty")
        let workBuddy = SourceStatus(id: "workbuddy", name: "WorkBuddy", detail: "", state: .installed)
        XCTAssertEqual(AgentSettingsGroup.make(sources: [workBuddy], agents: none.discoveredAgents, report: none)
            .first { $0.id == "WorkBuddy" }?.accounts, [], "Settings shows no unnamed account")

        // A ceiling whose reset has passed, with no row of it shown, makes no account either.
        let expired = try await provider(Box(ProviderSessions(limitHits: [hit(reset: -60)])), clock: Box(now))
            .fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(expired.accounts?["WorkBuddy"], [])
        XCTAssertTrue(ceilingRows(expired).isEmpty)

        // The account a build that reported one on every pass left behind retires.
        let placeholder = AccountObservation(account: .unresolved(provider: "WorkBuddy", home: ""), observedAt: now)
        let earlier = UsageReport(generatedAt: now, snapshots: [], sessions: [], accounts: ["WorkBuddy": [placeholder]])
        XCTAssertEqual(none.retainingReadings(from: earlier).accounts?["WorkBuddy"], [])
    }

    func testWhileTranscriptsAreIndexedTheCeilingsClaimNothing() async throws {
        let sessions = Box(ProviderSessions(indexing: IndexProgress(done: 1, total: 3), limitHits: [hit(reset: 3600)]))
        let report = try await provider(sessions, clock: Box(now)).fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(ceilingRows(report).count, 1, "a ceiling read so far is shown")
        XCTAssertNil(report.accounts?["WorkBuddy"], "the ceilings read so far may not be all of them, so no inventory is claimed")
    }

    // MARK: How long a row stays

    func testAMonthlyCeilingOutlivesTheWeekOfTranscriptsAPassReads() async throws {
        let file = try temp().appendingPathComponent("workbuddy-ceilings.json")
        let sessions = Box(ProviderSessions(limitHits: [hit(window: "month", reset: 20 * 86400)])), clock = Box(now)
        let workBuddy = provider(sessions, clock: clock, ceilings: WorkBuddyCeilings(fileURL: file))
        let first = try await workBuddy.fetchUsage(agents: [], historyHours: 24)
        let row = try XCTUnwrap(ceilingRows(first).first)
        XCTAssertEqual(row.shortModel, WorkBuddySessions.displayName("glm-5.1", apiReached: []) + " · " + WindowNames.Period.month.shortName)

        // Eight days on, the session was not written again and its transcript is no longer read.
        sessions.value = ProviderSessions()
        clock.value = now.addingTimeInterval(8 * 86400)
        let later = try await workBuddy.fetchUsage(agents: first.discoveredAgents, historyHours: 24)
        XCTAssertEqual(ceilingRows(later).map(\.id), [row.id], "the vendor still blocks the model, so the row stays")
        XCTAssertEqual(later.snapshots.first { $0.agentId == row.id }?.resetAt, now.addingTimeInterval(20 * 86400))
        XCTAssertTrue(try XCTUnwrap(later.accounts?["WorkBuddy"]?.first?.quotaWindowIDs).contains(row.id))

        // After a launch the ceiling is read back from where it was kept.
        clock.value = now.addingTimeInterval(9 * 86400)
        let launched = try await provider(sessions, clock: clock, ceilings: WorkBuddyCeilings(fileURL: file))
            .fetchUsage(agents: later.discoveredAgents, historyHours: 24)
        XCTAssertEqual(ceilingRows(launched).map(\.id), [row.id])

        // Once its reset passes, the row leaves the inventory, which retires it.
        clock.value = now.addingTimeInterval(21 * 86400)
        let reset = try await provider(sessions, clock: clock, ceilings: WorkBuddyCeilings(fileURL: file))
            .fetchUsage(agents: launched.discoveredAgents, historyHours: 24)
        XCTAssertTrue(ceilingRows(reset).isEmpty)
        XCTAssertEqual(reset.accounts?["WorkBuddy"]?.first?.quotaWindowIDs, [])
        XCTAssertEqual(try JSONDecoder().decode([ProviderLimitHit].self, from: Data(contentsOf: file)), [], "nothing past its reset is kept")
    }

    // MARK: A reading of the plan wins

    /// A WorkBuddy transcript whose sessions called glm-5.1 through its GLM Coding Plan entry and Intern-S2 through
    /// another entry, each until a 429 with a reset two hours ahead.
    func transcripts(in home: URL) throws {
        let reset = wallClock(now.addingTimeInterval(7200))
        func session(_ id: String, model: String, route: String) -> [String] {
            let ms = Int(now.timeIntervalSince1970 * 1000)
            return [#"{"type":"message","role":"assistant","status":"completed","timestamp":\#(ms),"sessionId":"\#(id)","cwd":"/Users/alice/repo","providerData":{"model":"\#(model)","requestModelId":"custom-local:\#(route)","messageId":"\#(id)-m1","usage":{"inputTokens":100,"outputTokens":4,"totalTokens":104}}}"#,
                    #"{"id":"\#(id)-e1","timestamp":\#(ms + 3000),"type":"message","role":"assistant","status":"incomplete","sessionId":"\#(id)","cwd":"/Users/alice/repo","providerData":{"error":{"message":"429 已达到 5 小时的使用上限。您的限额将在 \#(reset) 重置。","status":429}}}"#]
        }
        try write((session("s1", model: "glm-5.1", route: "glm-5.1") + session("s2", model: "Intern-S2", route: "intern-s2")).joined(separator: "\n") + "\n",
                  to: home.appendingPathComponent(".workbuddy/projects/repo/s1.jsonl"))
    }

    func models(_ glmKey: String?, in home: URL) throws {
        let glm = glmKey.map { [#"{"id":"glm-5.1","name":"GLM-5.1","vendor":"GLM Coding Plan","url":"https://open.bigmodel.cn/api/coding/paas/v4","apiKey":"\#($0)"}"#] } ?? []
        let intern = #"{"id":"intern-s2","name":"Intern-S2","vendor":"Intern","url":"https://chat.intern-ai.org.cn/api/v1/chat/completions","apiKey":"intern-key"}"#
        try write("[" + (glm + [intern]).joined(separator: ",") + "]", to: home.appendingPathComponent(".workbuddy/models.json"))
    }

    /// The app's providers for `home`: WorkBuddy's transcripts, and the GLM Coding Plan whose key its model list keeps,
    /// read from Zhipu at its ceiling.
    func app(home: URL, clock: Box<Date>) -> RetainedUsageProvider {
        let now = now
        let open = OpenAgentUsageProvider(credentials: { OpenAgentCredentials.discover(home: home, environment: [:], now: clock.value) },
            sessions: { _ in .init() }, fetchQuota: { credential, _ in
                ProviderQuota(windows: [.init(id: credential.pool.windowID("5h"), label: "5 hours", remaining: 0,
                                              reset: now.addingTimeInterval(7200), duration: 5 * 3600)], plan: "Pro")
            }, history: QuotaHistoryStore(), clock: { clock.value })
        let workBuddy = AdditionalUsageProvider(source: .workbuddy, readQuota: { ProviderQuota() }, readSessions: { since in
            await AdditionalLocalStore(source: .workbuddy, roots: [home.appendingPathComponent(".workbuddy/projects")]).index(since: since)
        }, history: QuotaHistoryStore(), clock: { clock.value }, ceilings: WorkBuddyCeilings(home: home))
        return RetainedUsageProvider(provider: CombinedUsageProvider([.init("WorkBuddy", workBuddy), .init("Open agents", open)]))
    }

    func testAZhipuReadingOfThePlanAModelWentThroughWinsOverItsCeiling() async throws {
        let home = try temp(), clock = Box(now)
        try transcripts(in: home)
        try models("wb-key", in: home)
        let plan = OpenAgentCredentials.credential(.glmChina, token: "wb-key", client: "WorkBuddy").pool
        let app = app(home: home, clock: clock)
        let first = try await app.fetchAccountAndLocalUsage(agents: [], historyHours: 24)
        let planRow = try XCTUnwrap(first.discoveredAgents.first { $0.billingPool == plan })
        XCTAssertEqual(planRow.vendor, "WorkBuddy", "the plan only WorkBuddy carries is shown in its group")

        // The next pass knows the app reads the plan: its 5-hour window stands for glm-5.1's ceiling, and Intern-S2,
        // whose plan the app does not read, keeps its own.
        let second = try await app.fetchUsage(agents: first.discoveredAgents, historyHours: 24)
        XCTAssertTrue(second.discoveredAgents.contains { $0.id == planRow.id })
        XCTAssertEqual(ceilingRows(second).map(\.model), ["Intern-S2 · " + WorkBuddyCeilings.label("5h")],
                       "the 429 of a model whose plan is read from Zhipu is not shown beside that reading")

        // Without the plan's key nothing reads the plan, and the 429 is its only reading again.
        try models(nil, in: home)
        clock.value = now.addingTimeInterval(UsageRefresh.accountRequestSpacing + 1)
        let removed = try await app.fetchAccountAndLocalUsage(agents: second.discoveredAgents, historyHours: 24)
        XCTAssertFalse(removed.discoveredAgents.contains { $0.billingPool == plan })
        let alone = try await app.fetchUsage(agents: removed.discoveredAgents, historyHours: 24)
        XCTAssertEqual(Set(ceilingRows(alone).map(\.model)),
                       [WorkBuddySessions.displayName("glm-5.1", apiReached: ["glm-5.1"]) + " · " + WorkBuddyCeilings.label("5h"),
                        "Intern-S2 · " + WorkBuddyCeilings.label("5h")])
    }

    func testTheSamePlanCarriedByPiToo() async throws {
        let home = try temp(), clock = Box(now)
        try transcripts(in: home)
        try models("shared-key", in: home)
        try write(#"{"zai-coding-cn":{"type":"api_key","key":"shared-key"}}"#, to: home.appendingPathComponent(".pi/agent/auth.json"))
        let app = app(home: home, clock: clock)
        let first = try await app.fetchAccountAndLocalUsage(agents: [], historyHours: 24)
        XCTAssertEqual(first.discoveredAgents.first { $0.billingPool != nil }?.vendor, "GLM", "a key Pi carries too stays under GLM")
        let second = try await app.fetchUsage(agents: first.discoveredAgents, historyHours: 24)
        XCTAssertEqual(ceilingRows(second).map(\.model), ["Intern-S2 · " + WorkBuddyCeilings.label("5h")],
                       "the reading wins whichever group it is shown in")
    }

    func testOnlyAnEntryThatNamesOnePlanRoutesToIt() throws {
        let home = try temp()
        let entry = { (id: String, key: String) in
            #"{"id":"\#(id)","vendor":"GLM Coding Plan","url":"https://open.bigmodel.cn/api/coding/paas/v4","apiKey":"\#(key)"}"#
        }
        try write("[" + [entry("one", "a"), entry("twice", "a"), entry("twice", "b"), entry("same", "c"), entry("same", "c"),
                         #"{"id":"other","vendor":"Kimi","url":"https://api.kimi.com/coding","apiKey":"k"}"#].joined(separator: ",") + "]",
                  to: home.appendingPathComponent(".workbuddy/models.json"))
        let pool = { (key: String) in OpenAgentCredentials.credential(.glmChina, token: key, client: "WorkBuddy").pool.id }
        XCTAssertEqual(OpenAgentCredentials.workBuddyPlanRoutes(home: home), ["one": pool("a"), "same": pool("c")],
                       "an id two keys share names neither, and another vendor's entry is not read")
    }

    // MARK: Names

    func testAModelTheAppServedReadsWithItsMarkAndTheCatalogsName() {
        XCTAssertEqual(WorkBuddySessions.displayName("glm-5.3", apiReached: []), L10n.text("glm-5.3（WorkBuddy）", "glm-5.3 (WorkBuddy)"))
        XCTAssertEqual(WorkBuddySessions.displayName("kimi-for-coding", apiReached: []),
                       L10n.text("Kimi For Coding（WorkBuddy）", "Kimi For Coding (WorkBuddy)"))
        XCTAssertEqual(WorkBuddySessions.displayName("kimi-for-coding", apiReached: ["kimi-for-coding"]), "Kimi For Coding")
        let long = "a-model-whose-name-is-long"
        XCTAssertEqual(WorkBuddySessions.displayName(long, apiReached: []), L10n.text("\(long)（WB）", "\(long) (WB)"))
    }

    // MARK: CodeBuddy Code pointed at WorkBuddy's folder

    func testCODEBUDDYCONFIGDIRNamingWorkBuddysFolderLeavesCodeBuddyItsOwn() throws {
        let home = try temp(), workBuddy = home.appendingPathComponent(".workbuddy")
        for value in [workBuddy.path, workBuddy.path + "/", home.path + "/./.workbuddy"] {
            let environment = ["CODEBUDDY_CONFIG_DIR": value]
            XCTAssertEqual(CodeBuddySessions.home(home, environment: environment).path, home.appendingPathComponent(".codebuddy").path, value)
            XCTAssertEqual(CodeBuddySessions.roots(home: home, environment: environment).map(\.path),
                           [home.appendingPathComponent(".codebuddy/projects").path], "WorkBuddy's transcripts are read once, as WorkBuddy's")
            XCTAssertEqual(CodeBuddySharedHome.folder(home: home, environment: environment)?.path, workBuddy.path)
        }
        let own = home.appendingPathComponent("codebuddy-config")
        XCTAssertEqual(CodeBuddySessions.home(home, environment: ["CODEBUDDY_CONFIG_DIR": own.path]).path, own.path)
        XCTAssertNil(CodeBuddySharedHome.folder(home: home, environment: ["CODEBUDDY_CONFIG_DIR": own.path]))
        XCTAssertNil(CodeBuddySharedHome.folder(home: home, environment: [:]))
    }

    func testCodeBuddysHandlersAnEarlierVersionWroteInWorkBuddysSettingsAreTakenOut() throws {
        let home = try temp(), executable = URL(fileURLWithPath: "/tmp/hud")
        let settings = home.appendingPathComponent(".workbuddy/settings.json")
        func handler(_ arguments: String) -> String {
            #"{"hooks":[{"type":"command","command":"\#(HookCommand.make(executable: executable, arguments: arguments).replacingOccurrences(of: "\"", with: "\\\""))"}]}"#
        }
        let original = #"{"model":"auto","hooks":{"PermissionRequest":[\#(handler("--permission-hook codebuddy")),\#(handler("--permission-hook workbuddy"))],"Stop":[\#(handler("--completion-hook codebuddy")),\#(handler("--completion-hook workbuddy")),{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try write(original, to: settings)
        try CodeBuddySharedHome.removeHandlers(home: home, environment: [:], executable: executable)
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), original, "without the variable WorkBuddy's settings are left alone")

        try CodeBuddySharedHome.removeHandlers(home: home, environment: ["CODEBUDDY_CONFIG_DIR": home.appendingPathComponent(".workbuddy").path],
                                               executable: executable)
        let result = try ProviderJSON.read(Data(contentsOf: settings))
        func commands(_ event: String) -> [String] {
            (result["hooks"][event].arrayValue ?? []).flatMap { $0["hooks"].arrayValue ?? [] }.compactMap { $0["command"].stringValue }
        }
        XCTAssertEqual(commands("PermissionRequest"), ["'/tmp/hud' --permission-hook workbuddy"])
        XCTAssertEqual(commands("Stop"), ["'/tmp/hud' --completion-hook workbuddy", "say done"])
        XCTAssertEqual(result["model"].stringValue, "auto")
    }

    /// A reset time as the vendor writes it: a wall-clock time in Beijing, whatever zone this Mac runs in.
    func wallClock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}
