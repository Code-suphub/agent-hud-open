import AgentHUDCore
import AppKit
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

/// The surface every piece of the HUD stands on (`HUDSurface`): solid as it has always been, the system's own glass,
/// whole at any transparency over a dimming layer in the look's colour, that runs past the screen edge it stands on, a
/// stand-in where nothing is behind to blur, and the island's first look, which replaces the placeholder's without
/// fading.
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

    /// A surface keeps its hairline unless it is Liquid Glass, clear or regular, which lights a rim of its own; glass
    /// drawn as its stand-in keeps it, as solid does.
    func testOnlyLiquidGlassLightsItsOwnRim() {
        let hairline = Theme.island.islandOutline
        XCTAssertEqual(HUDLook.standard.outline(hairline, standIn: false), hairline)
        XCTAssertEqual(HUDLook(appearance: .light).outline(hairline, standIn: false), hairline)
        for appearance in [HUDLook.Appearance.dark, .light] {
            for style in [HUDGlassStyle.clear, .regular] {
                let glass = HUDLook(appearance: appearance, material: .glass, glassStyle: style)
                XCTAssertEqual(glass.outline(hairline, standIn: true), hairline, "\(appearance) \(style)")
                XCTAssertEqual(glass.outline(hairline, standIn: false), HUDGlass.isLiquid ? .clear : hairline,
                               "\(appearance) \(style)")
            }
        }
    }

    /// Beneath glass lies a dimming layer, as Apple asks of clear glass to keep what is on it legible: the look's own
    /// colour, which the theme gives opaque, black beneath dark glass and near-white beneath light glass, at what the
    /// screen's Transparency leaves of it: all of it at 0, half at the standard 0.5 and none at 1, where the HUD is the
    /// system's bare glass. It is the same whatever the glass is made of. The glass itself is never faded, and no solid
    /// cover is drawn with it; a solid look has no dimming layer.
    func testTheDimmingBeneathGlassIsTheLooksColourAtWhatTheTransparencyLeaves() throws {
        for (appearance, theme) in [(HUDLook.Appearance.dark, Theme.dark), (.light, Theme.light)] {
            let tint = try sRGB(theme.glassTint), surface = try sRGB(theme.islandFill)
            XCTAssertEqual(tint.red, surface.red, accuracy: 0.002, "\(appearance)")
            XCTAssertEqual(tint.green, surface.green, accuracy: 0.002, "\(appearance)")
            XCTAssertEqual(tint.blue, surface.blue, accuracy: 0.002, "\(appearance)")
            XCTAssertEqual(tint.alpha, 1, accuracy: 0.002, "\(appearance): opaque, thinned by the transparency alone")
            for style in HUDGlassStyle.allCases {
                for transparency in stride(from: 0.0, through: 1, by: 0.1) {
                    let glass = HUDLook(appearance: appearance, material: .glass, transparency: transparency,
                                        glassStyle: style)
                    let what = "\(appearance) \(style) \(transparency)"
                    XCTAssertEqual(glass.dimmingOpacity, 1 - transparency, accuracy: 0.0001, what)
                    let dimming = try sRGB(glass.glassDimming)
                    XCTAssertEqual(dimming.alpha, 1 - transparency, accuracy: 0.002, what)
                    if dimming.alpha > 0.01 {
                        XCTAssertEqual(dimming.red, surface.red, accuracy: 0.002, what)
                        XCTAssertEqual(dimming.blue, surface.blue, accuracy: 0.002, what)
                    }
                    XCTAssertEqual(glass.coverOpacity, 0, "\(what): no solid cover")
                }
            }
            XCTAssertEqual(HUDLook(appearance: appearance, transparency: 0.4).dimmingOpacity, 0, "\(appearance): solid")
        }
        XCTAssertEqual(HUDLook.standard.dimmingOpacity, 0)
        XCTAssertEqual(Self.darkGlass.dimmingOpacity, 0.5, "half of it at the standard transparency")
    }

    /// Glass's Transparency runs from 0, the look's colour whole beneath the glass, to 1, the bare glass, and a screen
    /// that chooses Glass starts at 0.5, glass that is plainly dark or light and plainly glass. A solid surface has no
    /// blur under it to hold what shows through together: its Transparency stops at 0.9 and takes away 0.55 of its fill
    /// at the most, so that 0.505 of it is left there, never under half; a solid screen asked for more, as a style may
    /// ask, draws its own top.
    func testGlassRunsToTheBareGlassWhileSolidKeepsHalf() {
        XCTAssertEqual(ScreenPlacement.glassTransparencyRange, 0...1)
        XCTAssertEqual(ScreenPlacement.standardGlassTransparency, 0.5)
        XCTAssertEqual(ScreenPlacement.solidTransparencyRange, 0...0.9)
        XCTAssertEqual(ScreenPlacement.standardSolidTransparency, 0)
        XCTAssertEqual(HUDLook.solidFillGivenUp, 0.55)
        for appearance in [HUDLook.Appearance.dark, .light] {
            for transparency in stride(from: 0.0, through: 0.9, by: 0.1) {
                XCTAssertEqual(HUDLook(appearance: appearance, transparency: transparency).coverOpacity,
                               1 - transparency * 0.55, accuracy: 0.0001, "\(appearance) \(transparency)")
            }
            XCTAssertEqual(HUDLook(appearance: appearance).coverOpacity, 1, "\(appearance): opaque at first")
            let top = HUDLook(appearance: appearance, transparency: ScreenPlacement.solidTransparencyRange.upperBound)
            XCTAssertEqual(top.coverOpacity, 0.505, accuracy: 0.0001, "\(appearance)")
            XCTAssertGreaterThanOrEqual(top.coverOpacity, 0.5, "\(appearance): a solid surface keeps half")
        }
        var placement = ScreenPlacement(material: .solid)
        placement.transparency = 1
        let drawn = HUDLook(drawing: placement, systemIsLight: false, reducesTransparency: false)
        XCTAssertEqual(drawn.transparency, ScreenPlacement.solidTransparencyRange.upperBound)
        XCTAssertEqual(drawn.coverOpacity, 0.505, accuracy: 0.0001)
    }

    /// Where nothing is behind to blur, glass stands in as the look's own surface, as much of it as the dimming layer
    /// has and never less than 0.35, which glass over a mid-grey backdrop reads as, so that a picture of bare glass
    /// still holds the HUD's ink: opaque at 0, 0.675 at the standard 0.5, and 0.35 at 1, whatever the glass is made of.
    /// The notch's row stands in at 0.87 of black, its glass dimmed four fifths, whatever the screen's Transparency.
    func testGlassStandsInAsItsDimmingNeverUnderAThird() throws {
        XCTAssertEqual(HUDLook.standInFloor, 0.35)
        for (appearance, theme) in [(HUDLook.Appearance.dark, Theme.dark), (.light, Theme.light)] {
            let surface = try sRGB(theme.islandFill)
            for (transparency, share) in [(0.0, 1.0), (ScreenPlacement.standardGlassTransparency, 0.675), (1.0, 0.35)] {
                for style in HUDGlassStyle.allCases {
                    let look = HUDLook(appearance: appearance, material: .glass, transparency: transparency,
                                       glassStyle: style)
                    let what = "\(appearance) \(style) \(transparency)"
                    let standIn = try sRGB(look.glassStandIn)
                    XCTAssertEqual(standIn.alpha, share, accuracy: 0.002, what)
                    XCTAssertEqual(standIn.red, surface.red, accuracy: 0.002, what)
                    XCTAssertEqual(standIn.blue, surface.blue, accuracy: 0.002, what)
                    let row = try sRGB(look.inNotchRow.glassStandIn)
                    XCTAssertEqual(row.red, 0, accuracy: 0.002, "\(what): the notch's row, black")
                    XCTAssertEqual(row.alpha, 0.87, accuracy: 0.002, what)
                }
            }
        }
    }

    /// At the standard transparency, 0.5, the stand-in holds the look's text over the backdrop the HUD's pictures have
    /// as on a page, measured on the picture as drawn: about 17.8:1 on dark glass and 9.0:1 on light glass, and the
    /// secondary text, labels, captions and reset times, about 6.7:1 and 4.0:1. The floors leave room for a drawing
    /// that blends as sRGB does, where light glass's secondary text holds 3.7:1. Light glass's secondary ink is a grade
    /// darker than the solid light HUD's, whose grey holds about 2.7:1 there. What the glass holds on screen is the
    /// system's to say: it turns light over a light desktop and dark over a dark one, less so the more of the dimming
    /// layer the Transparency leaves, and the HUD's fixed ink reads less well over a desktop of the other shade, which
    /// nothing here asks it to hold.
    func testTheStandInHoldsItsTextOverThePicturesBackdrop() throws {
        let dark = try drawn(Self.darkGlass), light = try drawn(Self.lightGlass)
        func ink(_ color: Color) throws -> CGFloat { try sRGB(color).red }
        XCTAssertGreaterThan(contrast(try ink(Self.darkGlass.theme.text), dark), 17, "dark glass")
        XCTAssertGreaterThan(contrast(try ink(Self.lightGlass.theme.text), light), 8, "light glass")
        XCTAssertGreaterThan(contrast(try ink(Self.darkGlass.theme.secondary), dark), 6.3, "dark glass's secondary")
        XCTAssertGreaterThan(contrast(try ink(Self.lightGlass.theme.secondary), light), 3.5, "light glass's secondary")
        XCTAssertGreaterThan(contrast(try ink(Theme.lightGlass.secondary), light),
                             contrast(try ink(Theme.lightIsland.secondary), light) + 1, "a grade darker than solid's")
        // Light glass's request card lets the glass show through, as dark glass's does; the solid light card is white.
        XCTAssertLessThan(try sRGB(Theme.lightGlass.card).alpha, 1)
        XCTAssertGreaterThan(try sRGB(Theme.lightGlass.card).alpha, 0.3)
        XCTAssertEqual(try sRGB(Theme.lightIsland.card).alpha, 1)
    }

    // MARK: Drawn

    /// A solid surface is its fill, as it has always been. Glass where nothing is behind to blur is its stand-in over
    /// what the picture has behind it: the look's own surface whole at 0, 0.675 of it at the standard 0.5, darker than
    /// the backdrop for dark glass and lighter for light glass, thinner as the Transparency rises, and a third of it at
    /// 1, still dark or light; the notch's row 0.87 black at any transparency. Neither draws outside its shape. The
    /// stand-in is compared with itself drawn the same way over the backdrop, since the drawing blends in a colour
    /// space of its own, a few hundredths off a blend in sRGB.
    func testAPictureDrawsGlassAsItsStandIn() throws {
        let backdrop = try sRGB(HUDPictureRenderer.backdrop).red
        let lightSurface = try sRGB(Theme.light.islandFill).red
        XCTAssertEqual(try drawn(.standard), 0, accuracy: 0.02, "black as ever")
        XCTAssertEqual(try drawn(HUDLook(appearance: .light)), lightSurface, accuracy: 0.02)

        let dark = Self.darkGlass, light = Self.lightGlass
        XCTAssertEqual(try drawn(dark), try drawn(standIn: dark.glassStandIn), accuracy: 0.01)
        XCTAssertEqual(try drawn(light), try drawn(standIn: light.glassStandIn), accuracy: 0.01)
        XCTAssertEqual(try drawn(dark), try over(sRGB(dark.glassStandIn), backdrop), accuracy: 0.05)
        XCTAssertEqual(try drawn(light), try over(sRGB(light.glassStandIn), backdrop), accuracy: 0.05)
        XCTAssertLessThan(try drawn(dark), backdrop - 0.1, "dark glass is darker than what is behind it")
        XCTAssertGreaterThan(try drawn(light), backdrop + 0.4, "light glass is lighter than what is behind it")
        XCTAssertLessThan(try drawn(light), lightSurface - 0.1, "short of the light surface itself")
        XCTAssertEqual(try drawn(light, at: CGPoint(x: 0, y: 0)), backdrop, accuracy: 0.02, "nothing past the card's corner")
        let whole = HUDLook(appearance: .light, material: .glass, transparency: 0)
        XCTAssertEqual(try drawn(whole), lightSurface, accuracy: 0.02, "the surface itself")
        let thin = HUDLook(appearance: .light, material: .glass, transparency: 0.8)
        XCTAssertEqual(try drawn(thin), try drawn(standIn: thin.glassStandIn), accuracy: 0.01)
        XCTAssertLessThan(try drawn(thin), try drawn(light) - 0.1, "more of the backdrop shows through")
        let bare = HUDLook(appearance: .light, material: .glass, transparency: 1)
        XCTAssertEqual(try drawn(bare), try drawn(standIn: bare.glassStandIn), accuracy: 0.01)
        XCTAssertGreaterThan(try drawn(bare), backdrop + 0.2, "a third of the light surface is left")
        XCTAssertLessThan(try drawn(HUDLook(appearance: .dark, material: .glass, transparency: 1)), backdrop - 0.05,
                          "and of the dark one")
        let row = bare.inNotchRow
        XCTAssertEqual(try drawn(row), try drawn(standIn: row.glassStandIn), accuracy: 0.01)
        XCTAssertEqual(try drawn(row), try drawn(whole.inNotchRow), accuracy: 0.01,
                       "the notch's row, whatever the screen's")
        XCTAssertLessThan(try drawn(row), try drawn(dark), "darker than dark glass at the standard transparency")
    }

    /// On screen the HUD's glass is drawn as its screen makes it. Clear or regular, it is Liquid Glass on macOS 26 in a
    /// build made with Xcode 26 or later, which SwiftUI draws itself as a shape of its own over a blur of what is
    /// behind, with no view of AppKit's, and everywhere else the frosted blur (`FrostedGlass`), the one blur view of
    /// AppKit's the HUD holds, in the look's appearance. A material is SwiftUI's regular material on any Mac, drawn by
    /// SwiftUI too, a blur of what is behind with no shape of Liquid Glass's. Solid and the stand-in blur nothing.
    func testEachGlassIsDrawnAsTheScreenMakesIt() {
        for style in HUDGlassStyle.allCases {
            for appearance in [HUDLook.Appearance.dark, .light] {
                let look = HUDLook(appearance: appearance, material: .glass, transparency: 0.5, glassStyle: style)
                let what = "\(appearance) \(style)"
                let drawn = surface(look)
                let frosted = drawn.views.compactMap { $0 as? NSVisualEffectView }.filter { $0.material == .hudWindow }
                XCTAssertEqual(frosted.count, style != .material && !HUDGlass.isLiquid ? 1 : 0, what)
                for blur in frosted {
                    XCTAssertEqual(blur.blendingMode, .behindWindow, what)
                    XCTAssertEqual(blur.state, .active, what)
                    XCTAssertEqual(blur.appearance?.name, look.appearanceName, what)
                }
                #if compiler(>=6.2)
                if #available(macOS 26, *) {
                    XCTAssertEqual(drawn.views.count, 1, "\(what): nothing of AppKit's")
                    XCTAssertTrue(drawn.layers.contains { $0.contains("Backdrop") },
                                  "\(what): a blur of what is behind")
                    XCTAssertEqual(drawn.layers.contains { $0.contains("SDF") }, style != .material,
                                   "\(what): Liquid Glass's shape")
                }
                #endif
            }
        }
        let blurless: [(String, HUDLook, Bool)] = [
            ("standard", .standard, false),
            ("light solid with a transparency", HUDLook(appearance: .light, transparency: 0.4), false),
            ("the stand-in", HUDLook(appearance: .dark, material: .glass), true),
            ("the stand-in of a material", HUDLook(appearance: .light, material: .glass, glassStyle: .material), true),
        ]
        for (name, look, standIn) in blurless {
            let drawn = surface(look, standIn: standIn)
            XCTAssertTrue(drawn.views.allSatisfy { !($0 is NSVisualEffectView) }, name)
            XCTAssertFalse(drawn.layers.contains { $0.contains("Backdrop") }, name)
        }
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

    /// Glass of each appearance at the standard transparency, 0.5, half the look's colour beneath it, as a screen that
    /// chooses Glass first has it.
    private static let darkGlass = HUDLook(appearance: .dark, material: .glass,
                                           transparency: ScreenPlacement.standardGlassTransparency)
    private static let lightGlass = HUDLook(appearance: .light, material: .glass,
                                            transparency: ScreenPlacement.standardGlassTransparency)

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

    /// A card's surface in `look`, as the HUD draws it on screen or, with `standIn`, as its stand-in, in a window that
    /// is never shown: its AppKit views, its hosting view first, and the kinds of its layers, by name.
    private func surface(_ look: HUDLook, standIn: Bool = false) -> (views: [NSView], layers: [String]) {
        _ = NSApplication.shared
        let size = CGSize(width: 80, height: 40)
        let card = HUDSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), look: look,
                              fill: look.theme.islandFill, contact: nil)
        let hosting = NSHostingView(rootView: card.frame(width: size.width, height: size.height)
            .environment(\.drawsGlassStandIn, standIn))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func layers(_ layer: CALayer) -> [String] {
            [String(describing: type(of: layer))] + (layer.sublayers ?? []).flatMap(layers)
        }
        return (views(hosting), hosting.layer.map(layers) ?? [])
    }

    /// The level of grey in the middle of `standIn` laid over the HUD pictures' backdrop, drawn as `drawn(_:)` draws.
    private func drawn(standIn: Color, file: StaticString = #filePath, line: UInt = #line) throws -> CGFloat {
        let size = CGSize(width: 80, height: 40)
        let hosting = NSHostingView(rootView: standIn.frame(width: size.width, height: size.height)
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
