import AppKit
import SwiftUI
import AgentHUDCore

/// A nonmodal credential window near the HUD. It never occupies the agents' permission-request queue.
@MainActor
final class BalanceAuthenticationCenter {
    static let shared = BalanceAuthenticationCenter()
    private weak var store: UsageStore?
    private var openSettings: () -> Void = {}
    private var reminders = BalanceAuthenticationReminders()
    private var windows: [String: BalanceAuthenticationWindow] = [:]

    func configure(store: UsageStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
        sync()
    }

    func sync() {
        guard let store else { return }
        let profiles = store.settings.settings.customBalances
        let required = Set(profiles.filter(\.enabled).filter { profile in
            store.report?.billing.contains { $0.billingPool?.id == CustomBalanceUsageProvider.pool(profile).id && $0.requiresAuthentication == true } == true
        }.map(\.id))
        reminders.update(required: required)
        for id in Array(windows.keys) where !profiles.contains(where: { $0.id == id }) {
            windows[id]?.close()
        }
        // Recovery closes a failure prompt; manually opened renewal windows may stay while their source is healthy.
        for id in Array(windows.keys) where windows[id]?.automatic == true && !required.contains(id) {
            windows[id]?.close()
        }
        if windows.isEmpty, !store.isPaused, let next = reminders.waiting.first { show(profileID: next, automatic: true) }
    }

    func show(profileID: String, automatic: Bool = false) {
        let screen = ScreenIdentity.underPointer()
        if let window = windows[profileID] {
            window.reveal(activate: !automatic, on: automatic ? nil : screen)
            return
        }
        guard let store, let profile = store.settings.settings.customBalances.first(where: { $0.id == profileID && ($0.enabled || !automatic) }) else { return }
        let controller = BalanceAuthenticationWindow(profile: profile, store: store, automatic: automatic, openSettings: { [weak self] in
            self?.openSettings()
        }, onClose: { [weak self] in
            guard let self else { return }
            self.reminders.acknowledge(profileID)
            self.windows.removeValue(forKey: profileID)
            Task { @MainActor [weak self] in self?.sync() }
        })
        windows[profileID] = controller
        controller.reveal(activate: !automatic, on: screen)
    }
}

@MainActor
private final class BalanceAuthenticationWindow: NSWindowController, NSWindowDelegate {
    let automatic: Bool
    private let onClose: () -> Void

    init(profile: CustomBalanceProfile, store: UsageStore, automatic: Bool, openSettings: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.automatic = automatic; self.onClose = onClose
        let panel = BalanceAuthPanel(contentRect: NSRect(x: 0, y: 0, width: BalanceAuthenticationForm.width, height: 1),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.text("更新余额认证", "Update balance credentials")
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        super.init(window: panel)
        panel.delegate = self
        let content = BalanceAuthenticationForm(profile: profile, store: store, automatic: automatic,
            onClose: { [weak self] in self?.close() }, openSettings: { [weak self] in self?.close(); openSettings() })
        let hosting = NSHostingView(rootView: content.ignoresSafeArea().onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] height in
            Task { @MainActor in self?.resize(to: height) }
        })
        let fittingHeight = hosting.fittingSize.height
        hosting.sizingOptions = []
        panel.contentView = hosting
        resize(to: fittingHeight)
    }

    private func resize(to height: CGFloat) {
        guard let window, height.isFinite, height > 0 else { return }
        let content = NSRect(x: 0, y: 0, width: BalanceAuthenticationForm.width, height: ceil(height))
        let size = window.frameRect(forContentRect: content).size
        let current = window.frame
        guard current.size != size else { return }
        let frame = NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        let visible = window.isVisible
        window.setFrame(visible ? window.constrainFrameRect(frame, to: window.screen) : frame, display: visible)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func windowWillClose(_ notification: Notification) { onClose() }
    func reveal(activate: Bool, on screen: NSScreen?) {
        guard let window else { return }
        if let screen, !window.isVisible || window.screen.map(ScreenIdentity.key(for:)) != ScreenIdentity.key(for: screen) {
            let bounds = screen.visibleFrame
            let size = window.frame.size
            let frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - 55,
                               width: size.width, height: size.height)
            window.setFrame(window.constrainFrameRect(frame, to: screen), display: window.isVisible)
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}

private final class BalanceAuthPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct BalanceAuthenticationForm: View {
    static let width: CGFloat = 490
    let profile: CustomBalanceProfile
    let store: UsageStore
    var automatic = true
    var onClose: () -> Void = {}
    var openSettings: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private let original: BalanceRequest?
    @State private var values: [String: String] = [:]
    @State private var error: String?
    @State private var saving = false
    @State private var task: Task<Void, Never>?

    init(profile: CustomBalanceProfile, store: UsageStore, automatic: Bool = true, onClose: @escaping () -> Void = {},
         openSettings: @escaping () -> Void = {}, initialRequest: BalanceRequest? = nil) {
        self.profile = profile; self.store = store; self.automatic = automatic
        self.onClose = onClose; self.openSettings = openSettings
        do {
            original = try initialRequest ?? BalanceRequestStore.load(id: profile.id)
        } catch {
            original = nil
            _error = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        let theme = Theme.forScheme(scheme)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill").foregroundStyle(theme.statusText(.warning))
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).font(.ui(16, .semibold))
                    Text(automatic ? L10n.text("认证已失效或权限不足", "Authentication expired or access denied") : L10n.text("更新认证凭据", "Update credentials"))
                        .font(.ui(12)).foregroundStyle(theme.secondary)
                }
                Spacer()
                if let website = profile.websiteURL {
                    Link(destination: website) {
                        Label(L10n.text("打开官网", "Open website"), systemImage: "arrow.up.right.square")
                    }
                    .font(.ui(12)).help(website.absoluteString)
                }
            }
            if let original, !original.credentialHeaderNames.isEmpty {
                Text(L10n.text("填写新的 Cookie 或 Token。留空的项目会保留，验证成功后自动恢复监控。", "Update the Cookie or token that changed; blank fields are kept. Monitoring resumes after verification."))
                    .font(.ui(12)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
                let names = original.credentialHeaderNames
                if names.count > 4 {
                    ScrollView { credentialFields(names) }.frame(height: 200)
                } else {
                    credentialFields(names)
                }
                if let host = original.url.host {
                    Text(L10n.text("仅发送到：", "Sent only to: ") + host).font(.ui(11)).foregroundStyle(theme.secondary)
                }
            } else if original != nil {
                Text(L10n.text("这个请求没有标记认证字段。请在设置中重新导入 curl，并选择需要更新的认证项。", "This request has no renewable fields. Import cURL in Settings and mark its authentication fields."))
                    .font(.ui(12)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).font(.ui(11)).foregroundStyle(theme.statusText(.warning)).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(L10n.text("前往设置", "Settings"), action: openSettings).disabled(saving)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(L10n.text("稍后", "Later"), action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.text("验证并更新", "Verify and update")) { renew() }.keyboardShortcut(.defaultAction)
                    .disabled(saving || !values.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            }
        }
        .padding(24).padding(.top, 12)
        .frame(width: Self.width).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(theme.text).background(theme.windowBackground)
        .onDisappear { task?.cancel() }
    }

    private func credentialFields(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(names, id: \.self) { name in
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.ui(11, .medium)).lineLimit(1)
                    SecureField(name.lowercased() == "cookie" ? "session=…; token=…" : L10n.text("输入新的值", "Enter a new value"),
                        text: Binding(get: { values[name] ?? "" }, set: { values[name] = $0 }))
                        .textFieldStyle(.roundedBorder).disabled(saving)
                }
            }
        }
    }

    private func renew() {
        guard let original else { return }
        saving = true; error = nil
        task = Task {
            defer { saving = false }
            do {
                let updated = try original.replacingCredentials(values)
                let fields = try await BalanceRequestClient.fetch(updated)
                try Task.checkCancellation()
                _ = try profile.amounts(in: fields)
                guard store.settings.settings.customBalances.contains(profile), try BalanceRequestStore.load(id: profile.id) == original else {
                    throw UsageProviderError(L10n.text("配置已变化，请关闭后重新打开", "Configuration changed; close and reopen this window"))
                }
                try BalanceRequestStore.save(updated, id: profile.id)
                store.settings.update { preferences in
                    if let index = preferences.customBalances.firstIndex(where: { $0.id == profile.id }) {
                        preferences.customBalances[index].credentialRevision = (profile.credentialRevision ?? 0) + 1
                    }
                }
                Task { await store.refreshAccounts() }
                onClose()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
