import Foundation

/// One attached display as the host tells the MCP tools of it (`PanelTools`). It is named by its role, never by its
/// system name, which can be a personal device name, and it says nothing of whose agents or accounts it shows.
public struct PanelScreen: Equatable, Sendable {
    /// The display's key, under which its placement, glow and own layout are kept.
    let key: String
    /// Its role in English: "Built-in display", "Main display", or "Display 2" and on, by its place among the displays.
    let name: String
    let mode: HUDMode
    let edge: HUDEdge
    let hasNotch: Bool
    /// The agents its resting HUD would show now without a list in its layout, by vendor, one for each mark, in the
    /// order it shows them: the glow's beside the notch, the marks of a Dynamic dock, the items of a Simple panel.
    let agents: [String]

    public init(key: String, name: String, mode: HUDMode, edge: HUDEdge, hasNotch: Bool, agents: [String]) {
        self.key = key
        self.name = name
        self.mode = mode
        self.edge = edge
        self.hasNotch = hasNotch
        self.agents = agents
    }

    /// The mode as Agent HUD names it to a person: notch, dynamic or simple.
    var modeName: String {
        switch mode {
        case .notch: "notch"
        case .logos: "dynamic"
        case .simple: "simple"
        }
    }
}
