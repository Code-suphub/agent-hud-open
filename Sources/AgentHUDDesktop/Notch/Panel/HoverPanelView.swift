import SwiftUI
import AgentHUDCore

/// Reports the panel's natural height so the island window can size itself to the content.
struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

/// The agents' blocks, a compact token chart and the local session summary, as its screen's panel layout arranges and
/// sets them: by default the quota rows, then the chart, then the sessions, at regular spacing with dividers between.
struct HoverPanelView: View {
    let store: UsageStore
    let onOpenStats: () -> Void
    var onOpenSettings: () -> Void = {}
    var additionalHUDControls: @MainActor () -> AnyView = { AnyView(EmptyView()) }
    /// Nil measures the natural layout; the visible panel gives its bounded height.
    var height: CGFloat? = nil
    var alert: IslandAlert? = nil
    var onOpenAlert: () -> Void = {}
    var onOpenAlertSession: () -> Void = {}
    var onOpenAlertUsage: () -> Void = {}
    var sessionNavigationFailed = false
    var onOpenListedSession: (String) -> Void = { _ in }
    var failedListedSessionID: String? = nil
    var onDecideAlert: (PermissionDecision) -> Void = { _ in }
    var waitingRequests: [PermissionRequest] = []
    /// The notch keeps its hardware clearance; a dock leaves room beside its parked logo strip instead.
    var insets = HoverPanelView.notchInsets
    static let notchInsets = EdgeInsets(top: 32, leading: 18, bottom: 14, trailing: 18)

    /// The row whose questions are open for answering here rather than in the agent.
    var answeringSessionID: String? = nil
    var onAnswerSession: (String?) -> Void = { _ in }
    /// Set on a dock that separates its agents: the panel is this one agent's, and shows nothing of the others.
    var focusVendor: String? = nil
    /// Whether a failed refresh is said above the panel's content; a picture of the panel leaves it out.
    var showsRefreshError = true
    /// The key of the screen whose panel this is, whose layout it draws (`PanelLayoutStore.effective(for:)`); nil draws
    /// the shared layout.
    var screen: String? = nil

    /// Whether something belongs to the agent this panel is for. Agents that share a mark share a panel.
    private func focused(_ vendor: String?) -> Bool {
        guard let focusVendor else { return true }
        return vendor.map { AgentArtwork.markKey($0) == AgentArtwork.markKey(focusVendor) } ?? false
    }

    private var quotaGroups: [(vendor: String, rows: [AgentRow])] { store.rowGroups.filter { focused($0.vendor) } }
    private var billing: [APIBilling] { store.enabledBilling.filter { focused($0.vendor) } }
    private var consumers: [AgentDescriptor] { store.consumers.filter { focused($0.vendor) } }
    private var tokenFilter: TokenModelFilter {
        focusVendor == nil ? TokenModelFilter() : TokenModelFilter(consumerIDs: Set(consumers.map(\.id)))
    }

    let theme = Theme.island
    /// Above the draft bar and the footer, which keep their room whatever the layout's spacing.
    private let footerSpacing: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set on the panel's picture for an agent, whose session rows then name no session.
    @Environment(\.masksIdentity) var masksIdentity

    private var layout: PanelLayoutStore { store.settings.panelLayout }

    /// The panel under its screen's layout in effect, a draft included. The Settings switches decide what exists; the
    /// layout hides, orders and draws what they leave.
    private var plan: PanelLayoutPlan { PanelLayoutPlan(layout: layout.effective(for: screen), blocks: store.view.panelBlocks) }

    /// One block of the panel with what it draws: a vendor's quota rows, or the API accounts under one key.
    private enum Block: Identifiable {
        case quota(PanelBlockPlan, rows: [AgentRow])
        case billing(PanelBlockPlan, accounts: [APIBilling])

        var plan: PanelBlockPlan {
            switch self {
            case .quota(let plan, _), .billing(let plan, _): plan
            }
        }

        /// A block that asks for another widget, or other measures, is another view: its picker starts again.
        var id: String { "\(plan.key)|\(plan.widget.rawValue)|" + plan.measures.map(\.rawValue).joined(separator: ",") }
        var isQuota: Bool { plan.kind == .quota }
    }

    private func blocks(_ plan: PanelLayoutPlan) -> [Block] {
        guard store.settings.settings.showIslandQuota else { return [] }
        let groups = Dictionary(quotaGroups.map { ($0.vendor, $0.rows) }, uniquingKeysWith: { first, _ in first })
        let accounts = Dictionary(grouping: billing, by: \.panelBlockKey)
        return plan.blocks.compactMap { block in
            switch block.kind {
            case .quota: groups[block.key].map { .quota(block, rows: $0) }
            case .billing: accounts[block.key].map { .billing(block, accounts: $0) }
            }
        }
    }

    /// The sections that have something to show, in the layout's order.
    private func sections(_ plan: PanelLayoutPlan, blocks: [Block]) -> [PanelSection] {
        let settings = store.settings.settings
        return plan.sections.filter { section in
            switch section {
            case .blocks: !blocks.isEmpty
            case .tokens: settings.showIslandTokens && (store.isLoading || store.isIndexing || !consumers.isEmpty)
            case .sessions: settings.showIslandSessions
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: footerSpacing) {
            if height != nil {
                ScrollView(.vertical) { measuredContent }
            } else {
                measuredContent
            }
            // An unsaved layout is said above the footer, outside the scrolling content, and counts in the height.
            VStack(alignment: .leading, spacing: footerSpacing) {
                if layout.hasDraft(on: screen) {
                    PanelDraftBar(layout: layout, screen: screen).transition(.opacity)
                }
                footer
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self,
                                       value: proxy.size.height + insets.top + insets.bottom + footerSpacing)
            })
        }
        .padding(insets)
        .frame(height: height, alignment: .top)
        .foregroundStyle(theme.text)
        .animation(reduceMotion ? nil : IslandAnimation.curve, value: layout.effective(for: screen))
        .animation(reduceMotion ? nil : IslandAnimation.curve, value: layout.draftScope(on: screen))
    }

    private var measuredContent: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            })
    }

    private var content: some View {
        let plan = plan
        let blocks = blocks(plan)
        let sections = sections(plan, blocks: blocks)
        let inlineAlert = alert.map { !$0.isSessionEvent } == true
        // A quota block names its agent; where none is drawn, the panel still has to say whose it is.
        let titled = focusVendor != nil && !(sections.contains(.blocks) && blocks.contains(where: \.isQuota))
        let error = showsRefreshError ? store.lastError : nil
        let hasHeader = error != nil || inlineAlert || titled
        let spacing = PanelSpacingMetrics(plan.style.spacing)
        let divider = plan.style.separators ? theme.divider : Color.clear
        return VStack(alignment: .leading, spacing: spacing.sections) {
            if let error {
                Text(L10n.text("刷新失败：", "Refresh failed: ") + error)
                    .font(.ui(11)).foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let alert, !alert.isSessionEvent {
                IslandAlertInlineView(alert: alert, onOpen: onOpenAlert, onDecide: onDecideAlert,
                                      onOpenSession: onOpenAlertSession, onOpenUsage: onOpenAlertUsage,
                                      sessionNavigationFailed: sessionNavigationFailed,
                                      waitingRequests: waitingRequests).id(alert.id)
                    .padding(.bottom, 4)
            }
            if let focusVendor, titled {
                Text(focusVendor).font(.ui(13, .semibold))
            }
            ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                switch section {
                case .blocks:
                    blockList(blocks, separated: index > 0, spacing: spacing, divider: divider)
                case .tokens:
                    TokenConsumptionChart(store: store, theme: theme, context: .island, modelFilter: tokenFilter,
                                          compact: true, onOpenStats: onOpenStats)
                        // The chart keeps its filter as state, so another agent's panel is another chart.
                        .id(focusVendor)
                        .padding(.top, spacing.divided)
                        .topDivider(divider)
                case .sessions:
                    sessionLine(hasAbove: index > 0 || hasHeader, spacing: spacing, divider: divider)
                }
            }
        }
        .environment(\.panelSpacing, spacing)
    }

    /// The blocks in the layout's order. A quota block comes under a divider unless it is the first, which has one only
    /// below another section. An API account's card is always under its own divider, the first one too, as it has been
    /// since before there were layouts, so a panel of balances alone is the panel it was. Without separators each
    /// divider's room stays and its line goes.
    private func blockList(_ blocks: [Block], separated: Bool, spacing: PanelSpacingMetrics, divider: Color) -> some View {
        VStack(alignment: .leading, spacing: spacing.blocks) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                Group {
                    switch block {
                    case .quota(let plan, let rows):
                        let divided = index > 0 || separated
                        ProviderQuotaBlock(store: store, rows: rows, plan: plan)
                            .padding(.top, divided ? spacing.divided : 0)
                            .topDivider(divided ? divider : .clear)
                    case .billing(_, let accounts):
                        VStack(alignment: .leading, spacing: spacing.blocks) {
                            ForEach(accounts) { account in
                                APIBillingCard(billing: account, store: store, theme: theme, compact: true)
                                    .padding(.top, spacing.divided)
                                    .topDivider(divider)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help(L10n.text("设置", "Settings"))
            .accessibilityLabel(L10n.text("设置", "Settings"))
            Spacer()
            additionalHUDControls()
            Button {
                store.focusedSessionID = nil
                store.statsTab = .tokens
                onOpenStats()
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help(L10n.text("用量统计", "Usage statistics"))
            .accessibilityLabel(L10n.text("用量统计", "Usage statistics"))
        }
        .buttonStyle(.plain)
        .font(.ui(14))
        .foregroundStyle(theme.secondary)
        .padding(.top, 6)
        .overlay(alignment: .top) { Rectangle().fill(theme.divider).frame(height: 1) }
    }
}
