import Foundation

/// How one screen presents the HUD.
public enum HUDMode: String, Codable, Sendable, CaseIterable {
    /// The island: the notch itself, or a bar standing in for one on displays without.
    case notch
    /// A queue of the agents' own logos, parked on a screen edge, with the glow behind them as a backdrop.
    case logos
    /// A small floating panel on a screen edge with no glow behind it: each agent's mark, with its tightest
    /// window as a ring round it, a percentage beside it, or both.
    case simple

    /// Parked on a screen edge and opening inward from it, rather than standing at the notch.
    public var isDocked: Bool { self != .notch }
}

/// The screen edge a HUD is parked on. It runs along that edge and opens inward.
public enum HUDEdge: String, Codable, Sendable, CaseIterable {
    case top, right, bottom, left

    public var isHorizontal: Bool { self == .top || self == .bottom }

    /// Unit vector pointing into the screen from this edge.
    public var inward: (x: Double, y: Double) {
        switch self {
        case .top: return (0, -1)
        case .bottom: return (0, 1)
        case .left: return (1, 0)
        case .right: return (-1, 0)
        }
    }
}

/// The colours one screen's HUD is drawn in: light ink on a dark surface, the HUD as it has always been, dark ink on a
/// light one, or whichever of the two macOS is set to. It is the HUD's own, apart from the Appearance the app's windows
/// take (`Settings.appearance`).
public enum HUDAppearance: String, Codable, Sendable, CaseIterable {
    case dark
    case light
    /// Light or dark as macOS is set, whatever the app's own Appearance.
    case system
}

/// What one screen's HUD surface is made of: an opaque fill, or glass that lets the desktop behind it show through,
/// blurred. Glass keeps the HUD's appearance, dark glass with light ink or light glass with dark ink, whatever is behind
/// it.
public enum HUDMaterial: String, Codable, Sendable, CaseIterable {
    case solid
    case glass
}

/// One screen's HUD. Everything here is per screen: two displays can run different modes, sit on
/// different edges and size their logos differently. The glow is per screen too, kept beside this in
/// `Settings.screenGlow` under the same display key, with `Settings.glow` for a display that has none.
public struct ScreenPlacement: Hashable, Codable, Sendable {
    /// Side of one mark in points, independent of the display's menu bar height.
    public static let logoSizeRange: ClosedRange<Double> = 12...36
    /// Distance from the visible logo, including its outline, to its parked screen edge, in points.
    public static let logoEdgeDistanceRange: ClosedRange<Double> = 0...20
    /// Gap between logos, as a share of the logo's height. A gap wider than about half a mark reads as
    /// separate marks rather than one queue.
    public static let gapScaleRange: ClosedRange<Double> = 0.1...0.6
    /// Diameter of one ring in Simple mode, in points. The marks and numbers are sized from it.
    public static let simpleSizeRange: ClosedRange<Double> = 16...40
    /// Stroke of that ring, in points.
    public static let ringWidthRange: ClosedRange<Double> = 1...4
    public var mode: HUDMode
    public var edge: HUDEdge
    /// The queue's centre along its edge, as a fraction of that edge's length, so it survives a
    /// resolution change.
    public var offset: Double
    public var logoSize: Double
    public var logoEdgeDistance: Double
    public var gapScale: Double
    /// Draw the marks. Turning them off leaves the backdrop alone — it still spans what the marks would
    /// have occupied, so the field keeps its place and its width; only the logos stop being drawn.
    public var showsLogos: Bool
    public var simpleSize: Double
    public var ringWidth: Double
    /// Simple mode draws each agent's tightest window as a ring round its mark.
    public var showsRings: Bool
    /// Simple mode writes the percentage used beside each mark.
    public var showsNumbers: Bool
    /// Simple mode turns a working agent's mark into its bot, and lets idle marks visit as bots.
    public var simpleBots: Bool
    /// A docked HUD answers for one agent at a time: hovering a mark opens that agent's own panel from the
    /// mark, and a request or reminder grows from the mark of the agent that sent it while the others stay.
    public var separatesAgents: Bool
    /// The colours of the HUD, its panel and its cards: dark, the HUD as it has always been, unless chosen otherwise.
    public var appearance: HUDAppearance
    /// The surface of the HUD, its panel and its cards: solid unless chosen otherwise.
    public var material: HUDMaterial

    public init(
        mode: HUDMode = .logos,
        edge: HUDEdge = .top,
        offset: Double = 0.5,
        logoSize: Double = 20,
        logoEdgeDistance: Double = 2,
        gapScale: Double = 0.4,
        showsLogos: Bool = true,
        simpleSize: Double = 22,
        ringWidth: Double = 1.5,
        showsRings: Bool = true,
        showsNumbers: Bool = true,
        simpleBots: Bool = false,
        separatesAgents: Bool = false,
        appearance: HUDAppearance = .dark,
        material: HUDMaterial = .solid
    ) {
        self.mode = mode
        self.edge = edge
        self.offset = Self.clamp(offset, to: 0...1)
        self.logoSize = Self.clamp(logoSize, to: Self.logoSizeRange)
        self.logoEdgeDistance = Self.clamp(logoEdgeDistance, to: Self.logoEdgeDistanceRange)
        self.gapScale = Self.clamp(gapScale, to: Self.gapScaleRange)
        self.showsLogos = showsLogos
        self.simpleSize = Self.clamp(simpleSize, to: Self.simpleSizeRange)
        self.ringWidth = Self.clamp(ringWidth, to: Self.ringWidthRange)
        self.showsRings = showsRings
        self.showsNumbers = showsNumbers
        self.simpleBots = simpleBots
        self.separatesAgents = separatesAgents
        self.appearance = appearance
        self.material = material
    }

    /// A display's starting point: a notched screen keeps its island, anything else shows the queue, both dark and solid.
    public static func `default`(hasNotch: Bool) -> ScreenPlacement {
        ScreenPlacement(mode: hasNotch ? .notch : .logos)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }

    private enum CodingKeys: String, CodingKey {
        case mode, edge, offset, logoSize, logoEdgeDistance, gapScale, showsLogos
        case simpleSize, ringWidth, showsRings, showsNumbers, simpleBots, separatesAgents
        case appearance, material
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScreenPlacement()
        self.init(
            mode: (try? c.decodeIfPresent(HUDMode.self, forKey: .mode)) ?? d.mode,
            edge: (try? c.decodeIfPresent(HUDEdge.self, forKey: .edge)) ?? d.edge,
            offset: try c.decodeIfPresent(Double.self, forKey: .offset) ?? d.offset,
            logoSize: try c.decodeIfPresent(Double.self, forKey: .logoSize) ?? d.logoSize,
            logoEdgeDistance: try c.decodeIfPresent(Double.self, forKey: .logoEdgeDistance) ?? d.logoEdgeDistance,
            gapScale: try c.decodeIfPresent(Double.self, forKey: .gapScale) ?? d.gapScale,
            showsLogos: try c.decodeIfPresent(Bool.self, forKey: .showsLogos) ?? d.showsLogos,
            simpleSize: try c.decodeIfPresent(Double.self, forKey: .simpleSize) ?? d.simpleSize,
            ringWidth: try c.decodeIfPresent(Double.self, forKey: .ringWidth) ?? d.ringWidth,
            showsRings: try c.decodeIfPresent(Bool.self, forKey: .showsRings) ?? d.showsRings,
            showsNumbers: try c.decodeIfPresent(Bool.self, forKey: .showsNumbers) ?? d.showsNumbers,
            simpleBots: try c.decodeIfPresent(Bool.self, forKey: .simpleBots) ?? d.simpleBots,
            separatesAgents: try c.decodeIfPresent(Bool.self, forKey: .separatesAgents) ?? d.separatesAgents,
            // A name saved by a newer build falls back to the default instead of failing the whole placement, and with
            // it every screen's (`Settings.screens`).
            appearance: (try? c.decodeIfPresent(HUDAppearance.self, forKey: .appearance)) ?? d.appearance,
            material: (try? c.decodeIfPresent(HUDMaterial.self, forKey: .material)) ?? d.material
        )
    }
}

// MARK: The look drawn

extension ScreenPlacement {
    /// Whether the HUD draws its appearance and material: everywhere but at a hardware notch, where the island in Notch
    /// mode, the panel it opens into and the cards it grows stay black, dark and solid, one with the camera housing. A
    /// bar that stands in for a notch on a screen without one draws them, as every dock does.
    public func drawsLook(hasNotch: Bool) -> Bool {
        mode != .notch || !hasNotch
    }

    /// Whether the HUD is drawn light: its appearance, `system` as macOS is set now (`systemIsLight`), and dark where it
    /// does not draw its look (`drawsLook(hasNotch:)`).
    public func drawsLight(hasNotch: Bool, systemIsLight: Bool) -> Bool {
        guard drawsLook(hasNotch: hasNotch) else { return false }
        switch appearance {
        case .dark: return false
        case .light: return true
        case .system: return systemIsLight
        }
    }

    /// Whether the HUD is drawn as glass: its material, solid while Reduce Transparency is on (`reducesTransparency`)
    /// and where it does not draw its look (`drawsLook(hasNotch:)`).
    public func drawsGlass(hasNotch: Bool, reducesTransparency: Bool) -> Bool {
        drawsLook(hasNotch: hasNotch) && material == .glass && !reducesTransparency
    }
}
