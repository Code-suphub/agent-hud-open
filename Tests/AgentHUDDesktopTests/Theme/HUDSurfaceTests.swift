import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// The surface every piece of the HUD stands on (`HUDSurface`): solid as it has always been, glass that runs past the
/// screen edge it stands on and carries its look's tint, a stand-in where nothing is behind to blur, and the island's
/// first look, which replaces the placeholder's without fading.
@MainActor
final class HUDSurfaceTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 60)

    // MARK: The edge it stands on

    /// Liquid Glass runs on past the screen edge a silhouette stands on, so that no rim is lit along it, and only past
    /// that edge: on every other side, and inside the silhouette's own rect, the shape is the island's.
    func testAStandingSurfaceRunsPastTheEdgeItStandsOnOnly() {
        let depth = HUDGlass.bleed
        let expected: [HUDEdge: CGRect] = [
            .top: CGRect(x: 0, y: -depth, width: 200, height: 60 + depth),
            .bottom: CGRect(x: 0, y: 0, width: 200, height: 60 + depth),
            .left: CGRect(x: -depth, y: 0, width: 200 + depth, height: 60),
            .right: CGRect(x: 0, y: 0, width: 200 + depth, height: 60),
        ]
        for (edge, bounds) in expected {
            let island = IslandShape(topRadius: 10, bottomRadius: 16, edge: edge)
            let bled = ContactBleed(base: island, edge: edge, depth: depth).path(in: rect)
            assertEqual(bled.boundingRect, bounds, "\(edge)")
            // Beside a flare, just inside the contact edge, the island leaves the desktop showing, and so does its glass.
            let besideFlare: CGPoint = switch edge {
            case .top: CGPoint(x: 1, y: 5)
            case .bottom: CGPoint(x: 199, y: 55)
            case .left: CGPoint(x: 5, y: 59)
            case .right: CGPoint(x: 195, y: 1)
            }
            XCTAssertFalse(island.path(in: rect).contains(besideFlare), "\(edge)")
            XCTAssertFalse(bled.contains(besideFlare), "\(edge)")
            // Past the edge, off the window, only the glass is.
            let past: CGPoint = switch edge {
            case .top: CGPoint(x: 100, y: -depth / 2)
            case .bottom: CGPoint(x: 100, y: 60 + depth / 2)
            case .left: CGPoint(x: -depth / 2, y: 30)
            case .right: CGPoint(x: 200 + depth / 2, y: 30)
            }
            XCTAssertFalse(island.path(in: rect).contains(past), "\(edge)")
            XCTAssertTrue(bled.contains(past), "\(edge)")
            XCTAssertTrue(bled.contains(CGPoint(x: 100, y: 30)), "\(edge)")
        }
    }

    /// A surface that floats free of the edge, such as a card or the Simple panel, has nothing to run past.
    func testAFloatingSurfaceRunsPastNothing() {
        let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let floating = ContactBleed(base: card, edge: nil, depth: HUDGlass.bleed).path(in: rect)
        assertEqual(floating.boundingRect, card.path(in: rect).boundingRect, "a card")
        let lifted = IslandShape(topRadius: 10, bottomRadius: 12, edge: .top, lift: SimpleMeterConfig.edgeMargin)
        let panel = ContactBleed(base: lifted, edge: nil, depth: HUDGlass.bleed).path(in: rect)
        assertEqual(panel.boundingRect, lifted.path(in: rect).boundingRect, "the Simple panel")
    }

    /// The glass's shape moves with the silhouette's: an island growing into the panel interpolates its radii, and the
    /// glass with it.
    func testTheGlassMovesWithItsShape() {
        var bled = ContactBleed(base: IslandShape(topRadius: 6, bottomRadius: 12, edge: .top), edge: .top, depth: 12)
        XCTAssertEqual(bled.animatableData, AnimatablePair(6, 12))
        bled.animatableData = AnimatablePair(10, 26)
        XCTAssertEqual(bled.base.topRadius, 10)
        XCTAssertEqual(bled.base.bottomRadius, 26)
    }

    // MARK: Glass

    /// Glass is Liquid Glass on macOS 26 in a build made with Xcode 26 or later, and frosted everywhere else.
    func testGlassIsLiquidOnlyOnMacOS26InANewBuild() {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            XCTAssertTrue(HUDGlass.isLiquid)
        } else {
            XCTAssertFalse(HUDGlass.isLiquid)
        }
        #else
        XCTAssertFalse(HUDGlass.isLiquid)
        #endif
    }

    /// A surface keeps its hairline unless it is Liquid Glass, which lights a rim of its own; glass drawn as its stand-in
    /// keeps it, as solid does.
    func testOnlyLiquidGlassLightsItsOwnRim() {
        let hairline = Theme.island.islandOutline
        XCTAssertEqual(HUDLook.standard.outline(hairline, standIn: false), hairline)
        XCTAssertEqual(HUDLook(appearance: .light).outline(hairline, standIn: false), hairline)
        for appearance in [HUDLook.Appearance.dark, .light] {
            let glass = HUDLook(appearance: appearance, material: .glass)
            XCTAssertEqual(glass.outline(hairline, standIn: true), hairline, "\(appearance)")
            XCTAssertEqual(glass.outline(hairline, standIn: false), HUDGlass.isLiquid ? .clear : hairline, "\(appearance)")
        }
    }

    /// Glass is tinted with its look's own surface, thinned: dark glass is darkened and light glass lightened, whatever is
    /// behind. Over the backdrop the HUD's pictures have, the look's text reads on it as on a page.
    func testGlassIsTintedTowardsItsAppearance() throws {
        for theme in [Theme.dark, Theme.light] {
            let tint = try sRGB(theme.glassTint), surface = try sRGB(theme.islandFill)
            XCTAssertEqual(tint.red, surface.red, accuracy: 0.002)
            XCTAssertEqual(tint.green, surface.green, accuracy: 0.002)
            XCTAssertEqual(tint.blue, surface.blue, accuracy: 0.002)
            XCTAssertGreaterThan(tint.alpha, 0.5, "strong enough to hold the ink's contrast")
            XCTAssertLessThan(tint.alpha, 1, "the desktop still shows through")
        }
        let backdrop = try sRGB(HUDPictureRenderer.backdrop).red
        let dark = try over(sRGB(Theme.dark.glassTint), backdrop), light = try over(sRGB(Theme.light.glassTint), backdrop)
        XCTAssertLessThan(dark, backdrop, "dark glass is darker than what is behind it")
        XCTAssertGreaterThan(light, backdrop, "light glass is lighter than what is behind it")
        XCTAssertGreaterThan(try contrast(sRGB(Theme.dark.text).red, dark), 4.5)
        XCTAssertGreaterThan(try contrast(sRGB(Theme.light.text).red, light), 4.5)
    }

    /// Dark glass is dark enough for the HUD's secondary text, its labels, captions and reset times, to read on it over
    /// a white desktop, which its stand-in shows unblurred in a recording.
    func testDarkGlassHoldsItsSecondaryTextOverAWhiteDesktop() throws {
        let overWhite = try over(sRGB(Theme.dark.glassTint), 1)
        XCTAssertGreaterThan(try contrast(sRGB(Theme.dark.secondary).red, overWhite), 3)
        XCTAssertGreaterThan(try contrast(sRGB(Theme.dark.text).red, overWhite), 7)
    }

    /// Light glass is light enough for its own secondary text to read on it over a black desktop, which its stand-in
    /// shows unblurred in a recording: its ink is a grade darker than the solid light HUD's, whose window greys fall to
    /// 2:1 there. Its request card lets the glass show through, as dark glass's does; the solid light card is white.
    func testLightGlassHoldsItsSecondaryTextOverABlackDesktop() throws {
        let overBlack = try over(sRGB(Theme.lightGlass.glassTint), 0)
        XCTAssertGreaterThan(try contrast(sRGB(Theme.lightGlass.secondary).red, overBlack), 3)
        XCTAssertGreaterThan(try contrast(sRGB(Theme.lightGlass.text).red, overBlack), 7)
        XCTAssertLessThan(try contrast(sRGB(Theme.lightIsland.secondary).red, overBlack), 3, "the window's grey does not")
        XCTAssertGreaterThan(try contrast(sRGB(Theme.lightGlass.tertiary).red, over(sRGB(Theme.lightGlass.glassTint), 0.5)),
                             3, "nor its faintest ink over a mid-grey desktop")

        XCTAssertLessThan(try sRGB(Theme.lightGlass.card).alpha, 1)
        XCTAssertGreaterThan(try sRGB(Theme.lightGlass.card).alpha, 0.3)
        XCTAssertEqual(try sRGB(Theme.lightIsland.card).alpha, 1)
    }

    // MARK: Drawn

    /// A solid surface is its fill, as it has always been. Glass where nothing is behind to blur is its stand-in, the
    /// look's tint alone over what the picture has behind it. Neither draws outside its shape.
    func testAPictureDrawsGlassAsItsStandIn() throws {
        let backdrop = try sRGB(HUDPictureRenderer.backdrop).red
        XCTAssertEqual(try drawn(.standard), 0, accuracy: 0.02, "black as ever")
        XCTAssertEqual(try drawn(HUDLook(appearance: .light)), try sRGB(Theme.light.islandFill).red, accuracy: 0.02)

        let dark = HUDLook(appearance: .dark, material: .glass), light = HUDLook(appearance: .light, material: .glass)
        XCTAssertEqual(try drawn(dark), try over(sRGB(Theme.dark.glassTint), backdrop), accuracy: 0.03)
        XCTAssertEqual(try drawn(light), try over(sRGB(Theme.light.glassTint), backdrop), accuracy: 0.03)
        XCTAssertEqual(try drawn(light, at: CGPoint(x: 0, y: 0)), backdrop, accuracy: 0.02, "nothing past the card's corner")
    }

    // MARK: The island's first look

    /// The island starts from a placeholder in the standard look. The first view its screen gives it replaces that look
    /// at once; a later change of look cross-fades.
    func testTheIslandsFirstLookIsNotFadedInto() {
        _ = NSApplication.shared
        let controller = IslandWindowController(frame: CGRect(x: 0, y: 0, width: 216, height: 32), rootView: .placeholder)
        let glass = IslandRootView(store: nil, isOpen: false, collapsedSize: CGSize(width: 216, height: 32),
                                   collapsedTopRadius: NotchGeometry.collapsedTopRadius, collapsedBottomRadius: 12,
                                   look: HUDLook(appearance: .light, material: .glass), lightBorder: false,
                                   onOpenStats: {})
        XCTAssertTrue(glass.animatesLook)
        controller.setRootView(glass)
        XCTAssertFalse(controller.rootView.animatesLook, "the first look is the screen's own, not a change")
        controller.setRootView(.placeholder)
        XCTAssertTrue(controller.rootView.animatesLook, "every later one is")
    }

    // MARK: Helpers

    private struct Components {
        let red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    }

    private func sRGB(_ color: Color, file: StaticString = #filePath, line: UInt = #line) throws -> Components {
        let resolved = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB), file: file, line: line)
        return Components(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent,
                          alpha: resolved.alphaComponent)
    }

    /// A grey's level with `color` laid over it.
    private func over(_ color: Components, _ grey: CGFloat) -> CGFloat {
        color.red * color.alpha + grey * (1 - color.alpha)
    }

    /// WCAG contrast between two greys given as sRGB levels.
    private func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        func luminance(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// The level of grey at `point` (the middle by default) of a card's surface in `look`, drawn off screen over the
    /// HUD pictures' backdrop as a picture draws it, glass as its stand-in.
    private func drawn(_ look: HUDLook, at point: CGPoint? = nil, file: StaticString = #filePath,
                       line: UInt = #line) throws -> CGFloat {
        let size = CGSize(width: 80, height: 40)
        let surface = HUDSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), look: look,
                                 fill: look.theme.islandFill, contact: nil)
            .frame(width: size.width, height: size.height)
            .background(HUDPictureRenderer.backdrop)
            .environment(\.drawsGlassStandIn, true)
        let hosting = NSHostingView(rootView: surface)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), file: file, line: line)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let at = point ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = CGFloat(rep.pixelsWide) / size.width
        let color = try XCTUnwrap(rep.colorAt(x: Int(at.x * scale), y: Int(at.y * scale))?.usingColorSpace(.sRGB),
                                  file: file, line: line)
        return color.redComponent
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 0.01, message, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 0.01, message, file: file, line: line)
    }
}
