import SwiftUI
import AgentHUDCore

struct CustomBalancesPane: View {
    let settings: SettingsStore
    let store: UsageStore
    let theme: Theme
    @State private var editing: CustomBalanceProfile?
    @State private var adding = false
    @State private var avatarEditing: CustomBalanceProfile?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: L10n.text("自定义余额", "Custom balances"),
                subtitle: L10n.text("导入查询请求，选择响应字段，自动更新悬浮面板。", "Import a query and map response fields to a balance in the hover panel."), theme: theme) {
                if settings.settings.customBalances.isEmpty {
                    Text(L10n.text("还没有添加余额来源", "No balance sources yet"))
                        .font(.ui(12)).foregroundStyle(theme.secondary)
                        .padding(16)
                }
                ForEach(settings.settings.customBalances) { profile in
                    HStack(spacing: 12) {
                        Button { avatarEditing = profile } label: { AgentLogo(vendor: profile.name, size: 28) }
                            .buttonStyle(.plain)
                            .disabled(AgentArtwork.fileNames[AgentArtwork.markKey(profile.name)] != nil)
                            .help(L10n.text("设置头像与跳动动画；内置智能体保留原头像", "Customize avatar and motion; built-in agents retain their artwork"))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.ui(13, .medium))
                            Text(status(profile)).font(.ui(11)).foregroundStyle(theme.secondary).lineLimit(2)
                        }
                        Spacer()
                        Toggle(L10n.text("启用", "Enabled"), isOn: Binding(get: {
                            settings.settings.customBalances.first { $0.id == profile.id }?.enabled ?? false
                        }, set: { value in
                            settings.update { preferences in
                                if let index = preferences.customBalances.firstIndex(where: { $0.id == profile.id }) {
                                    preferences.customBalances[index].enabled = value
                                }
                            }
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Button { BalanceAuthenticationCenter.shared.show(profileID: profile.id) } label: { Image(systemName: "key.horizontal") }
                            .help(L10n.text("更新认证凭据", "Update credentials"))
                        Button(L10n.text("编辑", "Edit")) { editing = profile }
                        Button(role: .destructive) { remove(profile) } label: { Image(systemName: "trash") }
                            .help(L10n.text("删除来源及其请求凭据", "Remove this source and its request credentials"))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if profile.id != settings.settings.customBalances.last?.id { SettingsDivider(theme: theme) }
                }
                if !settings.settings.customBalances.isEmpty { SettingsDivider(theme: theme) }
                HStack {
                    Button { adding = true } label: { Label(L10n.text("添加来源", "Add source"), systemImage: "plus") }
                    Spacer()
                    Button(L10n.text("立即刷新", "Refresh now")) { Task { await store.refreshAccounts() } }
                        .disabled(store.isRefreshing || settings.settings.customBalances.isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            Text(L10n.text("从浏览器复制只读余额查询为 cURL，选择要保留的请求项。约每 5 分钟刷新；认证过期可直接更新 Cookie 或 Token，凭据保存在本机配置目录。",
                           "Copy a read-only query as cURL and select the request items to keep. Refreshes about every 5 minutes; update Cookie or token values when authentication expires. Credentials stay in this Mac’s local configuration directory."))
                .font(.ui(11)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.ui(12)).foregroundStyle(theme.statusText(.warning)) }
        }
        .sheet(isPresented: $adding) { CustomBalanceEditor(settings: settings, store: store, theme: theme) }
        .sheet(item: $editing) { profile in CustomBalanceEditor(settings: settings, store: store, theme: theme, profile: profile) }
        .sheet(item: $avatarEditing) { profile in CustomAvatarEditor(profile: profile, settings: settings, theme: theme) }
    }

    private func status(_ profile: CustomBalanceProfile) -> String {
        guard profile.enabled else { return L10n.text("已暂停", "Paused") }
        guard let billing = store.report?.billing.first(where: { $0.isCustomBalance && $0.billingPool?.scope == profile.id }) else {
            return L10n.text("等待首次读取", "Waiting for the first reading")
        }
        if let notice = billing.notice { return notice }
        guard let balance = billing.balances.first else { return L10n.text("等待数据", "Waiting for data") }
        return L10n.text("余额 ", "Balance ") + CustomBalanceProfile.format(balance.total, unit: balance.currency)
    }

    private func remove(_ profile: CustomBalanceProfile) {
        do {
            try BalanceRequestStore.remove(id: profile.id)
            settings.update { $0.customBalances.removeAll { $0.id == profile.id } }
        } catch { self.error = error.localizedDescription }
    }
}

private struct CustomBalanceEditor: View {
    let settings: SettingsStore
    let store: UsageStore
    let theme: Theme
    let profile: CustomBalanceProfile?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var currency: String
    @State private var divisor: String
    @State private var valueKind: CustomBalanceProfile.ValueKind
    @State private var balancePath: String
    @State private var totalPath: String
    @State private var curl = ""
    @State private var request: BalanceRequest?
    @State private var selection: BalanceRequestSelection?
    @State private var fields: [BalanceField] = []
    @State private var isTesting = false
    @State private var error: String?
    @State private var testTask: Task<Void, Never>?
    @State private var requestRevision = 0

    init(settings: SettingsStore, store: UsageStore, theme: Theme, profile: CustomBalanceProfile? = nil) {
        self.settings = settings; self.store = store; self.theme = theme; self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _currency = State(initialValue: profile?.currency ?? "CNY")
        _divisor = State(initialValue: profile.map { NSDecimalNumber(decimal: $0.divisor).stringValue } ?? "1")
        _valueKind = State(initialValue: profile?.valueKind ?? .remaining)
        _balancePath = State(initialValue: profile?.balancePath ?? "")
        _totalPath = State(initialValue: profile?.totalPath ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                editorContent
            }.frame(maxHeight: 570)
            HStack {
                Spacer()
                Button(L10n.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("保存", "Save")) { save() }.keyboardShortcut(.defaultAction)
                    .disabled(request == nil || preview == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 650)
        .onDisappear { testTask?.cancel() }
        .task { if profile != nil { prepare() } }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(profile == nil ? L10n.text("添加余额来源", "Add balance source") : L10n.text("编辑余额来源", "Edit balance source"))
                .font(.ui(20, .semibold))
            HStack(spacing: 12) {
                TextField(L10n.text("名称，如 Bitto", "Name, e.g. Bitto"), text: $name)
                HStack(spacing: 4) {
                    TextField(L10n.text("币种 / 单位", "Currency / unit"), text: $currency).frame(width: 98)
                    Menu {
                        Button(L10n.text("人民币（CNY）", "Yuan (CNY)")) { currency = "CNY" }
                        Button(L10n.text("美元（USD）", "US dollar (USD)")) { currency = "USD" }
                        Button(L10n.text("欧元（EUR）", "Euro (EUR)")) { currency = "EUR" }
                        Button(L10n.text("额度（CREDITS）", "Credits (CREDITS)")) { currency = "CREDITS" }
                    } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(L10n.text("选择常用币种，也可直接输入自定义单位", "Choose a currency or type a custom unit"))
                }
            }
            .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("cURL").font(.ui(12, .medium))
                TextEditor(text: $curl).font(.system(size: 11, design: .monospaced))
                    .frame(height: 110).padding(5).background(theme.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .autocorrectionDisabled()
                    .onChange(of: curl) { _, _ in
                        invalidate(); selection = nil
                    }
                Text(profile == nil ? L10n.text("粘贴查询余额的请求，不会执行 Shell 命令。", "Paste a balance query. Shell commands are never executed.")
                     : L10n.text("留空可使用已保存的请求；粘贴新 curl 可更新登录凭据。", "Leave blank to use the saved request, or paste new cURL to update credentials."))
                    .font(.ui(11)).foregroundStyle(theme.secondary)
            }
            HStack {
                Button(L10n.text("解析 curl", "Parse cURL")) { prepare() }
                    .disabled(curl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && profile == nil)
                Spacer()
            }
            if selection != nil {
                BalanceRequestSelectionView(selection: Binding(get: { selection! }, set: { selection = $0 }), theme: theme,
                    onChange: { invalidate() })
            }
            HStack {
                Button { test() } label: { Label(L10n.text("请求并读取字段", "Request and inspect fields"), systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(isTesting || selection == nil)
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                if !fields.isEmpty { Text(L10n.text("读取到 \(fields.count) 个数值字段", "Found \(fields.count) numeric fields")).font(.ui(11)).foregroundStyle(theme.secondary) }
            }
            if !fields.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text(L10n.text("字段含义", "Value means"))
                        Picker("", selection: $valueKind) {
                            Text(L10n.text("剩余余额", "Remaining balance")).tag(CustomBalanceProfile.ValueKind.remaining)
                            Text(L10n.text("已用额度（总量 − 已用）", "Used amount (total − used)")).tag(CustomBalanceProfile.ValueKind.used)
                        }.labelsHidden()
                    }
                    GridRow { Text(valueKind == .remaining ? L10n.text("余额字段", "Balance field") : L10n.text("已用字段", "Used field")); fieldPicker($balancePath, optional: false) }
                    GridRow { Text(L10n.text("总量字段", "Total field")); fieldPicker($totalPath, optional: valueKind == .remaining) }
                    GridRow {
                        Text(L10n.text("单位除数", "Unit divisor"))
                        HStack { TextField("1", text: $divisor).textFieldStyle(.roundedBorder).frame(width: 110)
                            Text(L10n.text("原值 ÷ 除数；无需换算填 1", "Raw value ÷ divisor; use 1 for no conversion")).font(.ui(11)).foregroundStyle(theme.secondary) }
                    }
                }.font(.ui(12))
                if let preview {
                    HStack(spacing: 20) {
                        Text(L10n.text("余额 ", "Balance ") + CustomBalanceProfile.format(preview.balance, unit: currency.uppercased()))
                        if let total = preview.total { Text(L10n.text("总量 ", "Total ") + CustomBalanceProfile.format(total, unit: currency.uppercased())) }
                    }.font(.tabular(14, .semibold)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if let error { Text(error).font(.ui(12)).foregroundStyle(theme.statusText(.warning)).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func invalidate() {
        testTask?.cancel(); requestRevision += 1; request = nil; fields = []; isTesting = false; error = nil
    }

    private func prepare() {
        invalidate()
        do {
            let saved = curl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let definition = try saved ? BalanceRequestStore.load(id: profile!.id) : BalanceRequest.parse(curl: curl, forSelection: true)
            selection = BalanceRequestSelection(definition, preserveSavedSelection: saved)
        } catch { selection = nil; self.error = error.localizedDescription }
    }

    private func fieldPicker(_ selection: Binding<String>, optional: Bool) -> some View {
        Picker("", selection: selection) {
            Text(optional ? L10n.text("不设置", "Not set") : L10n.text("请选择", "Select a field")).tag("")
            ForEach(fields) { field in
                Text((field.path.isEmpty ? "/" : field.path) + " = " + NSDecimalNumber(decimal: field.value).stringValue).tag(field.path)
            }
        }.labelsHidden().frame(maxWidth: .infinity)
    }

    private func draft() -> CustomBalanceProfile {
        var value = CustomBalanceProfile(id: profile?.id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), balancePath: balancePath,
            totalPath: totalPath.isEmpty ? nil : totalPath, divisor: Decimal(string: divisor, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            enabled: profile?.enabled ?? true, valueKind: valueKind)
        value.avatar = profile?.avatar
        return value
    }
    private var preview: (balance: Decimal, total: Decimal?)? { try? draft().amounts(in: fields) }

    private func test() {
        error = nil; fields = []; request = nil; isTesting = true
        let revision = requestRevision
        testTask = Task {
            defer { if requestRevision == revision { isTesting = false } }
            do {
                guard let definition = selection?.request() else { return }
                let result = try await BalanceRequestClient.fetch(definition)
                try Task.checkCancellation()
                guard requestRevision == revision else { return }
                guard !result.isEmpty else { throw UsageProviderError(L10n.text("响应中没有可选的数值字段", "No numeric fields in the response")) }
                fields = result; request = definition
                if !result.contains(where: { $0.path == balancePath }) { balancePath = "" }
                if !result.contains(where: { $0.path == totalPath }) { totalPath = "" }
            } catch { if !Task.isCancelled, requestRevision == revision { self.error = error.localizedDescription } }
        }
    }

    private func save() {
        do {
            var value = draft()
            value.credentialRevision = (profile?.credentialRevision ?? 0) + 1
            _ = try value.amounts(in: fields)
            guard let request else { return }
            try BalanceRequestStore.save(request, id: value.id)
            settings.update { preferences in
                if let index = preferences.customBalances.firstIndex(where: { $0.id == value.id }) { preferences.customBalances[index] = value }
                else { preferences.customBalances.append(value) }
            }
            Task { await store.refreshAccounts() }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
