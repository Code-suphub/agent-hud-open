import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// The surface every piece of the HUD stands on (`HUDSurface`): solid as it has always been, glass that runs past the
/// screen edge it stands on and is covered with its look's own surface at the screen's transparency, a stand-in where
/// nothing is behind to blur, and the island's first look, which replaces the placeholder's without fading.
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

    /// Glass is covered with its look's own surface, which the theme gives opaque, at the opacity the transparency
    /// leaves it: whole at 0, under three quarters at the standard transparency, and still half at the range's top,
    /// where the desktop shows through most: thinner, either look's glass turns the mid-grey of the other over a
    /// desktop of the other shade. A dark cover darkens and a light one lightens what is behind, whatever it is.
    func testGlassIsCoveredWithItsSurfaceAtTheTransparency() throws {
        for (appearance, theme) in [(HUDLook.Appearance.dark, Theme.dark), (.light, Theme.light)] {
            let tint = try sRGB(theme.glassTint), surface = try sRGB(theme.islandFill)
            XCTAssertEqual(tint.red, surface.red, accuracy: 0.002, "\(appearance)")
            XCTAssertEqual(tint.green, surface.green, accuracy: 0.002, "\(appearance)")
            XCTAssertEqual(tint.blue, surface.blue, accuracy: 0.002, "\(appearance)")
            XCTAssertEqual(tint.alpha, 1, accuracy: 0.002, "the transparency alone thins it")
            for (transparency, alpha) in [(0.0, 1.0), (ScreenPlacement.standardGlassTransparency, 0.725), (0.9, 0.505)] {
                let cover = try sRGB(HUDLook(appearance: appearance, material: .glass, transparency: transparency).glassCover)
                XCTAssertEqual(cover.red, surface.red, accuracy: 0.002, "\(appearance) \(transparency)")
                XCTAssertEqual(cover.blue, surface.blue, accuracy: 0.002, "\(appearance) \(transparency)")
                XCTAssertEqual(cover.alpha, alpha, accuracy: 0.002, "\(appearance) \(transparency)")
            }
        }
        let backdrop = try sRGB(HUDPictureRenderer.backdrop).red
        let dark = try over(sRGB(Self.darkGlass.glassCover), backdrop)
        let light = try over(sRGB(Self.lightGlass.glassCover), backdrop)
        XCTAssertLessThan(dark, backdrop, "dark glass is darker than what is behind it")
        XCTAssertGreaterThan(light, backdrop, "light glass is lighter than what is behind it")
    }

    /// The transparency thins the glass's frost as well as its cover, so that the desktop comes through sharper: all of
    /// the frost with no transparency, half at the standard one, a tenth at the most. Thinning the cover alone left a
    /// window behind the HUD blurred into an even tone, light glass over a white window plain white at any setting.
    func testTheTransparencyThinsTheFrost() {
        for appearance in [HUDLook.Appearance.dark, .light] {
            for (transparency, frost) in [(0.0, 1.0), (ScreenPlacement.standardGlassTransparency, 0.5), (0.9, 0.1)] {
                let look = HUDLook(appearance: appearance, material: .glass, transparency: transparency)
                XCTAssertEqual(look.glassFrost, frost, accuracy: 0.0001, "\(appearance) \(transparency)")
            }
        }
    }

    /// At the standard transparency the look's text reads on its glass over the backdrop the HUD's pictures have as on
    /// a page, about 17:1 on dark glass and 9:1 on light glass, and over a desktop of the other shade, which a recording
    /// shows unblurred, about 8.6:1 for dark glass over white and 7.9:1 for light glass over black. At the most
    /// transparency the look's text still holds 3:1 there.
    func testGlassHoldsItsTextAtTheStandardTransparency() throws {
        let backdrop = try sRGB(HUDPictureRenderer.backdrop).red
        let dark = try sRGB(Self.darkGlass.glassCover), light = try sRGB(Self.lightGlass.glassCover)
        let darkText = try sRGB(Self.darkGlass.theme.text).red, lightText = try sRGB(Self.lightGlass.theme.text).red
        XCTAssertGreaterThan(contrast(darkText, over(dark, backdrop)), 4.5)
        XCTAssertGreaterThan(contrast(lightText, over(light, backdrop)), 4.5)
        XCTAssertGreaterThan(contrast(darkText, over(dark, 1)), 7, "dark glass over a white desktop")
        XCTAssertGreaterThan(contrast(lightText, over(light, 0)), 7, "light glass over a black desktop")
        let top = ScreenPlacement.glassTransparencyRange.upperBound
        let thinDark = try sRGB(HUDLook(appearance: .dark, material: .glass, transparency: top).glassCover)
        let thinLight = try sRGB(HUDLook(appearance: .light, material: .glass, transparency: top).glassCover)
        XCTAssertGreaterThan(contrast(darkText, over(thinDark, 1)), 3, "dark glass at its most transparent over white")
        XCTAssertGreaterThan(contrast(lightText, over(thinLight, 0)), 3, "light glass at its most transparent over black")
        XCTAssertGreaterThan(try contrast(sRGB(Self.darkGlass.theme.secondary).red, over(dark, backdrop)), 4.5,
                             "dark glass's secondary text over the backdrop")
    }

    /// The less transparent the glass, the more its own surface holds the ink to the look over a desktop of the other
    /// shade, and at 0 the glass reads as the solid surface does: its secondary text too, labels, captions and reset
    /// times, which bare glass would leave unread.
    func testLessTransparentGlassHoldsMoreContrast() throws {
        for appearance in [HUDLook.Appearance.dark, .light] {
            let desktop: CGFloat = appearance == .dark ? 1 : 0
            func text(at transparency: Double, _ ink: KeyPath<Theme, Color> = \.text) throws -> CGFloat {
                let look = HUDLook(appearance: appearance, material: .glass, transparency: transparency)
                return try contrast(sRGB(look.theme[keyPath: ink]).red, over(sRGB(look.glassCover), desktop))
            }
            let range = ScreenPlacement.glassTransparencyRange
            let steps = stride(from: range.lowerBound, through: range.upperBound, by: 0.1).map { $0 }
            let contrasts = try steps.map { try text(at: $0) }
            XCTAssertEqual(contrasts, contrasts.sorted(by: >), "\(appearance)")
            XCTAssertGreaterThan(try text(at: 0, \.secondary), 3, "\(appearance) secondary at 0")
            XCTAssertGreaterThan(try text(at: 0), 7, "\(appearance) at 0")
        }
        // Light glass's ink is a grade darker than the solid light HUD's, whose window greys fall short over a black
        // desktop through the same cover. Its request card lets the glass show through, as dark glass's does; the solid
        // light card is white.
        let cover = try over(sRGB(Self.lightGlass.glassCover), 0)
        XCTAssertGreaterThan(try contrast(sRGB(Theme.lightGlass.secondary).red, cover),
                             try contrast(sRGB(Theme.lightIsland.secondary).red, cover))
        XCTAssertLessThan(try sRGB(Theme.lightGlass.card).alpha, 1)
        XCTAssertGreaterThan(try sRGB(Theme.lightGlass.card).alpha, 0.3)
        XCTAssertEqual(try sRGB(Theme.lightIsland.card).alpha, 1)
    }

    // MARK: Drawn

    /// A solid surface is its fill, as it has always been. Glass where nothing is behind to blur is its stand-in, the
    /// look's cover alone over what the picture has behind it, as thin as the transparency leaves it. Neither draws
    /// outside its shape. The cover is compared with itself drawn the same way over the backdrop, since the drawing
    /// blends in a colour space of its own, a few hundredths off a blend in sRGB at half cover.
    func testAPictureDrawsGlassAsItsStandIn() throws {
        let backdrop = try sRGB(HUDPictureRenderer.backdrop).red
        XCTAssertEqual(try drawn(.standard), 0, accuracy: 0.02, "black as ever")
        XCTAssertEqual(try drawn(HUDLook(appearance: .light)), try sRGB(Theme.light.islandFill).red, accuracy: 0.02)

        let dark = Self.darkGlass, light = Self.lightGlass
        XCTAssertEqual(try drawn(dark), try drawn(cover: dark.glassCover), accuracy: 0.01)
        XCTAssertEqual(try drawn(light), try drawn(cover: light.glassCover), accuracy: 0.01)
        XCTAssertEqual(try drawn(dark), try over(sRGB(dark.glassCover), backdrop), accuracy: 0.05)
        XCTAssertEqual(try drawn(light), try over(sRGB(light.glassCover), backdrop), accuracy: 0.05)
        XCTAssertEqual(try drawn(light, at: CGPoint(x: 0, y: 0)), backdrop, accuracy: 0.02, "nothing past the card's corner")
        let thin = HUDLook(appearance: .light, material: .glass, transparency: 0.8)
        XCTAssertEqual(try drawn(thin), try drawn(cover: thin.glassCover), accuracy: 0.01)
        XCTAssertLessThan(try drawn(thin), try drawn(light) - 0.1, "more of the backdrop shows through")
        let whole = HUDLook(appearance: .light, material: .glass, transparency: 0)
        XCTAssertEqual(try drawn(whole), try sRGB(Theme.light.islandFill).red, accuracy: 0.02, "the surface itself")
    }

    /// A Settings preview draws glass as Liquid Glass where the HUD has it, which takes in the wallpaper painted behind
    /// it in the window, and as its stand-in over the wallpaper where glass is frosted, which would blur the desktop
    /// behind the window instead.
    func testASettingsPreviewDrawsLiquidGlassWhereTheHUDHasIt() {
        let seen = StandInSeen()
        let preview = NSHostingView(rootView: SettingsPreview { StandInProbe(seen: seen) })
        preview.frame = CGRect(x: 0, y: 0, width: 200, height: 80)
        preview.layoutSubtreeIfNeeded()
        XCTAssertEqual(seen.standIn, !HUDGlass.isLiquid)
        _ = NSHostingView(rootView: StandInProbe(seen: seen)).fittingSize
        XCTAssertEqual(seen.standIn, false, "outside a preview glass is drawn as glass")
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

    /// Glass of each appearance at the standard transparency, as a screen that chooses Glass first has it.
    private static let darkGlass = HUDLook(appearance: .dark, material: .glass)
    private static let lightGlass = HUDLook(appearance: .light, material: .glass)

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

    /// The level of grey in the middle of `cover` laid over the HUD pictures' backdrop, drawn as `drawn(_:)` draws.
    private func drawn(cover: Color, file: StaticString = #filePath, line: UInt = #line) throws -> CGFloat {
        let size = CGSize(width: 80, height: 40)
        let hosting = NSHostingView(rootView: cover.frame(width: size.width, height: size.height)
            .background(HUDPictureRenderer.backdrop))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), file: file, line: line)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let color = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB),
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

/// What a probe last read of whether glass is drawn as its stand-in.
private final class StandInSeen {
    var standIn: Bool?
}

private struct StandInProbe: View {
    let seen: StandInSeen
    @Environment(\.drawsGlassStandIn) private var standIn

    var body: some View {
        seen.standIn = standIn
        return Color.clear.frame(width: 10, height: 10)
    }
}
