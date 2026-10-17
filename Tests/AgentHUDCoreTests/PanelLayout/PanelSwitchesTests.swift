import AgentHUDSupport
import Foundation
import XCTest
@testable import AgentHUDCore

/// The four switches of Settings → Display → Expanded panel as fields of the layout: the sections it hides and its
/// `countdown`, which Settings sets on the saved shared layout, an agent in any draft, a screen's own layout apart, and
/// which settings an earlier version kept are carried into once.
@MainActor
final class PanelSwitchesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "AgentHUDTests.PanelSwitches.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func stored(_ defaults: UserDefaults, _ key: String) -> [String: JSONValue] {
        defaults.data(forKey: key).flatMap { try? JSONValue.parse($0) }?.objectValue ?? [:]
    }

    // MARK: Fields of the layout

    func testTheSwitchesAreTheLayoutsHiddenSectionsAndCountdown() {
        XCTAssertEqual(PanelLayout().switches, PanelSwitches(), "the default view has every switch on")
        let layout = PanelLayout(sections: [.sessions, .tokens], hiddenSections: [.sessions, .blocks], countdown: false)
        XCTAssertEqual(layout.switches, PanelSwitches(sessionList: false, quotaDetails: false, resetCountdown: false, tokenUsage: true))

        var changed = layout
        changed.switches.sessionList = true
        changed.switches.tokenUsage = false
        XCTAssertEqual(changed.normalized(), PanelLayout(sections: [.sessions, .tokens, .blocks], hiddenSections: [.blocks, .tokens],
                                                         countdown: false), "a hidden section keeps its place in the order")
        changed.switches = PanelSwitches()
        XCTAssertEqual(changed.normalized(), PanelLayout(sections: [.sessions, .tokens, .blocks]))
        XCTAssertEqual(try String(decoding: RecordCoding.encoder().encode(PanelLayout(countdown: false)), as: UTF8.self),
                       #"{"countdown":false}"#)
    }

    /// A person's switch sets the saved shared layout at once, the one field it names, and the waiting shared draft
    /// with it, so the panel shows the change either way; it keeps no version, and a screen's own layout keeps its own.
    func testASwitchSetsTheSavedSharedLayoutAndItsDraftAtOnce() {
        let defaults = makeDefaults()
        let store = PanelLayoutStore(defaults: defaults)
        let rings = PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)])
        store.propose(rings)
        store.save()
        store.propose(.own(PanelLayout(order: ["Codex"])), for: "A")
        store.save(.screen("A"))
        store.propose(PanelLayout(blocks: rings.blocks, hiddenSections: [.blocks]))
        let revision = store.revision

        store.setSwitches { $0.tokenUsage = false }
        XCTAssertEqual(store.current, PanelLayout(blocks: rings.blocks, hiddenSections: [.tokens]))
        XCTAssertEqual(store.draft, PanelLayout(blocks: rings.blocks, hiddenSections: [.blocks, .tokens]),
                       "the draft takes the switch too, and keeps its own sections")
        XCTAssertEqual(store.previous, PanelLayout(), "a person's switch is no version")
        XCTAssertEqual(store.effective(for: "A"), PanelLayout(order: ["Codex"]), "a screen with its own layout keeps it")
        XCTAssertEqual(store.revision, revision + 1)
        XCTAssertEqual(store.switches, PanelSwitches(tokenUsage: false), "Settings reads the saved layout")
        XCTAssertEqual(PanelLayoutStore(defaults: defaults).current, store.current, "saved at once")

        store.setSwitches { $0.tokenUsage = false }
        XCTAssertEqual(store.revision, revision + 1, "a switch set as it is changes nothing")
        store.setSwitches { $0.quotaDetails = false }
        XCTAssertEqual(store.current, PanelLayout(blocks: rings.blocks, hiddenSections: [.blocks, .tokens]))
        XCTAssertNil(store.draft, "a draft the switch makes the saved layout is no draft")
        store.setSwitches { $0.resetCountdown = false }
        XCTAssertFalse(store.current.countdown)
        XCTAssertTrue(store.canRevert)
        store.revert()
        XCTAssertEqual(store.current, PanelLayout(), "Revert to Previous goes back to the version before, switches and all")
    }

    // MARK: Before the switches joined the layout

    /// Settings an earlier version wrote, with the four switches among them as it wrote them.
    private func earlierSettings(sessions: Bool = true, quota: Bool = true, countdown: Bool = true, tokens: Bool = true,
                                 in defaults: UserDefaults) {
        let json = #"{"glowRange": 20, "showIslandSessions": \#(sessions), "showIslandQuota": \#(quota), "#
            + #""showResetCountdown": \#(countdown), "showIslandTokens": \#(tokens), "botLogos": false}"#
        defaults.set(Data(json.utf8), forKey: SettingsStore.Keys.settings)
    }

    /// The switches an earlier version kept off are carried into every saved layout, the shared one and each screen's
    /// own, and the ones before them, so that nobody's panel changes; the settings are written again without them, so
    /// they are carried once, and the other settings stay as they were.
    func testTheSwitchesAnEarlierVersionKeptAreCarriedIntoEverySavedLayoutOnce() throws {
        let defaults = makeDefaults()
        let rings = PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)])
        do {
            let earlier = PanelLayoutStore(defaults: defaults)
            earlier.propose(rings)
            earlier.save()
            earlier.propose(PanelLayout(order: ["Codex"]))
            earlier.save()
            earlier.propose(.own(PanelLayout(hiddenSections: [.blocks])), for: "A")
            earlier.save(.screen("A"))
            earlier.propose(.own(PanelLayout(style: PanelStyle(spacing: .compact))), for: "A")
            earlier.save(.screen("A"))
            earlier.propose(.own(PanelLayout()), for: "B")
            earlier.save(.screen("B"))
        }
        earlierSettings(sessions: false, countdown: false, in: defaults)

        let settings = SettingsStore(defaults: defaults)
        let layout = settings.panelLayout
        XCTAssertEqual(layout.current, PanelLayout(order: ["Codex"], hiddenSections: [.sessions], countdown: false))
        XCTAssertEqual(layout.previous, PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .ring)], hiddenSections: [.sessions],
                                                    countdown: false), "Revert to Previous draws what it drew")
        XCTAssertEqual(layout.ownLayout(of: "A"), PanelLayout(hiddenSections: [.sessions], countdown: false,
                                                              style: PanelStyle(spacing: .compact)))
        XCTAssertEqual(layout.previous(of: "A"), .own(PanelLayout(hiddenSections: [.blocks, .sessions], countdown: false)))
        XCTAssertEqual(layout.ownLayout(of: "B"), PanelLayout(hiddenSections: [.sessions], countdown: false))
        XCTAssertEqual(layout.previous(of: "B"), .shared, "a screen that used the shared layout still does")
        XCTAssertEqual(layout.switches, PanelSwitches(sessionList: false, resetCountdown: false))
        XCTAssertEqual(layout.revision, 0, "nothing an agent read has changed")
        XCTAssertFalse(layout.hasDraft)

        let written = stored(defaults, SettingsStore.Keys.settings)
        for key in ["showIslandSessions", "showIslandQuota", "showResetCountdown", "showIslandTokens"] {
            XCTAssertNil(written[key], "\(key) is written no more")
        }
        XCTAssertEqual(settings.settings.glowRange, 20)
        XCTAssertFalse(settings.settings.botLogos)

        // The person turns the session list on again; the next launch has nothing to carry, so it stays on.
        layout.setSwitches { $0.sessionList = true }
        let relaunched = SettingsStore(defaults: defaults).panelLayout
        XCTAssertEqual(relaunched.switches, PanelSwitches(resetCountdown: false))
        XCTAssertEqual(relaunched.ownLayout(of: "A"), PanelLayout(hiddenSections: [.sessions], countdown: false,
                                                                  style: PanelStyle(spacing: .compact)),
                       "the person's switch is the shared layout's alone")
    }

    /// Switches an earlier version kept on, as they were by default, change no layout, and settings this version
    /// wrote carry nothing.
    func testSwitchesLeftOnChangeNoLayout() throws {
        let defaults = makeDefaults()
        let quiet = PanelLayout(hiddenSections: [.tokens])
        let earlier = PanelLayoutStore(defaults: defaults)
        earlier.propose(quiet)
        earlier.save()
        let saved = defaults.data(forKey: SettingsStore.Keys.panelLayout)
        earlierSettings(in: defaults)
        XCTAssertEqual(SettingsStore(defaults: defaults).panelLayout.current, quiet)
        XCTAssertEqual(defaults.data(forKey: SettingsStore.Keys.panelLayout), saved, "nothing to carry, nothing written")
        XCTAssertNil(stored(defaults, SettingsStore.Keys.settings)["showIslandTokens"], "the settings are written without them")

        let fresh = makeDefaults()
        let settings = SettingsStore(defaults: fresh)
        settings.update { $0.glowRange = 18 }
        XCTAssertNil(PanelSwitches.stored(in: fresh.data(forKey: SettingsStore.Keys.settings)))
        XCTAssertEqual(SettingsStore(defaults: fresh).panelLayout.current, PanelLayout(), "the default layout keeps every switch on")
    }

    /// The stored switches are read forgivingly: one missing or not true or false is on, as it was by default.
    func testTheStoredSwitchesAreReadForgivingly() {
        func read(_ json: String) -> PanelSwitches? { PanelSwitches.stored(in: Data(json.utf8)) }
        XCTAssertNil(read("{}"))
        XCTAssertNil(read(#"{"glowRange": 20}"#))
        XCTAssertNil(read("not json"))
        XCTAssertNil(PanelSwitches.stored(in: nil))
        XCTAssertEqual(read(#"{"showIslandQuota": false}"#), PanelSwitches(quotaDetails: false))
        XCTAssertEqual(read(#"{"showIslandTokens": "off", "showResetCountdown": 0, "showIslandSessions": false}"#),
                       PanelSwitches(sessionList: false))
    }

    /// Settings the app cannot read whole are not written over: the switches are carried, and the rest stays for a
    /// person's own change to replace, as before.
    func testUnreadableSettingsAreNotWrittenOver() {
        let defaults = makeDefaults()
        let unreadable = Data(#"{"showIslandQuota": false, "hoverDelayMs": "slow"}"#.utf8)
        defaults.set(unreadable, forKey: SettingsStore.Keys.settings)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.panelLayout.switches, PanelSwitches(quotaDetails: false))
        XCTAssertEqual(defaults.data(forKey: SettingsStore.Keys.settings), unreadable)
    }
}
