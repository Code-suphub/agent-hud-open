import AgentHUDSupport
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

/// The app's own settings under an agent's app draft, drawn at once wherever the app reads them: every screen's HUD and
/// its marks, the hover's timing, the menu-bar item and the windows' look, and the Settings controls, which show the draft
/// and whose edit drops that field first. Discard gives back what is saved and Save writes it; nothing else writes.
@MainActor
final class AppDraftHUDTests: XCTestCase {
    private var changes = 0

    /// The demo over settings of their own, with the main display a Dynamic dock.
    private func make() throws -> (store: UsageStore, settings: SettingsStore, key: String, screen: NSScreen) {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let key = ScreenIdentity.key(for: screen)
        let domain = "app.agenthud.tests.app-draft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        addTeardownBlock { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.agents)
        settings.update {
            $0.screens[key] = ScreenPlacement(mode: .logos, edge: .top)
            $0.showIslandTokens = false
            $0.showIslandSessions = false
        }
        settings.onChange = { [weak self] _ in self?.changes += 1 }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, accessAllowed: { false })
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours, now: Date()))
        return (store, settings, key, screen)
    }

    /// Waits for the main run loop to bring `condition` about, for up to two seconds.
    private func poll(_ what: String, line: UInt = #line, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), what, line: line)
    }

    /// A draft re-applies every HUD through the controller that watches the settings: the dock's marks stop turning into
    /// bots, and the hover takes the draft's delays, with nothing opened and nothing written; Discard gives both back.
    func testADraftReappliesTheHUDWithItsBotsAndItsHover() throws {
        let (store, settings, key, screen) = try make()
        let controller = IslandController(store: store, settings: settings)
        defer { controller.rebuild(keys: [], screens: []) }
        controller.rebuild(keys: [key], screens: [screen])
        let hud = try XCTUnwrap(controller.huds[key])
        XCTAssertTrue(hud.island.rootView.botLogos)
        XCTAssertEqual(hud.island.rootView.logoQueue?.bots, true)
        changes = 0

        settings.panelLayout.proposeApp(AppDraft(botLogos: false, delayMs: 900, collapseDelayMs: 50))
        poll("the marks stay logos") { !hud.island.rootView.botLogos && hud.island.rootView.logoQueue?.bots == false }
        XCTAssertEqual(hud.config.hoverDelay, 0.9, accuracy: 0.000_1, "hovering waits as the draft says")
        XCTAssertEqual(hud.config.collapseDelay, 0.05, accuracy: 0.000_1)
        XCTAssertFalse(hud.island.rootView.isOpen, "nothing opens the panel")
        XCTAssertEqual(changes, 0, "and nothing is written")
        XCTAssertTrue(settings.settings.botLogos)

        settings.panelLayout.discardPanel(on: key)
        poll("discarding gives the bots back") { hud.island.rootView.botLogos && hud.island.rootView.logoQueue?.bots == true }
        XCTAssertEqual(hud.config.hoverDelay, settings.settings.hoverDelay, accuracy: 0.000_1)
    }

    /// A draft that hides the menu-bar item hides it at once, and the HUD's panel keeps the bar with its Save and Discard,
    /// whose Discard brings the item back; Save writes the setting.
    func testTheMenuBarItemFollowsADraftAndTheBarStaysOnTheHUD() throws {
        let (_, settings, key, _) = try make()
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings)
        let controller = StatusItemController(store: store, settings: settings)
        defer { controller.closeMenu() }
        XCTAssertTrue(controller.showsItem)

        settings.panelLayout.proposeApp(AppDraft(showMenuBarIcon: false))
        poll("the item leaves the menu bar") { !controller.showsItem }
        XCTAssertTrue(settings.panelLayout.hasDraft(on: key), "the panel's bar is the way back")
        XCTAssertTrue(settings.settings.showMenuBarIcon, "nothing is written")

        settings.panelLayout.discardPanel(on: key)
        poll("Discard brings it back") { controller.showsItem }

        settings.panelLayout.proposeApp(AppDraft(showMenuBarIcon: false))
        poll("the item leaves the menu bar again") { !controller.showsItem }
        settings.panelLayout.savePanel(on: key)
        XCTAssertFalse(settings.settings.showMenuBarIcon, "Save writes it")
        XCTAssertFalse(controller.showsItem)
        settings.update { $0.showMenuBarIcon = true }
        poll("the item is back") { controller.showsItem }
    }

    /// The windows take the draft's Match screen and the app the draft's Appearance, as they take a person's.
    func testTheWindowsFollowADraftsMatchScreen() throws {
        let (_, settings, key, screen) = try make()
        XCTAssertNil(settings.windowLook(on: screen))
        settings.panelLayout.proposeApp(AppDraft(matchScreen: true))
        XCTAssertEqual(settings.windowLook(on: screen), settings.effectiveLook(on: key), "the screen's look, as a draft")
        settings.panelLayout.proposeApp(AppDraft(appearance: .light))
        XCTAssertNil(settings.windowLook(on: screen))
        XCTAssertEqual(settings.effectiveSettings.appearance, .light)
        XCTAssertEqual(settings.settings.appearance, .system)
    }

    /// A Settings control shows what the app draws, the draft included, and a person's edit through it drops that field
    /// of the draft and writes the settings; the draft's other fields wait.
    func testASettingsControlShowsTheDraftAndAPersonsEditDropsIt() throws {
        let (_, settings, _, _) = try make()
        settings.panelLayout.proposeApp(AppDraft(botLogos: false, delayMs: 700))
        let bots = settings.binding(\.botLogos), delay = settings.doubleBinding(\.hoverDelayMs)
        XCTAssertFalse(bots.wrappedValue, "the control shows the draft")
        XCTAssertEqual(delay.wrappedValue, 700)
        changes = 0
        delay.wrappedValue = 250
        XCTAssertEqual(settings.panelLayout.appDraft, AppDraft(botLogos: false))
        XCTAssertEqual(settings.settings.hoverDelayMs, 250)
        XCTAssertEqual(changes, 1)
        bots.wrappedValue = true
        XCTAssertNil(settings.panelLayout.appDraft, "set to what is saved, the field is dropped all the same")
        XCTAssertTrue(bots.wrappedValue)
    }
}
