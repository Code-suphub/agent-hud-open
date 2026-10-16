import AppKit
import SwiftUI
import AgentHUDCore

/// What the menu-bar menu shows, which its panel changes and its view draws: the entries, how many of them fit from the
/// top, the row under the pointer or the arrow keys, and the look of the screen it opened on.
@MainActor @Observable
final class StatusMenuModel {
    var entries: [StatusMenuEntry] = []
    /// The entries drawn, from the top: all of them unless the screen is too short for the menu
    /// (`StatusMenuLayout.shownCount`).
    var shownCount = 0
    var highlighted: Int?
    var look: HUDLook
    var size: CGSize = .zero

    init(look: HUDLook) {
        self.look = look
    }
}

/// The menu as it is drawn: its rows on a surface of the look (`HUDSurface`), glass, a material or a solid fill thinned
/// by the screen's transparency, with the hairline Liquid Glass leaves out for its own rim. The rows take the look's ink,
/// and the highlighted one the system's selection colour with white text, as a macOS menu's does. VoiceOver reads the
/// panel's own elements instead (`StatusMenuContentView`).
struct StatusMenuView: View {
    let model: StatusMenuModel

    var body: some View {
        let look = model.look
        let theme = look.theme
        let shape = RoundedRectangle(cornerRadius: StatusMenuLayout.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(model.entries.prefix(model.shownCount).enumerated()), id: \.offset) { index, entry in
                if entry.kind == .separator {
                    Rectangle().fill(theme.divider)
                        .frame(height: 1)
                        .padding(.horizontal, StatusMenuLayout.inset)
                        .frame(height: StatusMenuLayout.separatorHeight)
                } else {
                    StatusMenuRow(entry: entry, theme: theme, look: look, highlighted: model.highlighted == index)
                }
            }
        }
        .padding(.vertical, StatusMenuLayout.verticalInset)
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .background(HUDSurface(shape, look: look, fill: theme.raisedSurface, contact: nil)
            .environment(\.drawsRegularGlass, true))
        .overlay(shape.strokeBorder(look.outline(theme.cardBorder, standIn: false)))
        .hudLook(look)
        .accessibilityHidden(true)
    }
}

private struct StatusMenuRow: View {
    let entry: StatusMenuEntry
    let theme: Theme
    let look: HUDLook
    let highlighted: Bool

    private var selectedText: Color { Color(nsColor: .selectedMenuItemTextColor) }

    var body: some View {
        HStack(spacing: 0) {
            icon
                .frame(width: StatusMenuLayout.iconWidth, height: StatusMenuLayout.iconWidth)
                .padding(.trailing, StatusMenuLayout.iconGap)
            Text(entry.title)
                .font(.system(size: entry.weight.size, weight: entry.weight == .agent ? .bold : .regular))
                .foregroundStyle(highlighted ? selectedText : entry.titleInk.color(in: theme))
                .lineLimit(1)
            Spacer(minLength: StatusMenuLayout.valueGap)
            Text(entry.value)
                .font(.system(size: entry.weight.size).monospacedDigit())
                .foregroundStyle(highlighted ? selectedText : entry.valueInk.color(in: theme))
                .lineLimit(1)
        }
        .padding(.horizontal, StatusMenuLayout.inset)
        .frame(height: StatusMenuLayout.rowHeight)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: StatusMenuLayout.selectionRadius, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor))
                    .padding(.horizontal, StatusMenuLayout.selectionInset)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        let ink = highlighted ? selectedText : entry.titleInk.color(in: theme)
        switch entry.icon {
        case .none:
            Color.clear
        case .artwork(let vendor):
            if let image = AgentArtwork.image(for: vendor, dark: look.appearance == .dark) {
                picture(image, ink: ink)
            }
        case .dot(let level):
            Circle().fill(level.map(theme.status) ?? theme.tertiary)
                .frame(width: 7, height: 7)
        case .image(let image):
            picture(image, ink: ink)
        case .state(let state):
            if state == .on || state == .mixed {
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink)
            }
        }
    }

    private func picture(_ image: NSImage, ink: Color) -> some View {
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: min(image.size.width, StatusMenuLayout.iconWidth),
                   height: min(image.size.height, StatusMenuLayout.iconWidth))
            .foregroundStyle(ink)
    }
}
