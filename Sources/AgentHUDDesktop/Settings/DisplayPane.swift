import AppKit
import SwiftUI
import AgentHUDCore

struct DisplayPane: View {
    let settings: SettingsStore
    let store: UsageStore
    let theme: Theme
    /// Which display the panes below are editing. Owned here so the glow preview can show that screen's
    /// mode rather than always the notch.
    @State private var screen: String = ScreensPane.attached().first?.key ?? ""
    /// Reduce Transparency and macOS's own light or dark setting, which a screen's look is resolved from as well as from
    /// its settings, and which SwiftUI does not see there (`SettingsStore.effectiveLook(on:)`). Both are held here so
    /// that the look is resolved again, and every preview below drawn again, as either is switched: macOS's setting too
    /// while the app's Appearance holds this window to its own.
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @State private var systemIsLight = SystemAppearance.isLight

    private var selection: NSScreen? {
        NSScreen.screens.first { ScreenIdentity.key(for: $0) == screen } ?? NSScreen.main
    }

    /// The selected screen's placement as its HUD draws it now, an agent's unsaved style included.
    private var placement: ScreenPlacement {
        guard let selection else { return .default(hasNotch: false) }
        return ScreenIdentity.placement(for: selection, in: settings)
    }

    /// The selected screen's look, which every preview below is drawn in.
    private var look: HUDLook {
        // Read for SwiftUI to draw the panes again when either changes; the look reads both from the Mac itself.
        _ = (reducesTransparency, systemIsLight)
        return settings.effectiveLook(on: screen)
    }

    var body: some View {
        let look = look
        VStack(alignment: .leading, spacing: 28) {
            ScreensPane(settings: settings, store: store, theme: theme, look: look, selected: $screen)
            // Simple mode draws no glow, so its screen has no glow settings to show.
            if placement.mode != .simple {
                GlowPane(settings: settings, store: store, theme: theme, placement: placement,
                         metrics: ScreenMetrics(screen: selection), screen: screen, look: look)
            }
            // The samples show the panel in the selected screen's look.
            IslandPane(settings: settings, theme: theme, look: look)
            SettingsSection(title: L10n.text("菜单栏", "Menu bar"), theme: theme) {
                SettingsToggleRow(
                    label: L10n.text("显示菜单栏图标", "Show menu bar icon"),
                    subtitle: L10n.text("快速查看用量、刷新数据和打开设置。", "Quick access to usage, refresh and settings."),
                    isOn: settings.binding(\.showMenuBarIcon)
                )
            }
        }
        .onReceive(DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)) { _ in
            systemIsLight = SystemAppearance.isLight
        }
    }
}

/// Decorative wallpaper for the glow preview. A HUD of glass is previewed with its stand-in, its tint over the
/// wallpaper: a blur in the Settings window would show the desktop behind the window, not the wallpaper painted in it.
struct SettingsPreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.drawsGlassStandIn, true)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    Image(nsImage: SettingsPreviewArtwork.wallpaper)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .accessibilityHidden(true)
            // A glow reaches past the box it is previewed in, and the preview sits in front of the rows
            // above it. Left interactive, that overhang silently swallows their clicks: AppKit-backed
            // controls keep working because they are real views, and plain SwiftUI buttons stop responding.
            .allowsHitTesting(false)
    }
}

@MainActor
private enum SettingsPreviewArtwork {
    static let wallpaper = NSImage(contentsOf: AppResources.bundle.url(forResource: "settings-wallpaper", withExtension: "png")!)!
}
