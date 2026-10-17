import XCTest
@testable import AgentHUDCore

/// A drag in Settings → Agents records one order of the provider groups (`Settings.providerOrder`). The page and the Tokens
/// page list the groups in it, and the agent rows keep to it, so the HUD, the glow and the menu bar list them the same way.
@MainActor
final class ProviderGroupOrderTests: XCTestCase {
    private let known = ["Claude", "Codex", "Cursor", "GLM", "Kimi", "WorkBuddy"]

    // MARK: Settings.moveProvider

    func testAMoveRecordsEveryListedGroupWithOnlyTheMovedOneDisplaced() {
        var settings = Settings()
        settings.moveProvider(id: "WorkBuddy", to: "Codex", known: known)
        XCTAssertEqual(settings.providerOrder, ["Claude", "WorkBuddy", "Codex", "Cursor", "GLM", "Kimi"])
        // A later move starts from the recorded order and moves only the group it names.
        settings.moveProvider(id: "Kimi", to: "Claude", known: known)
        XCTAssertEqual(settings.providerOrder, ["Kimi", "Claude", "WorkBuddy", "Codex", "Cursor", "GLM"])
        settings.moveProvider(id: "Kimi", to: "Codex", known: known)
        XCTAssertEqual(settings.providerOrder, ["Claude", "WorkBuddy", "Codex", "Kimi", "Cursor", "GLM"],
                       "a group moved down lands after its target, where the live drag leaves it")
    }

    func testAMoveOfAGroupThePageDoesNotListChangesNothing() {
        var settings = Settings()
        settings.moveProvider(id: "Ghost", to: "Codex", known: known)
        XCTAssertEqual(settings.providerOrder, [], "a drag of a group the page does not list changes nothing")
        settings.moveProvider(id: "Codex", to: "Phantom", known: known)
        XCTAssertEqual(settings.providerOrder, [], "and neither does one onto a group it does not list")
    }

    func testEntriesThatNoLongerExistAreIgnoredAndNewcomersKeepTheirPlace() throws {
        var settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"providerOrder":["Gone","Codex","Claude"]}"#.utf8))
        settings.moveProvider(id: "Claude", to: "Codex", known: known)
        XCTAssertEqual(settings.providerOrder, ["Claude", "Codex", "Cursor", "GLM", "Kimi", "WorkBuddy"])
    }

    // MARK: AgentSettingsGroup.make

    func testThePageListsTheGroupsInTheRecordedOrder() {
        let rows = [row("Claude"), row("Codex")]
        let sources = [source("Claude"), source("Codex"), source("Kimi"), source("Cursor", detected: false),
                       source("Qwen", detected: false), source("GLM")]
        func page(_ providerOrder: [String]) -> [String] {
            AgentSettingsGroup.make(sources: sources, agents: rows, providerOrder: providerOrder).map(\.id)
        }
        XCTAssertEqual(page([]), ["Claude", "Codex", "Kimi", "GLM", "Cursor", "Qwen"],
                       "without a recorded order the groups follow the rows, then the sources")
        XCTAssertEqual(page(["GLM", "Kimi", "Codex", "Claude", "Qwen", "Cursor"]), ["GLM", "Kimi", "Codex", "Claude", "Qwen", "Cursor"])
        XCTAssertEqual(page(["Kimi", "Codex"]), ["Kimi", "Codex", "Claude", "GLM", "Cursor", "Qwen"],
                       "groups the order does not name follow those it names, in their own order")
        XCTAssertEqual(page(["Gone", "Codex", "Phantom", "Claude"]), ["Codex", "Claude", "Kimi", "GLM", "Cursor", "Qwen"],
                       "entries naming no group are passed over")
        XCTAssertEqual(page(["Codex", "Claude", "Codex"]), ["Codex", "Claude", "Kimi", "GLM", "Cursor", "Qwen"],
                       "a repeated entry counts once, where it first appears")
        XCTAssertEqual(page(["Qwen", "Cursor", "GLM", "Claude"]), ["GLM", "Claude", "Codex", "Kimi", "Qwen", "Cursor"],
                       "groups not detected stay after the others, in the recorded order among themselves")
        XCTAssertEqual(AgentSettingsGroup.make(sources: sources, agents: rows, providerOrder: ["Codex", "Claude"])
            .first { $0.id == "Codex" }?.agents, [rows[1]], "a group keeps its rows wherever it is listed")
    }

    // MARK: SettingsStore

    func testADraggedGroupOrdersTheHUDAndANewVendorsRowsTakeTheirRecordedPlace() throws {
        let sources = [source("Claude"), source("Codex"), source("Kimi"), source("Cursor", detected: false)]
        let store = SettingsStore(defaults: try makeDefaults(), defaultAgents: [row("Claude"), row("Codex")])
        store.moveProviderGroup(id: "Codex", to: "Claude", known: page(store, sources))
        XCTAssertEqual(page(store, sources), ["Codex", "Claude", "Kimi", "Cursor"])
        XCTAssertEqual(hud(store), ["Codex", "Claude"], "the same drag orders the HUD's rows and the glow with it")

        // Kimi, installed with no rows at the drag, signs in: its rows go to Kimi's recorded place, not to the top.
        store.mergeDiscovered([row("Kimi")])
        XCTAssertEqual(page(store, sources), ["Codex", "Claude", "Kimi", "Cursor"])
        assertTheHUDFollowsThePage(store, sources)

        // A vendor the order does not name follows those it names, on the page and in the HUD.
        let grok = sources + [source("Grok")]
        store.mergeDiscovered([row("Grok")])
        XCTAssertEqual(page(store, grok), ["Codex", "Claude", "Kimi", "Grok", "Cursor"])
        assertTheHUDFollowsThePage(store, grok)

        // A later drag starts from the order both show.
        store.moveProviderGroup(id: "Kimi", to: "Codex", known: page(store, grok))
        XCTAssertEqual(page(store, grok), ["Kimi", "Codex", "Claude", "Grok", "Cursor"])
        assertTheHUDFollowsThePage(store, grok)
    }

    func testADropOnAGroupWithoutRowsMovesTheHUDToo() throws {
        let sources = [source("Claude"), source("Codex"), source("Kimi")]
        let store = SettingsStore(defaults: try makeDefaults(), defaultAgents: [row("Claude"), row("Codex")])
        store.moveProviderGroup(id: "Claude", to: "Kimi", known: page(store, sources))
        XCTAssertEqual(page(store, sources), ["Codex", "Kimi", "Claude"])
        XCTAssertEqual(hud(store), ["Codex", "Claude"])
        store.moveProviderGroup(id: "Kimi", to: "Codex", known: page(store, sources))
        XCTAssertEqual(page(store, sources), ["Kimi", "Codex", "Claude"])
        XCTAssertEqual(hud(store), ["Codex", "Claude"], "a group without rows moves on the page alone")
    }

    func testAPlanThatMovesBetweenGroupsStaysInTheRecordedOrder() throws {
        // Since a GLM plan only WorkBuddy carries shows in WorkBuddy's group, a merge can move its rows between the two.
        let pool = OpenAgentCredentials.credential(.glmChina, token: "wb-key", client: "WorkBuddy").pool
        let plan = AgentDescriptor(id: pool.windowID("5h"), vendor: "WorkBuddy", model: "5 hours", source: "WorkBuddy", enabled: true,
                                   billingPool: pool, account: ProviderAccount(pool: pool))
        let shared = AgentDescriptor(id: plan.id, vendor: "GLM", model: plan.model, source: "Pi, WorkBuddy", enabled: true,
                                     billingPool: pool, account: plan.account)
        let sources = [source("Claude"), source("WorkBuddy"), source("GLM")]
        let store = SettingsStore(defaults: try makeDefaults(), defaultAgents: [row("Claude"), row("WorkBuddy"), plan])
        store.moveProviderGroup(id: "GLM", to: "Claude", known: page(store, sources))
        XCTAssertEqual(page(store, sources), ["GLM", "Claude", "WorkBuddy"])
        XCTAssertEqual(hud(store), ["Claude", "WorkBuddy"])

        // Pi carries the key too: the plan's rows are GLM's, and GLM's group has its recorded place in the HUD as well.
        store.mergeDiscovered([shared])
        XCTAssertEqual(hud(store), ["GLM", "Claude", "WorkBuddy"])
        assertTheHUDFollowsThePage(store, sources)

        // WorkBuddy alone carries it again.
        store.mergeDiscovered([plan])
        XCTAssertEqual(hud(store), ["Claude", "WorkBuddy"])
        XCTAssertEqual(store.agents.filter { $0.vendor == "WorkBuddy" }.count, 2, "the plan's rows are back in WorkBuddy's group")
        assertTheHUDFollowsThePage(store, sources)
    }

    func testRowsSavedOutOfTheRecordedOrderFollowItAtLaunch() throws {
        let defaults = try makeDefaults()
        let first = SettingsStore(defaults: defaults, defaultAgents: [row("Claude"), row("Codex")])
        first.moveProviderGroup(id: "Codex", to: "Claude", known: ["Claude", "Codex", "Kimi"])
        // Rows saved in another order, as a build that kept the two orders apart could leave them.
        defaults.set(try JSONEncoder().encode([row("Kimi"), row("Claude"), row("Codex")]), forKey: SettingsStore.Keys.agents)
        XCTAssertEqual(SettingsStore(defaults: defaults).agents.map(\.vendor), ["Codex", "Claude", "Kimi"])
    }

    func testMovingAGroupOfRowsRecordsTheOrderToo() throws {
        let store = SettingsStore(defaults: try makeDefaults(), defaultAgents: [row("Claude"), row("Codex"), row("Cursor")])
        store.moveAgentGroup(id: "Cursor", to: "Claude")
        XCTAssertEqual(store.settings.providerOrder, ["Cursor", "Claude", "Codex"])
        XCTAssertEqual(hud(store), ["Cursor", "Claude", "Codex"])
        store.mergeDiscovered([row("Kimi")])
        XCTAssertEqual(hud(store), ["Cursor", "Claude", "Codex", "Kimi"], "a later merge keeps the move")
    }

    // MARK: Helpers

    private func row(_ vendor: String) -> AgentDescriptor {
        AgentDescriptor(id: vendor.lowercased() + "-5h", vendor: vendor, model: "5h", source: "", enabled: true)
    }

    private func source(_ name: String, detected: Bool = true) -> SourceStatus {
        SourceStatus(id: name.lowercased(), name: name, detail: "", state: detected ? .installed : .notDetected)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ProviderGroupOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// The groups Settings → Agents lists, in its order.
    private func page(_ store: SettingsStore, _ sources: [SourceStatus]) -> [String] {
        AgentSettingsGroup.make(sources: sources, agents: store.agents, providerOrder: store.settings.providerOrder).map(\.id)
    }

    /// The groups the HUD lists, in its order.
    private func hud(_ store: SettingsStore) -> [String] {
        ReportView(report: nil, agents: store.agents, settings: store.settings, now: Date()).rowGroups.map(\.vendor)
    }

    private func assertTheHUDFollowsThePage(_ store: SettingsStore, _ sources: [SourceStatus],
                                            file: StaticString = #filePath, line: UInt = #line) {
        let listed = AgentSettingsGroup.make(sources: sources, agents: store.agents, providerOrder: store.settings.providerOrder)
        XCTAssertEqual(hud(store), listed.filter { !$0.agents.isEmpty }.map(\.id),
                       "the HUD lists the groups with rows as Settings → Agents does", file: file, line: line)
    }
}
