import SwiftUI
import AgentHUDCore

/// Says that the panel shows a layout an agent proposed and nobody has saved, and lets a person keep it or drop it.
/// It sits above the footer, outside the scrolling content, for as long as the draft waits.
struct PanelDraftBar: View {
    let layout: PanelLayoutStore
    private let theme = Theme.island
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.dashed")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.status(.warning))
            Text(L10n.text("布局未保存", "Unsaved layout"))
                .font(.ui(12, .medium))
                .foregroundStyle(theme.text)
            Text(L10n.text("重启后丢弃", "Dropped on restart"))
                .font(.ui(11))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button { change { layout.discard() } } label: {
                Text(L10n.text("放弃", "Discard"))
                    .font(.ui(11, .medium)).lineLimit(1)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 9).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.cardBorder, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("island-layout-discard")
            Button { change { layout.save() } } label: {
                Text(L10n.text("保存", "Save"))
                    .font(.ui(11, .medium)).lineLimit(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(theme.text, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("island-layout-save")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, IslandRowLayout.inset)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.text.opacity(0.06)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("布局未保存", "Unsaved layout"))
    }

    private func change(_ body: () -> Void) {
        withAnimation(reduceMotion ? nil : IslandAnimation.curve, body)
    }
}
