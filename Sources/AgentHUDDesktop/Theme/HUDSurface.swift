import AppKit
import SwiftUI
import AgentHUDCore

extension EnvironmentValues {
    /// Whether glass is drawn as its stand-in, the look's tint alone over whatever is behind it: in a picture, a snapshot,
    /// a Settings preview and a recording of the HUD, which are drawn where no glass or blur can be, off screen, in this
    /// process, or over a desktop painted inside a window. Off on the HUD itself.
    @Entry var drawsGlassStandIn = false
    /// Whether a material stands in too, where Liquid Glass would not: in a Settings preview, whose wallpaper is painted
    /// inside the window, which a material, a blur of what is behind the window, does not take in.
    @Entry var drawsMaterialStandIn = false
}

/// Where glass is Liquid Glass and where it is frosted.
enum HUDGlass {
    /// Whether glass is Liquid Glass here: on macOS 26, in a build made with Xcode 26 or later. Before macOS 26, and in a
    /// build made with an older Xcode, glass is a frosted blur (`FrostedGlass`).
    static var isLiquid: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    /// How far Liquid Glass runs on past the screen edge a surface stands on, off the window: glass lights a rim round
    /// its whole shape, and none must show where the HUD meets the edge of the screen.
    static let bleed: CGFloat = 12
}

extension HUDLook {
    /// The hairline round a surface in this look: `color`, or none where Liquid Glass lights a rim of its own. Glass drawn
    /// as its stand-in keeps the hairline, as solid does, and so does a material, which has no rim of its own.
    func outline(_ color: Color, standIn: Bool) -> Color {
        material == .glass && glassStyle != .material && !standIn && HUDGlass.isLiquid ? .clear : color
    }
}

/// The HUD's surface in one of its shapes: the island's silhouette, a detached card, a compact reminder's wings, the
/// Simple panel and the line that grows out of it, the body of a row's hover details. Every fill the HUD stands on is
/// drawn here, so solid and glass part in one place.
///
/// - Solid is `fill` in the shape, as the HUD has always been filled, thinned by the screen's transparency
///   (`HUDLook.coverOpacity`), which is 0 for a solid surface until chosen otherwise.
/// - Glass is Liquid Glass on macOS 26 in a build made with Xcode 26 or later, and a frosted blur of what is behind the
///   window everywhere else (`FrostedGlass`): the system's own glass, always whole, with nothing of the HUD's laid over
///   it. Beneath it lies a dimming layer in the look's own colour (`HUDLook.glassDimming`), as Apple asks of clear
///   glass, which the glass blurs with the desktop: the screen's transparency thins it, from whole at 0 to none at 1,
///   where the HUD is the system's bare glass, as a macOS menu's is. So the HUD stays frosted glass at any transparency.
///   Glass turns light over a light desktop and dark over a dark one, and the HUD's text and status colours are fixed,
///   so with little dimming they read less well over a desktop of the other shade. The frosted blur hides what lies
///   beneath it in the window, so there the dimming lies over it.
/// - Where nothing is behind to blur (`drawsGlassStandIn`), glass is the look's own surface standing in for it
///   (`HUDLook.glassStandIn`).
///
/// The surface is drawn behind what the HUD holds, never round it: glass that holds the HUD's content would turn that
/// content's colour scheme with the desktop behind it, and glass drawn in a `GlassEffectContainer` with the content
/// beside it blurs the content as if it were the desktop. So no surface is ever put in such a container.
///
/// A change of look cross-fades on the island's curve, and under Reduce Motion is made at once. A blur or glass does not
/// fade with a colour, so each way of drawing is a layer of its own, and a change between them fades one layer out as
/// the other fades in; a change of appearance or of transparency moves the colours, and fades a blur into its new one.
struct HUDSurface<S: Shape>: View {
    let shape: S
    let look: HUDLook
    /// The solid fill, the island's or a raised box's, opaque: the screen's transparency alone thins it.
    let fill: Color
    /// The screen edge the surface stands on, which Liquid Glass runs on past (`HUDGlass.bleed`); nil for a surface that
    /// floats free of it.
    let contact: HUDEdge?
    @Environment(\.drawsGlassStandIn) private var standIn
    @Environment(\.drawsMaterialStandIn) private var materialStandIn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ shape: S, look: HUDLook, fill: Color, contact: HUDEdge?) {
        self.shape = shape
        self.look = look
        self.fill = fill
        self.contact = contact
    }

    /// How the surface is drawn here and now.
    private enum Drawing {
        case solid
        case liquid
        case frosted
        case material
        case standIn
    }

    private var drawing: Drawing {
        guard look.material == .glass else { return .solid }
        if standIn { return .standIn }
        if look.glassStyle == .material { return materialStandIn ? .standIn : .material }
        return HUDGlass.isLiquid ? .liquid : .frosted
    }

    var body: some View {
        ZStack {
            switch drawing {
            case .solid:
                shape.fill(fill)
                    .opacity(look.coverOpacity)
                    .transition(.opacity)
            case .standIn:
                shape.fill(look.glassStandIn)
                    .transition(.opacity)
            case .frosted:
                // A blur of what is behind the window hides what the window holds beneath it, so the dimming lies over
                // the frost here.
                FrostedGlass(appearance: look.appearanceName)
                    .clipShape(shape)
                    .overlay { shape.fill(look.glassDimming) }
                    .transition(.opacity)
            case .liquid:
                // The dimming beneath the glass, which Liquid Glass blurs with the desktop behind it.
                ZStack {
                    shape.fill(look.glassDimming)
                    liquid
                }
                .transition(.opacity)
            case .material:
                // A material is a blur of what is behind the window, which hides what lies beneath it, so the dimming
                // lies over it.
                shape.fill(.regularMaterial)
                    .environment(\.colorScheme, look.colorScheme)
                    .overlay { shape.fill(look.glassDimming) }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : IslandAnimation.curve, value: look)
    }

    /// Liquid Glass in the shape, run past the screen edge the surface stands on, in the look's colour scheme, with no
    /// tint of its own: a tint is taken as a hint the glass lets the desktop overrule. It is the screen's choice of
    /// variant: the clear one, the same at any size, which lets more of the desktop through, or the regular one, which
    /// turns light or dark with the size of the piece it is drawn in, a narrow panel light and a wide card dark over the
    /// same window.
    @ViewBuilder
    private var liquid: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(look.glassStyle == .regular ? .regular : .clear,
                             in: ContactBleed(base: shape, edge: contact, depth: HUDGlass.bleed))
                .environment(\.colorScheme, look.colorScheme)
        }
        #endif
    }
}

/// `base` run on `depth` points past `edge`, where it stands on the screen's edge: a strip as wide as its contact edge
/// joined to it beyond the rect it is drawn in, which the window cuts off. Nothing is added for a surface that floats.
struct ContactBleed<Base: Shape>: Shape {
    var base: Base
    let edge: HUDEdge?
    let depth: CGFloat

    var animatableData: Base.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let shape = base.path(in: rect)
        guard let edge, depth > 0 else { return shape }
        let strip = switch edge {
        case .top: CGRect(x: rect.minX, y: rect.minY - depth, width: rect.width, height: depth)
        case .bottom: CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: depth)
        case .left: CGRect(x: rect.minX - depth, y: rect.minY, width: depth, height: rect.height)
        case .right: CGRect(x: rect.maxX, y: rect.minY, width: depth, height: rect.height)
        }
        return shape.union(Path(strip))
    }
}

/// The frosted blur glass is drawn as where Liquid Glass is not. It blurs what is behind the window in the HUD's
/// material, held to the look's appearance, and stays active: the HUD's windows are hardly ever key, and an inactive
/// blur draws the flat grey of a window in the background.
struct FrostedGlass: NSViewRepresentable {
    let appearance: NSAppearance.Name

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.appearance = NSAppearance(named: appearance)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        guard view.appearance?.name != appearance else { return }
        // A blur takes a new appearance at once. Under an animated change it fades into it, as the colours over it move.
        if context.transaction.animation != nil, !context.transaction.disablesAnimations, let layer = view.layer {
            IslandAnimation.fadeLook(of: layer)
        }
        view.appearance = NSAppearance(named: appearance)
    }
}
