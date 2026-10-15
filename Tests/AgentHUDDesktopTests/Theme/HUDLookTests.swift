import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// What a screen's HUD looks like, and how a look reaches what the HUD draws: its tokens everywhere, and SwiftUI's colour
/// scheme and AppKit's appearance in what is drawn apart from the island, whatever the app is set to.
@MainActor
final class HUDLookTests: XCTestCase {
    /// The standard look is the HUD as it has always been drawn: the island's dark tokens, dark controls and artwork.
    func testTheStandardLookIsTheDarkIsland() {
        let look = HUDLook.standard
        XCTAssertEqual(look.appearance, .dark)
        XCTAssertEqual(look.colorScheme, .dark)
        XCTAssertEqual(look.appearanceName, .darkAqua)
        XCTAssertEqual(look.theme.text, Theme.island.text)
        XCTAssertEqual(look.theme.islandFill, Theme.island.islandFill)

        let light = HUDLook(appearance: .light)
        XCTAssertEqual(light.colorScheme, .light)
        XCTAssertEqual(light.appearanceName, .aqua)
        XCTAssertEqual(light.theme.text, Theme.light.text)
        XCTAssertEqual(light.theme.islandFill, Theme.light.islandFill)
    }

    /// Every screen's settings give its HUD the standard look: none of them chooses another yet.
    func testEveryScreenHasTheStandardLook() {
        let suite = "app.agenthud.tests.hud-look.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!, defaultAgents: DemoData.agents)
        XCTAssertEqual(settings.effectiveLook(on: "screen:a"), .standard)
        XCTAssertEqual(settings.effectiveLook(on: ""), .standard)
    }

    /// The HUD's dark tokens are the very colours the HUD drew with before it had any: nothing changes on screen.
    func testTheIslandsTokensAreTheColoursTheHUDDrewWith() {
        let island = Theme.island
        XCTAssertEqual(island.islandFill, Color.black)
        XCTAssertEqual(island.restingFillOpacity, 0.82)
        XCTAssertEqual(island.islandOutline, Color.white.opacity(0.14))
        XCTAssertEqual(island.desktopOutline, Color.white.opacity(0.18))
        XCTAssertEqual(island.meterTrack, Color.white.opacity(0.14))
        XCTAssertEqual(island.alertText, Color.white)
        XCTAssertEqual(island.inverseText, Color.black)
        XCTAssertEqual(island.onAccent, Color.black)
        XCTAssertEqual(island.raisedSurface, island.windowBackground)
    }

    /// What the panel and the request cards took from the status palette and the island's constants before they read
    /// a look, the standard look gives them unchanged.
    func testTheStandardLookGivesThePanelAndTheCardsTheirColours() {
        let theme = HUDLook.standard.theme
        for level in StatusLevel.allCases {
            XCTAssertEqual(theme.status(level), Color(StatusPalette.color(for: level)), "\(level)")
        }
        let color = PermissionColor(theme)
        XCTAssertEqual(color.text, Theme.island.text)
        XCTAssertEqual(color.secondary, Theme.island.secondary)
        XCTAssertEqual(color.tertiary, Theme.island.tertiary)
        XCTAssertEqual(color.surface, Theme.island.card)
        XCTAssertEqual(color.inset, Theme.island.rowBackground)
        XCTAssertEqual(color.border, Theme.island.cardBorder)
        XCTAssertEqual(color.highlight, Theme.island.segmentBackground)
        XCTAssertEqual(color.onAllow, Color.black)
        XCTAssertEqual(color.signal, Color(IslandAlert.warningAccent))
        XCTAssertEqual(color.allow, Color(StatusPalette.ok))
        XCTAssertEqual(color.deny, Color(StatusPalette.critical))
    }

    /// A view drawn in a look apart from the island, such as a picture or a hover popover's details, takes its theme and
    /// its colour scheme from it, even in a window set to the other one.
    func testAViewDrawnInALookTakesItsThemeAndScheme() {
        let seen = Seen()
        let hosting = NSHostingView(rootView: Probe(seen: seen).hudLook(.standard))
        hosting.appearance = NSAppearance(named: .aqua)
        _ = hosting.fittingSize
        XCTAssertEqual(seen.scheme, .dark, "a dark picture in a light window draws dark")
        XCTAssertEqual(seen.look, .standard)
        XCTAssertEqual(seen.text, Theme.island.text)

        let light = NSHostingView(rootView: Probe(seen: seen).hudLook(HUDLook(appearance: .light)))
        light.appearance = NSAppearance(named: .darkAqua)
        _ = light.fittingSize
        XCTAssertEqual(seen.scheme, .light)
        XCTAssertEqual(seen.text, Theme.light.text)
    }

    /// Outside any look a view has the standard one, so a piece of the HUD drawn on its own is drawn as it always was.
    func testAViewOutsideALookHasTheStandardOne() {
        let seen = Seen()
        _ = NSHostingView(rootView: Probe(seen: seen)).fittingSize
        XCTAssertEqual(seen.look, .standard)
        XCTAssertEqual(seen.text, Theme.island.text)
    }

    /// The island takes only its look's colours. Its window, and with it what AppKit and SwiftUI choose themselves on it,
    /// such as a mark's artwork, the scroller and a text field's caret, keep the app's appearance, as they always have.
    func testTheIslandKeepsTheAppsAppearance() throws {
        _ = NSApplication.shared
        let controller = IslandWindowController(frame: CGRect(x: 0, y: 0, width: 216, height: 32), rootView: .placeholder)
        controller.setRootView(.placeholder)
        let hosting = try XCTUnwrap(controller.panel.contentView)
        XCTAssertNil(hosting.appearance)
        XCTAssertNil(controller.panel.appearance)
    }

    /// A text field on a card is AppKit's, which the look's colour scheme does not reach: it inks its text and its
    /// placeholder for the look of the HUD it is on, and again when that look changes.
    func testAnIslandTextFieldInksItsTextForTheLook() throws {
        func card(_ look: HUDLook) -> some View {
            IslandTextField(text: "", placeholder: "Type your own answer", onChange: { _ in }, onSubmit: {}, onTyping: { _ in })
                .frame(width: 200, height: 20)
                .hudLook(look)
        }
        let hosting = NSHostingView(rootView: card(.standard))
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 20)
        hosting.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(fields(in: hosting).first)
        XCTAssertTrue(field.textColor.map { same($0, Theme.island.text) } ?? false, "\(String(describing: field.textColor))")

        hosting.rootView = card(HUDLook(appearance: .light))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(field.textColor.map { same($0, Theme.light.text) } ?? false, "\(String(describing: field.textColor))")
        let placeholder = field.placeholderAttributedString?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertTrue(placeholder.map { same($0, Theme.light.tertiary) } ?? false, "\(String(describing: placeholder))")
    }

    private func fields(in view: NSView) -> [KeyboardField] {
        view.subviews.flatMap { ($0 as? KeyboardField).map { [$0] } ?? fields(in: $0) }
    }

    /// Whether AppKit's colour is the token's, compared in sRGB.
    private func same(_ color: NSColor, _ token: Color) -> Bool {
        guard let a = color.usingColorSpace(.sRGB), let b = NSColor(token).usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.002 && abs(a.greenComponent - b.greenComponent) < 0.002
            && abs(a.blueComponent - b.blueComponent) < 0.002 && abs(a.alphaComponent - b.alphaComponent) < 0.002
    }
}

/// What a probe last read from its environment.
private final class Seen {
    var scheme: ColorScheme?
    var look: HUDLook?
    var text: Color?
}

private struct Probe: View {
    let seen: Seen
    @Environment(\.colorScheme) private var scheme
    @Environment(\.hudLook) private var look
    @Environment(\.hudTheme) private var theme

    var body: some View {
        seen.scheme = scheme
        seen.look = look
        seen.text = theme.text
        return Color.clear.frame(width: 10, height: 10)
    }
}
