import AgentHUDSupport
import Foundation

/// The four switches of Settings → Display → Expanded panel as a layout sets them: whether the panel shows its session
/// list, its quota details, the agents' blocks with their balances, the blocks' reset countdowns, and its token chart.
/// They are no settings of their own but fields of the layout, its hidden sections and its `countdown`, so an agent's
/// draft, Save, a screen's own layout, Revert to Previous and Reset to Default reach them as they reach the rest of it.
/// Settings shows and sets them on the saved shared layout (`PanelLayoutStore.switches`). `PanelSwitches()`, every
/// switch on, is the default view's.
public struct PanelSwitches: Hashable, Sendable {
    /// The session rows: the `sessions` section shown.
    public var sessionList: Bool
    /// The agents' blocks and the API balances: the `blocks` section shown.
    public var quotaDetails: Bool
    /// The quota blocks' reset times: the layout's `countdown`, which a block's own overrides.
    public var resetCountdown: Bool
    /// The token chart: the `tokens` section shown.
    public var tokenUsage: Bool

    public init(sessionList: Bool = true, quotaDetails: Bool = true, resetCountdown: Bool = true, tokenUsage: Bool = true) {
        self.sessionList = sessionList
        self.quotaDetails = quotaDetails
        self.resetCountdown = resetCountdown
        self.tokenUsage = tokenUsage
    }

    /// Every switch, each with the section it shows; nil for the countdown, which is no section.
    static var fields: [(WritableKeyPath<PanelSwitches, Bool>, PanelSection?)] {
        [(\.sessionList, .sessions), (\.quotaDetails, .blocks), (\.resetCountdown, nil), (\.tokenUsage, .tokens)]
    }

    // MARK: Before the switches joined the layout

    /// The keys the settings kept the switches under before they joined the layout (`SettingsStore.Keys.settings`).
    private static var storedKeys: [(String, WritableKeyPath<PanelSwitches, Bool>)] {
        [("showIslandSessions", \.sessionList), ("showIslandQuota", \.quotaDetails), ("showResetCountdown", \.resetCountdown),
         ("showIslandTokens", \.tokenUsage)]
    }

    /// The switches as settings an earlier version wrote keep them; nil where they keep none, as the settings this
    /// version writes do. Read forgivingly: a switch that is missing or not true or false is on, as it was by default.
    static func stored(in settings: Data?) -> PanelSwitches? {
        guard let fields = settings.flatMap({ try? JSONValue.parse($0) })?.objectValue,
              storedKeys.contains(where: { fields[$0.0] != nil }) else { return nil }
        var switches = PanelSwitches()
        for (key, field) in storedKeys { switches[keyPath: field] = fields[key]?.boolValue ?? true }
        return switches
    }
}

public extension PanelLayout {
    /// The switches as the layout sets them: each section's switch on while the layout does not hide that section, and
    /// the countdown's while the layout's own `countdown` is on. Setting one shows or hides its section, which keeps
    /// its place in `sections`, or sets `countdown`; a block's own countdown still overrides it.
    var switches: PanelSwitches {
        get {
            var switches = PanelSwitches()
            for (field, section) in PanelSwitches.fields {
                switches[keyPath: field] = section.map { !hiddenSections.contains($0) } ?? countdown
            }
            return switches
        }
        set {
            for (field, section) in PanelSwitches.fields {
                let on = newValue[keyPath: field]
                guard let section else { countdown = on; continue }
                hiddenSections.removeAll { $0 == section }
                if !on { hiddenSections.append(section) }
            }
        }
    }
}

extension PanelLayout {
    /// The layout with the switches that `from` and `to` set apart set as `to` sets them, and the others as the layout
    /// sets them: a person's switch reaches that one field.
    func switching(from: PanelSwitches, to: PanelSwitches) -> PanelLayout {
        var layout = self, switches = layout.switches
        for (field, _) in PanelSwitches.fields where from[keyPath: field] != to[keyPath: field] {
            switches[keyPath: field] = to[keyPath: field]
        }
        layout.switches = switches
        return layout
    }

    /// The layout with what the switches an earlier version kept in the settings turned off turned off here too, and
    /// the rest as it is, so the panel it draws is the one those settings drew over it.
    func carrying(_ stored: PanelSwitches) -> PanelLayout {
        var layout = self, switches = layout.switches
        for (field, _) in PanelSwitches.fields where !stored[keyPath: field] { switches[keyPath: field] = false }
        layout.switches = switches
        return layout
    }
}
