import SwiftUI
import AgentHUDCore

/// One API provider's accounts in the hover panel, each account's card one under another, drawn by the widget its plan
/// names, with one picker over the measures the plan offers, in the first card's heading, where there is more than one:
/// a flip shows the same measure on every card of the block. Refreshes keep its selected measure because its provider is
/// its identity; the panel gives it a new identity when its plan asks for another widget or other measures, and the
/// picker starts from the first of them again.
struct BillingBlock: View {
    let store: UsageStore
    let accounts: [APIBilling]
    let plan: PanelBlockPlan
    /// Whether the first card stands under a divider of its own: across the whole line it does, as every balance card
    /// has since before there were layouts; in half a line the line's divider stands above it instead.
    let dividesFirst: Bool
    let divider: Color
    @State private var metric: PanelMeasure
    @Environment(\.panelSpacing) private var spacing
    @Environment(\.hudTheme) private var theme

    init(store: UsageStore, accounts: [APIBilling], plan: PanelBlockPlan, dividesFirst: Bool, divider: Color) {
        self.store = store
        self.accounts = accounts
        self.plan = plan
        self.dividesFirst = dividesFirst
        self.divider = divider
        _metric = State(initialValue: plan.measure)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing.blocks) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                let divided = dividesFirst || index > 0
                APIBillingCard(billing: account, store: store, theme: theme, compact: true, period: plan.period,
                               widget: plan.widget, measures: plan.measures, measure: metric,
                               picker: index == 0 && plan.measures.count > 1 ? $metric : nil)
                    .padding(.top, divided ? spacing.divided : 0)
                    .topDivider(divided ? divider : .clear)
            }
        }
    }
}
