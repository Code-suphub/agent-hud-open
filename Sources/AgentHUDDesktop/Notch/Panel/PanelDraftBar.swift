import SwiftUI
import AgentHUDCore

/// Says that the panel shows a layout an agent proposed and nobody has saved, that its screen's resting HUD shows a style
/// an agent proposed, or that the app draws its own settings as an agent proposed them, and lets a person keep it or drop
/// it. It sits above the footer, outside the scrolling content, for as long as the draft waits. It acts on the document
/// the panel draws (`PanelLayoutStore.draftScope(on:)`), its screen's own draft or the shared draft, which shows its bar
/// on every screen that uses it, on the screen's style draft, so one Save keeps both as one version, and on the app's
/// draft, which shows the bar on every screen, so that a draft that hides the menu-bar icon still has its Save and
/// Discard on the HUD.
struct PanelDraftBar: View {
    let layout: PanelLayoutStore
    /// The key of the screen whose panel this is; nil for the shared layout's.
    let screen: String?
    @Environment(\.hudTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What waits: a layout, with or without a style, a style alone, or the app's settings alone; the note says when the
    /// app's settings wait beside a layout or a style.
    private var title: String {
        if layout.draftScope(on: screen) != nil { return L10n.text("布局未保存", "Unsaved layout") }
        if layout.hasStyleDraft(screen) { return L10n.text("HUD 样式未保存", "Unsaved HUD style") }
        return L10n.text("应用设置未保存", "Unsaved app settings")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.dashed")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.statusText(.warning))
            Text(title)
                .font(.ui(12, .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            // An agent's own panel on a separated dock is narrower than the whole panel: where a screen's note does not
            // fit there, it says only that the draft is this display's.
            ViewThatFits(in: .horizontal) {
                noteText(note.full)
                noteText(note.short)
            }
            Spacer(minLength: 8)
            Button { change { layout.discardPanel(on: screen) } } label: {
                Text(L10n.text("放弃", "Discard"))
                    .font(.ui(11, .medium)).lineLimit(1)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 9).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.cardBorder, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("island-layout-discard")
            Button { change { layout.savePanel(on: screen) } } label: {
                Text(L10n.text("保存", "Save"))
                    .font(.ui(11, .medium)).lineLimit(1)
                    .foregroundStyle(theme.inverseText)
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
        .accessibilityLabel(title)
    }

    /// When the draft goes, and for a screen's own draft or a style alone that it is this display's alone, or that the
    /// app's settings, every display's, wait beside it; `short` where `full` does not fit on one line.
    private var note: (full: String, short: String) {
        let restart = L10n.text("重启后丢弃", "Dropped on restart")
        if layout.appDraft != nil {
            guard layout.draftScope(on: screen) != nil || layout.hasStyleDraft(screen) else { return (restart, restart) }
            return (L10n.text("含应用设置，重启后丢弃", "With app settings, dropped on restart"),
                    L10n.text("含应用设置", "With app settings"))
        }
        switch layout.draftScope(on: screen) {
        case .shared?:
            return (restart, restart)
        case .screen?, nil:
            return (L10n.text("仅此显示器，重启后丢弃", "This display only, dropped on restart"),
                    L10n.text("仅此显示器", "This display only"))
        }
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.ui(11))
            .foregroundStyle(theme.secondary)
            .lineLimit(1)
    }

    private func change(_ body: () -> Void) {
        withAnimation(reduceMotion ? nil : IslandAnimation.curve, body)
    }
}
