import SwiftUI
import AgentHUDCore

/// A single silhouette: closed notch, lateral event wings, or a hovered detail surface.
struct IslandRootView: View {
    let store: UsageStore?
    let isOpen: Bool
    let collapsedSize: CGSize
    let collapsedTopRadius: CGFloat
    let collapsedBottomRadius: CGFloat
    let lightBorder: Bool
    let onOpenStats: () -> Void
    var onOpenSettings: () -> Void = {}
    var additionalHUDControls: @MainActor () -> AnyView = { AnyView(EmptyView()) }
    var alert: IslandAlert? = nil
    var onOpenAlert: () -> Void = {}
    var onDismissAlert: () -> Void = {}
    var onOpenAlertSession: () -> Void = {}
    var onOpenAlertUsage: () -> Void = {}
    var sessionNavigationFailed = false
    var onOpenListedSession: (String) -> Void = { _ in }
    var failedListedSessionID: String? = nil
    /// The user's answer to a request waiting on the island; the alert's own id says which request it answers.
    var onDecideAlert: (PermissionDecision) -> Void = { _ in }
    /// Every request waiting for this user, oldest first and across screens: the expanded card stacks the rest under
    /// the one being decided, and the collapsed island only counts them.
    var waitingRequests: [PermissionRequest] = []
    /// The screen owner supplies the same expansion to visible content and natural-height measurement.
    var answeringSessionID: String? = nil
    var onAnswerSession: (String?) -> Void = { _ in }
    /// Replies and requests share the event surface while quota and tokens keep their own panel.
    var sessionEvents: [IslandAlert] = []
    /// Brings one of the stacked requests to the front.
    var onSelectRequest: (String) -> Void = { _ in }
    /// The user started or stopped typing an answer on the island.
    var onTyping: @MainActor (Bool) -> Void = { _ in }
    var showsAlertDetails = false
    var presentationSize: CGSize? = nil
    /// The actual card inside a canvas that can also hold a longer logo strip. Coordinates are local,
    /// top-left based; the card and its upright content share this exact frame with the native shadow.
    var presentationFrame: CGRect? = nil
    var animatesGeometry = true
    var onContentHeight: (CGFloat) -> Void = { _ in }
    var onGeometryCompletion: () -> Void = {}
    /// Set on a screen in logo mode: the marks ride on top of the silhouette, collapsed or open, so hovering
    /// never makes the agents disappear.
    var logoQueue: LogoQueueConfig? = nil
    /// Set on a screen in Simple mode: the panel of rings and numbers, which takes the queue's place. Its
    /// silhouette floats, and is the panel itself while collapsed.
    var simpleMeter: SimpleMeterConfig? = nil
    /// Whether marks on this island turn into bots; carried to the alerts through the environment.
    var botLogos = true
    /// Set on a screen whose HUD is a logo queue. Collapsed, such a HUD has no silhouette: it is the marks
    /// over whatever is behind them. Kept apart from `logoQueue`, which only says whether marks are drawn —
    /// hiding them leaves the backdrop alone and must not bring the black shape back.
    var hidesSilhouette = false
    /// Set on a dock that separates its agents. The marks then stay where they are whatever the card does:
    /// the Simple panel draws its own capsule instead of lending it to the card, and nothing replaces them.
    var separatesAgents = false
    /// The one agent the card is for right now: the hovered mark's, or the sender of the event on show.
    var focusVendor: String? = nil
    /// Where the queue's strip sits inside the window, in points down from its top edge, and how tall it is.
    /// The window's own top edge moves between the collapsed and the expanded frame; the marks must not.
    var logoQueueInset: CGFloat = 0
    var logoQueueHeight: CGFloat = 0
    var edge: HUDEdge = .top
    /// The queue's exact rect in the window, using SwiftUI's top-left coordinates. It stays anchored while
    /// the panel grows inward, including when clamping the panel near a screen corner moves its centre.
    var logoQueueFrame: CGRect? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let expandedTopRadius: CGFloat = NotchGeometry.expandedTopRadius
    static let expandedBottomRadius: CGFloat = IslandController.expandedRadius
    static let dockCompactRowHeight: CGFloat = 32
    /// The compact row already keeps `alertSidePadding` at each end, so the card adds none of its own.
    static let dockCompactInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)

    static var placeholder: IslandRootView {
        IslandRootView(store: nil, isOpen: false, collapsedSize: CGSize(width: 216, height: 32),
                       collapsedTopRadius: NotchGeometry.collapsedTopRadius, collapsedBottomRadius: 12,
                       lightBorder: false, onOpenStats: {})
    }

    var body: some View {
        surfaces.environment(\.botLogos, botLogos)
    }

    private var surfaces: some View {
        GeometryReader { proxy in
            let bounds = proxy.size
            let visible = isOpen || alert != nil
            let size = visible ? (presentationFrame?.size ?? presentationSize ?? bounds) : collapsedSize
            // Simple mode has one floating frame. Collapsed it is the capsule the figures sit in; opening
            // enlarges that same frame into the panel, so nothing fades in over it and nothing is swapped.
            let shape = simpleMeter.map { meter in
                IslandShape(
                    topRadius: visible ? Self.expandedTopRadius : 0,
                    bottomRadius: isOpen ? Self.expandedBottomRadius : (alert == nil ? meter.cornerRadius : 16),
                    edge: edge, lift: SimpleMeterConfig.edgeMargin
                )
            } ?? IslandShape(
                topRadius: isOpen ? Self.expandedTopRadius : collapsedTopRadius,
                bottomRadius: isOpen ? Self.expandedBottomRadius : max(collapsedBottomRadius, alert == nil ? 0 : 14),
                edge: edge
            )
            // A collapsed logo queue is the marks alone: no silhouette behind them, so they read as agents
            // sitting on the desktop rather than as a bar. The silhouette comes back the moment the panel
            // opens or an event needs somewhere to be shown — but never because the marks were hidden.
            let bare = hidesSilhouette && !visible && (!floats || separatesAgents)
            let surface = ZStack(alignment: surfaceAlignment) {
                // Keep one shape alive through collapse so it can shrink before becoming transparent.
                shape.fill(.black.opacity(floats && !visible ? 0.82 : 1))
                    .overlay {
                        if floats { shape.stroke(.white.opacity(0.14), lineWidth: 1) }
                        else if lightBorder && alert == nil { shape.stroke(.white.opacity(0.18), lineWidth: 1) }
                    }
                    .frame(width: size.width, height: size.height)
                    .opacity(bare ? 0 : 1)
                content
                    .environment(\.islandTyping, onTyping)
                    .mask(alignment: surfaceAlignment) { shape.frame(width: size.width, height: size.height) }
                }
            ZStack(alignment: .topLeading) {
                if let presentationFrame {
                    // The native canvas changes immediately. Only the card's size and its position
                    // along the parked edge interpolate; the contact edge stays on that canvas.
                    let offset = (hidesSilhouette ? edge : .top).isHorizontal
                        ? CGSize(width: presentationFrame.midX - bounds.width / 2, height: 0)
                        : CGSize(width: 0, height: presentationFrame.midY - bounds.height / 2)
                    surface
                        .frame(width: presentationFrame.width, height: presentationFrame.height,
                               alignment: surfaceAlignment)
                        .offset(offset)
                        .animation(geometryAnimation, value: presentationFrame)
                        .transaction(value: presentationFrame) { transaction in
                            if animatesGeometry {
                                transaction.addAnimationCompletion(criteria: .removed, onGeometryCompletion)
                            }
                        }
                        .frame(width: bounds.width, height: bounds.height, alignment: surfaceAlignment)
                } else {
                    surface
                        .animation(geometryAnimation, value: size)
                        .frame(width: bounds.width, height: bounds.height, alignment: surfaceAlignment)
                }
                if let logoQueue, alert == nil || focusVendor != nil {
                    if let logoQueueFrame {
                        LogoQueueView(config: logoQueue, light: lightBorder)
                            .frame(width: logoQueueFrame.width, height: logoQueueFrame.height)
                            .position(x: logoQueueFrame.midX, y: logoQueueFrame.midY)
                            .frame(width: bounds.width, height: bounds.height)
                            .transaction { $0.animation = nil }
                    } else {
                        LogoQueueView(config: logoQueue, light: lightBorder)
                            .frame(width: size.width, height: logoQueueHeight)
                            .padding(.top, logoQueueInset)
                            .frame(width: bounds.width, height: bounds.height, alignment: surfaceAlignment)
                            .transaction { $0.animation = nil }
                    }
                }
                if let simpleMeter, alert == nil || focusVendor != nil {
                    let strip = logoQueueFrame ?? CGRect(x: 0, y: logoQueueInset, width: size.width, height: logoQueueHeight)
                    SimpleMeterView(config: simpleMeter, onIsland: !separatesAgents)
                        .frame(width: strip.width, height: strip.height)
                        .position(x: strip.midX, y: strip.midY)
                        .frame(width: bounds.width, height: bounds.height)
                        .transaction { $0.animation = nil }
                }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .id(store?.settings.settings.language ?? .system)
    }

    @ViewBuilder
    var content: some View {
        if isOpen, showsAlertDetails, let alert {
            Group {
                if alert.isSessionEvent {
                    IslandEventPanelView(alert: alert, onOpen: onOpenAlert, onDecide: onDecideAlert,
                                         onDismiss: onDismissAlert,
                                         onOpenSession: onOpenAlertSession, onOpenUsage: onOpenAlertUsage,
                                         sessionNavigationFailed: sessionNavigationFailed,
                                         events: sessionEvents, waitingRequests: waitingRequests,
                                         onSelectRequest: onSelectRequest)
                } else {
                    IslandAlertDetailView(alert: alert, onOpen: onOpenAlert, onDecide: onDecideAlert,
                                          onDismiss: onDismissAlert,
                                          onOpenSession: onOpenAlertSession, onOpenUsage: onOpenAlertUsage,
                                          sessionNavigationFailed: sessionNavigationFailed,
                                          waitingRequests: waitingRequests, onSelectRequest: onSelectRequest)
                }
            }
                .padding(hidesSilhouette ? dockInsets : alert.detailInsets.map {
                    // Never under the silhouette: a notch is 38 pt of hardware on some Macs, and a card narrower
                    // than the usage panel sits squarely in its shadow rather than beside it. A screenshot cannot
                    // show that, which is why the number has to come from the screen and not from the panel.
                    EdgeInsets(top: max($0.top, collapsedSize.height), leading: $0.leading,
                               bottom: $0.bottom, trailing: $0.trailing)
                } ?? EdgeInsets(top: collapsedSize.height + alert.detailTopInset, leading: 24, bottom: 22, trailing: 24))
                .frame(width: alert.detailWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height) })
                .onPreferenceChange(PanelHeightKey.self, perform: onContentHeight)
                .transition(detailTransition)
        } else if isOpen, let store {
            HoverPanelView(store: store, onOpenStats: onOpenStats, onOpenSettings: onOpenSettings,
                           additionalHUDControls: additionalHUDControls,
                           height: panelPresentationHeight,
                           alert: alert, onOpenAlert: onOpenAlert, onOpenAlertSession: onOpenAlertSession,
                           onOpenAlertUsage: onOpenAlertUsage, sessionNavigationFailed: sessionNavigationFailed,
                           onOpenListedSession: onOpenListedSession, failedListedSessionID: failedListedSessionID,
                           onDecideAlert: onDecideAlert,
                           waitingRequests: waitingRequests,
                           insets: hidesSilhouette ? dockInsets : HoverPanelView.notchInsets,
                           answeringSessionID: answeringSessionID, onAnswerSession: onAnswerSession,
                           focusVendor: focusVendor)
                .frame(width: focusVendor == nil ? IslandController.expandedWidth
                              : Self.agentPanelWidth(edge: edge, collapsedSize: collapsedSize), alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .onPreferenceChange(PanelHeightKey.self, perform: onContentHeight)
                .transition(detailTransition)
        } else if let alert {
            if hidesSilhouette {
                IslandAlertCompactView(alert: alert, cameraWidth: 0, height: Self.dockCompactRowHeight, onOpen: onOpenAlert,
                                       waitingRequests: waitingRequests)
                    .padding(Self.dockCompactInsets)
                    .frame(width: Self.dockCompactSize(edge: edge, collapsedSize: collapsedSize).width)
                    // Beside the marks rather than in their place, when they stay.
                    .padding(focusVendor == nil ? EdgeInsets() : Self.stripClearance(edge: edge, collapsedSize: collapsedSize))
                    .offset(floats ? liftCentring : .zero)
                    .id(alert.id)
                    .transition(detailTransition)
            } else {
                IslandAlertCompactView(alert: alert,
                                      cameraWidth: collapsedSize.width - collapsedTopRadius * 2,
                                      height: max(38, collapsedSize.height), onOpen: onOpenAlert,
                                      waitingRequests: waitingRequests)
                    .id(alert.id)
                    .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.08)))
            }
        }
    }

    /// Only the strip's thickness is clearance. A long vertical queue must not turn into top padding.
    static func dockInsets(edge: HUDEdge, collapsedSize: CGSize) -> EdgeInsets {
        let strip = edge.isHorizontal ? collapsedSize.height : collapsedSize.width
        var insets = EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        switch edge {
        case .top: insets.top = strip + 12
        case .bottom: insets.bottom = strip + 12
        case .left: insets.leading = strip + 12
        case .right: insets.trailing = strip + 12
        }
        return insets
    }

    /// The strip's thickness on the parked side: what a card leaves free when the marks stay on top of it.
    static func stripClearance(edge: HUDEdge, collapsedSize: CGSize) -> EdgeInsets {
        let strip = edge.isHorizontal ? collapsedSize.height : collapsedSize.width
        switch edge {
        case .top: return EdgeInsets(top: strip, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: strip, trailing: 0)
        case .left: return EdgeInsets(top: 0, leading: strip, bottom: 0, trailing: 0)
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: strip)
        }
    }

    /// One agent's panel is narrower than the whole one. On a side edge the strip takes its thickness out of
    /// the panel's width, so the panel is that much wider and its rows keep the room they are laid out for.
    static func agentPanelWidth(edge: HUDEdge, collapsedSize: CGSize) -> CGFloat {
        IslandController.agentPanelWidth + (edge.isHorizontal ? 0 : collapsedSize.width)
    }

    /// A compact event beside the marks it came from: the compact row and the strip it must not cover.
    static func dockCompactSize(edge: HUDEdge, collapsedSize: CGSize, besideMarks: Bool) -> CGSize {
        let core = dockCompactSize(edge: edge, collapsedSize: collapsedSize)
        guard besideMarks else { return core }
        let clearance = stripClearance(edge: edge, collapsedSize: collapsedSize)
        return CGSize(width: core.width + clearance.leading + clearance.trailing,
                      height: core.height + clearance.top + clearance.bottom)
    }

    static func dockCompactSize(edge: HUDEdge, collapsedSize: CGSize) -> CGSize {
        // Events replace the marks, so their row needs no queue clearance. The window adds the
        // contact shoulders along its parked edge once, outside this compact content core.
        let insets = dockCompactInsets
        let textWidth = 2 * IslandController.alertWingWidth + 2 * IslandController.alertSidePadding
        return CGSize(width: textWidth + insets.leading + insets.trailing,
                      height: dockCompactRowHeight + insets.top + insets.bottom)
    }

    private var dockInsets: EdgeInsets { Self.dockInsets(edge: edge, collapsedSize: collapsedSize) }

    /// Simple mode's silhouette floats off its edge instead of flaring into it.
    private var floats: Bool { simpleMeter != nil }

    /// A floating silhouette gives up `edgeMargin` on its edge side; a row centred in the card moves half of
    /// that inward to sit centred in what is left.
    private var liftCentring: CGSize {
        let half = SimpleMeterConfig.edgeMargin / 2
        switch edge {
        case .top: return CGSize(width: 0, height: half)
        case .bottom: return CGSize(width: 0, height: -half)
        case .left: return CGSize(width: half, height: 0)
        case .right: return CGSize(width: -half, height: 0)
        }
    }

    /// Side flares live above and below the content core. The fixed-height usage panel stays upright,
    /// centred between those shoulders, and the reported natural height still describes only the core.
    private var panelPresentationHeight: CGFloat? {
        guard let height = presentationFrame?.height ?? presentationSize?.height else { return nil }
        return hidesSilhouette && !edge.isHorizontal ? max(0, height - 2 * Self.expandedTopRadius) : height
    }

    private var surfaceAlignment: Alignment {
        IslandAnimation.attachmentAlignment(for: hidesSilhouette ? edge : .top)
    }

    private var geometryAnimation: Animation? {
        animatesGeometry && !reduceMotion ? IslandAnimation.curve : nil
    }

    private var detailTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let offset = IslandAnimation.entryOffset(for: hidesSilhouette ? edge : .top)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(offset)).animation(.easeOut(duration: 0.22).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }
}
