import SwiftUI
import AgentHUDCore

/// One screen's panel layout, in that screen's part of Settings → Display: whether the screen uses the shared layout or
/// its own, in which state, and what a person can do about it. A click takes effect at once, where an agent's change
/// waits in the panel to be saved.
struct ScreenLayoutRow: View {
    let layout: PanelLayoutStore
    let screen: String

    private var scope: PanelLayoutScope { .screen(screen) }
    /// Whether the screen keeps a layout of its own, saved or as its draft.
    private var hasOwn: Bool { layout.ownLayout(of: screen) != nil || layout.draft(of: screen)?.layout != nil }

    var body: some View {
        SettingRow(label: L10n.text("面板布局", "Panel layout"), subtitle: status) {
            HStack(spacing: 8) {
                if hasOwn || layout.draft(of: screen) != nil {
                    Button(L10n.text("使用共用布局", "Use Shared Layout")) { layout.useShared(screen) }
                        .accessibilityIdentifier("settings-screen-layout-shared")
                }
                Button(L10n.text("恢复上一版", "Revert to Previous")) { layout.revert(scope) }
                    .disabled(!layout.canRevert(scope))
                    .accessibilityIdentifier("settings-screen-layout-revert")
                if hasOwn {
                    Button(L10n.text("恢复默认", "Reset to Default")) { layout.reset(scope) }
                        .disabled(layout.ownLayout(of: screen)?.isDefault == true && layout.draft(of: screen) == nil)
                        .accessibilityIdentifier("settings-screen-layout-reset")
                }
            }
            .controlSize(.small)
        }
    }

    /// Which layout the screen's panel draws, and in which state.
    private var status: String {
        switch layout.draft(of: screen) {
        case .own?:
            return L10n.text("面板正显示这块屏幕未保存的布局", "The panel shows an unsaved layout for this display")
        case .shared?:
            return L10n.text("面板正显示未保存的改动：改用共用布局", "The panel shows an unsaved change: back to the shared layout")
        case nil:
            break
        }
        if let own = layout.ownLayout(of: screen) {
            return own.isDefault ? L10n.text("这块屏幕自己的布局：默认布局", "Its own layout: the default layout")
                : L10n.text("这块屏幕自己的自定义布局", "Its own custom layout")
        }
        return layout.hasDraft ? L10n.text("使用共用布局，面板正显示它未保存的改动", "Uses the shared layout, which has an unsaved change in the panel")
            : L10n.text("使用共用布局", "Uses the shared layout")
    }
}

/// The shared layout, once in Settings → Display → Expanded panel: its state, which displays use it, and the two buttons
/// that take effect at once.
struct SharedLayoutRow: View {
    let layout: PanelLayoutStore
    /// The attached displays, of which the row names those that use the shared layout.
    let screens: [ScreensPane.Screen]

    var body: some View {
        SettingRow(label: L10n.text("共用布局", "Shared layout"), subtitle: status + "\n" + users) {
            HStack(spacing: 8) {
                Button(L10n.text("恢复上一版", "Revert to Previous")) { layout.revert() }
                    .disabled(!layout.canRevert)
                    .accessibilityIdentifier("settings-layout-revert")
                Button(L10n.text("恢复默认", "Reset to Default")) { layout.reset() }
                    .disabled(layout.current.isDefault && !layout.hasDraft)
                    .accessibilityIdentifier("settings-layout-reset")
            }
            .controlSize(.small)
        }
    }

    /// Which of its three states the shared layout is in.
    private var status: String {
        if layout.hasDraft { return L10n.text("面板正显示未保存的布局", "The panel shows an unsaved layout") }
        return layout.current.isDefault ? L10n.text("默认布局", "Default layout") : L10n.text("自定义布局", "Custom layout")
    }

    /// The displays whose panel draws the shared layout now.
    private var users: String {
        let names = screens.filter { layout.usesShared($0.key) }.map(\.name)
        guard !names.isEmpty else {
            return L10n.text("每块显示器都在用自己的布局。", "Every display uses a layout of its own.")
        }
        return L10n.text("使用它的显示器：", "Used by ") + names.joined(separator: L10n.text("、", ", "))
    }
}
