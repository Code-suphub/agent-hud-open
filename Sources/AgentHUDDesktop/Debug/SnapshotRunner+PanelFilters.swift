import AppKit
import SwiftUI
import AgentHUDCore

#if DEBUG
/// The hover panel's stills under a layout's sessions, tokens and periods, named `panel-layout-sessions-…`,
/// `panel-layout-tokens-…` and `panel-layout-blocks-week`.
extension SnapshotRunner {
    /// The sample's panel with three session rows and with ten, ten of the week's, the running sessions alone, an agent
    /// filter that keeps none of the day's sessions, the token chart over the last 7 days, Claude's over the last 30 and
    /// one model's alone, Claude's quota block as a chart of the last 7 days beside the balance's estimated cost over
    /// them, and the chart alone in each period its picker offers, one above the other. They are drawn from a settings store of their own,
    /// as the other layout stills are.
    static func saveFilters(preferences: AgentHUDCore.Settings, folder: URL) {
        let suite = "app.agenthud.open.snapshot.layout-filters"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.agents)
        settings.update { $0 = preferences }
        let store = demoStore(settings)
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours,
                                                       now: DemoClock.now, stage: nil))
        func shoot(_ name: String, _ proposal: PanelLayout) {
            settings.panelLayout.propose(proposal)
            settings.panelLayout.save()
            save("panel-layout-\(name)", IslandScene(store: store, settings: settings, open: true, light: false, look: .standard),
                 folder: folder, scheme: .dark)
        }
        shoot("sessions-3", PanelLayout(sessions: PanelLayout.Sessions(limit: 3)))
        shoot("sessions-10", PanelLayout(sessions: PanelLayout.Sessions(limit: 10)))
        shoot("sessions-week", PanelLayout(sessions: PanelLayout.Sessions(limit: 10, period: .week)))
        shoot("sessions-running", PanelLayout(sessions: PanelLayout.Sessions(states: [.running])))
        // The sample has no Grok session: the section says the filter keeps none and keeps its header.
        shoot("sessions-none", PanelLayout(sessions: PanelLayout.Sessions(agents: ["Grok CLI"])))
        shoot("tokens-week", PanelLayout(tokens: PanelLayout.Tokens(period: .week)))
        shoot("tokens-month", PanelLayout(tokens: PanelLayout.Tokens(period: .month, agents: ["Claude"])))
        shoot("tokens-models", PanelLayout(tokens: PanelLayout.Tokens(models: ["claude-model:claude-opus-5-5"])))
        shoot("blocks-week", PanelLayout(blocks: ["Claude": PanelLayout.Block(widget: .chart, period: .week),
                                                  "api:DeepSeek": PanelLayout.Block(period: .week)]))
        settings.panelLayout.reset()

        let width = CGFloat(PanelStyle.defaultWidth) - HoverPanelView.notchInsets.leading - HoverPanelView.notchInsets.trailing
        let look = HUDLook.standard
        save("panel-layout-tokens-picker",
             VStack(alignment: .leading, spacing: 18) {
                 ForEach(PanelTokenPeriod.allCases) { period in
                     TokenConsumptionChart(store: store, theme: look.theme, context: .island, period: period, compact: true)
                 }
             }
             .frame(width: width)
             .foregroundStyle(look.theme.text)
             .padding(18)
             .background(look.theme.islandFill)
             .hudLook(look), folder: folder, scheme: .dark)
    }
}
#endif
