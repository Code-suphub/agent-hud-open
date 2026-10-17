import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// What a screen's HUD looks like, and how a look reaches what the HUD draws: its tokens everywhere, and SwiftUI's colour
/// scheme and AppKit's appearance in what is drawn apart from the island, whatever the app is set to, and on the island
/// under every look but the standard one.
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

    /// A light HUD draws with the HUD's own light tokens, opaque as they are; on glass, light or dark, the greys are
    /// tints of the ink (`Theme.under(_:)`), a grade darker on light glass, and dark glass keeps the island's cards.
    func testEachLookDrawsWithItsOwnTokens() {
        XCTAssertEqual(HUDLook(appearance: .light).theme.cardBorder, Theme.lightIsland.cardBorder)
        XCTAssertEqual(HUDLook(appearance: .light).theme.secondary, Theme.light.secondary)
        let lightGlass = HUDLook(appearance: .light, material: .glass).theme
        XCTAssertEqual(lightGlass.secondary, Color.black.opacity(0.65))
        XCTAssertEqual(lightGlass.tertiary, Color.black.opacity(0.53))
        XCTAssertEqual(lightGlass.cardBorder, Theme.lightIsland.cardBorder)
        let darkGlass = HUDLook(appearance: .dark, material: .glass).theme
        XCTAssertEqual(darkGlass.secondary, Color.white.opacity(0.60), "the island's grey on black")
        XCTAssertEqual(darkGlass.card, Theme.island.card)
    }

    /// A box raised over content is drawn nearly opaque: solid at nine tenths at the least, and glass's stand-in at 0.85
    /// at the least, so that what lies beneath never shows through its text; on an opaque look it is whole.
    func testARaisedBoxHasAFloor() throws {
        XCTAssertEqual(HUDLook.standard.raisedCoverOpacity, 1)
        XCTAssertEqual(HUDLook(appearance: .light).raisedCoverOpacity, 1)
        XCTAssertEqual(HUDLook(appearance: .dark, transparency: 0.6).raisedCoverOpacity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(HUDLook(appearance: .dark, transparency: 0.05).raisedCoverOpacity, 0.95, accuracy: 0.0001)
        for (transparency, alpha) in [(0.0, 1.0), (0.6, 0.91), (1, 0.85)] {
            let look = HUDLook(appearance: .light, material: .glass, transparency: transparency)
            let standIn = try XCTUnwrap(NSColor(look.raisedStandIn).usingColorSpace(.sRGB))
            XCTAssertEqual(standIn.alphaComponent, alpha, accuracy: 0.002, "\(transparency)")
        }
    }

    /// A heatmap's empty cell is a tint of the ink, so that the grid holds on any ground; a busy cell is the green ramp on
    /// an opaque ground and the theme's green over a see-through one, thicker as the value rises.
    func testAHeatmapCellFollowsItsGround() throws {
        // Compared by their sRGB components: two equal colours can be built in different spaces, which `Color`'s own
        // equality tells apart though they print the same.
        func same(_ a: Color, _ b: Color, _ what: String, line: UInt = #line) throws {
            let x = try XCTUnwrap(NSColor(a).usingColorSpace(.sRGB)), y = try XCTUnwrap(NSColor(b).usingColorSpace(.sRGB))
            for (p, q) in [(x.redComponent, y.redComponent), (x.greenComponent, y.greenComponent),
                           (x.blueComponent, y.blueComponent), (x.alphaComponent, y.alphaComponent)] {
                XCTAssertEqual(p, q, accuracy: 0.002, what, line: line)
            }
        }
        try same(HeatmapCard.color(for: 0, theme: .dark), Color.white.opacity(0.06), "an empty cell on dark")
        try same(HeatmapCard.color(for: 0, theme: .light), Color.black.opacity(0.075), "an empty cell on light")
        let glass = HUDLook(appearance: .dark, material: .glass, transparency: 0.3).theme
        try same(HeatmapCard.color(for: 1, theme: glass), glass.status(.ok).opacity(1), "the busiest cell on glass")
        try same(HeatmapCard.color(for: 0.25, theme: glass), glass.status(.ok).opacity(0.6), "a quarter on glass")
        XCTAssertNotEqual(HeatmapCard.color(for: 1, theme: .dark), Theme.dark.status(.ok), "the ramp, opaque")
    }

    /// A screen whose settings choose no look gives its HUD the standard one (`HUDLookResolutionTests`).
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

    /// What AppKit chooses itself on the island, such as the scroller, a text field's caret and a template image, follows
    /// the island's hosting view, which takes a light or glass look's appearance whatever the app is set to, and again
    /// when the look changes. Under the standard look it takes none, and leaves them to the app as it always has. The
    /// window itself keeps none of its own.
    func testTheIslandTakesItsLooksAppearance() throws {
        _ = NSApplication.shared
        let controller = IslandWindowController(frame: CGRect(x: 0, y: 0, width: 216, height: 32), rootView: .placeholder)
        let hosting = try XCTUnwrap(controller.panel.contentView)
        XCTAssertNil(hosting.appearance)
        XCTAssertNil(controller.panel.appearance)

        func island(_ look: HUDLook) -> IslandRootView {
            IslandRootView(store: nil, isOpen: false, collapsedSize: CGSize(width: 216, height: 32),
                           collapsedTopRadius: NotchGeometry.collapsedTopRadius, collapsedBottomRadius: 12,
                           look: look, lightBorder: false, onOpenStats: {})
        }
        controller.setRootView(island(HUDLook(appearance: .light)))
        XCTAssertEqual(hosting.appearance?.name, .aqua)
        controller.setRootView(island(HUDLook(appearance: .dark, material: .glass)))
        XCTAssertEqual(hosting.appearance?.name, .darkAqua)
        controller.setRootView(.placeholder)
        XCTAssertNil(hosting.appearance)
    }

    /// The island under the standard look sets its colours and leaves its colour scheme to the app, as it always has, so
    /// a mark's artwork is the one it always drew. Every other look draws in its own scheme, whatever the app is set to.
    func testTheStandardIslandLeavesItsSchemeToTheApp() {
        let seen = Seen()
        for (appearance, scheme) in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark)] {
            let standard = NSHostingView(rootView: Probe(seen: seen).islandLook(.standard))
            standard.appearance = NSAppearance(named: appearance)
            _ = standard.fittingSize
            XCTAssertEqual(seen.scheme, scheme, "\(appearance)")
            XCTAssertEqual(seen.look, .standard)
            XCTAssertEqual(seen.text, Theme.island.text)
        }

        let darkGlass = NSHostingView(rootView: Probe(seen: seen).islandLook(HUDLook(appearance: .dark, material: .glass)))
        darkGlass.appearance = NSAppearance(named: .aqua)
        _ = darkGlass.fittingSize
        XCTAssertEqual(seen.scheme, .dark)
        let light = NSHostingView(rootView: Probe(seen: seen).islandLook(HUDLook(appearance: .light)))
        light.appearance = NSAppearance(named: .darkAqua)
        _ = light.fittingSize
        XCTAssertEqual(seen.scheme, .light)
        XCTAssertEqual(seen.text, Theme.light.text)
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
