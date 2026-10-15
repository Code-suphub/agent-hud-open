import SwiftUI
import AgentHUDCore

struct QuotaForecastDetails: View {
    let agent: AgentDescriptor
    let hint: String
    /// The tokens of the HUD the row is in, which the popover hands on to its own window (`IslandHoverPopover`).
    @Environment(\.hudTheme) private var theme

    var body: some View {
        Text(hint)
            .font(.ui(12, .medium))
            .monospacedDigit()
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.raisedSurface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardBorder))
            .fixedSize()
            .accessibilityLabel("\(agent.displayName), \(hint)")
    }
}
