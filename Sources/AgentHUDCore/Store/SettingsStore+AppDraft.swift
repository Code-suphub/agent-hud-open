import Foundation

/// What the app draws of its own settings: the saved settings, with the draft an agent proposed for them drawn over them
/// (`PanelLayoutStore.appDraft`). Settings stay the saved truth, and a person's edit of one of them in Settings wins over
/// a draft.
@MainActor
public extension SettingsStore {
    /// The settings as the app draws them now: the saved ones with the app's draft drawn over them, which sets the
    /// Appearance, Match screen, Bot logos, Show menu bar icon and Hover behavior, and every other setting as saved. The
    /// HUDs, their hover, the app's windows, the menu bar and the Settings controls and previews read those settings
    /// here, so a draft shows at once wherever they apply.
    var effectiveSettings: Settings {
        panelLayout.appDraft.map { $0.applied(to: settings) } ?? settings
    }

    /// A person's own edit of one setting in Settings, `setting`: the field of the app's draft that sets it, if any, is
    /// dropped first, so a person always wins over an agent, and the change is made to the settings as saved. The rest of
    /// the draft waits as it was, but for an appearance that the edit leaves to Match screen: with Match screen on the
    /// windows and the menu take their screen's look, which is why Settings greys the Appearance out, so the draft's
    /// appearance would draw nothing, and a proposal that repeats it would be refused. These settings are no one screen's,
    /// so an agent's hold on a panel stays on.
    func updateSetting(_ setting: PartialKeyPath<Settings>, _ change: (inout Settings) -> Void) {
        if let field = AppDraft.Field(setting: setting) { panelLayout.discardApp(field) }
        update(change)
        if panelLayout.appDraft?.appearance != nil, effectiveSettings.appearanceFollowsScreen {
            panelLayout.discardApp(.appearance)
        }
    }
}
