import SwiftUI
import UniformTypeIdentifiers
import AgentHUDCore

struct CustomAvatarEditor: View {
    let profile: CustomBalanceProfile
    let settings: SettingsStore
    let theme: Theme
    @Environment(\.dismiss) private var dismiss
    private enum Mode: String { case none, emoji, image }
    @State private var mode: Mode
    @State private var emoji: String
    @State private var png: Data?
    @State private var animated: Bool
    @State private var importing = false
    @State private var error: String?

    init(profile: CustomBalanceProfile, settings: SettingsStore, theme: Theme) {
        self.profile = profile; self.settings = settings; self.theme = theme
        _mode = State(initialValue: profile.avatar?.imagePNG != nil ? .image : profile.avatar?.emoji != nil ? .emoji : .none)
        _emoji = State(initialValue: profile.avatar?.emoji ?? "🤖")
        _png = State(initialValue: profile.avatar?.imagePNG)
        _animated = State(initialValue: profile.avatar?.animated ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("自定义头像", "Custom avatar")).font(.ui(20, .semibold))
            Text(profile.name).font(.ui(12)).foregroundStyle(theme.secondary)
            Picker(L10n.text("头像来源", "Avatar source"), selection: $mode) {
                Text(L10n.text("默认", "Default")).tag(Mode.none)
                Text("Emoji").tag(Mode.emoji)
                Text(L10n.text("本地图片", "Local image")).tag(Mode.image)
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 20) {
                Group {
                    if let draft, let image = CustomAvatarRegistry.render(draft) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else { Text(String(profile.name.prefix(1))).font(.system(size: 36, weight: .semibold)) }
                }
                .frame(width: 72, height: 72).padding(12)
                .background(theme.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                if mode == .emoji {
                    TextField(L10n.text("输入 Emoji 或文字", "Emoji or text"), text: $emoji).textFieldStyle(.roundedBorder)
                } else if mode == .image {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(L10n.text("选择图片…", "Choose image…")) { importing = true }
                        Text("PNG / JPEG / WebP").font(.ui(11)).foregroundStyle(theme.secondary)
                    }
                } else { Text(L10n.text("显示名称首字母", "Show the name’s initial")).font(.ui(12)).foregroundStyle(theme.secondary) }
            }
            Toggle(L10n.text("启用跳动动画", "Animate avatar"), isOn: $animated).toggleStyle(.switch).disabled(mode == .none)
            Text(L10n.text("沿用智能体的跳动和呼吸动画，保留头像原貌。系统开启“减少动态效果”时静止显示。", "Uses the agents’ hop and breathing motions while preserving your artwork. Respects Reduce Motion."))
                .font(.ui(11)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.ui(12)).foregroundStyle(theme.statusText(.warning)) }
            HStack {
                Spacer()
                Button(L10n.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("保存", "Save")) { save() }.keyboardShortcut(.defaultAction)
                    .disabled(mode != .none && draft == nil)
            }
        }
        .padding(24).frame(width: 440).foregroundStyle(theme.text).background(theme.windowBackground)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .webP]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 10_485_760 else { throw UsageProviderError(L10n.text("图片请小于 10 MB", "Choose an image below 10 MB")) }
                png = try CustomAvatarRegistry.normalizedPNG(Data(contentsOf: url)); error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private var draft: CustomBalanceAvatar? {
        switch mode {
        case .none: nil
        case .emoji: try? CustomBalanceAvatar(emoji: emoji, animated: animated)
        case .image: png.flatMap { try? CustomBalanceAvatar(imagePNG: $0, animated: animated) }
        }
    }
    private func save() {
        let avatar = draft
        guard mode == .none || avatar != nil else { return }
        settings.update { preferences in
            if let index = preferences.customBalances.firstIndex(where: { $0.id == profile.id }) {
                preferences.customBalances[index].avatar = avatar
            }
        }
        dismiss()
    }
}
