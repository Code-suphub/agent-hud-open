import SwiftUI
import AgentHUDCore

struct CustomBalancesPane: View {
    let settings: SettingsStore
    let store: UsageStore
    let theme: Theme
    @State private var editing: CustomBalanceProfile?
    @State private var adding = false
    @State private var isManuallyRefreshing = false
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
                        if let website = profile.websiteURL {
                            Link(destination: website) { Image(systemName: "safari") }
                                .accessibilityLabel(L10n.text("打开官网", "Open website"))
                                .help(website.absoluteString)
                        }
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
                    Button(L10n.text("立即刷新", "Refresh now"), action: refreshManually)
                        .disabled(isManuallyRefreshing || !settings.settings.customBalances.contains(where: \.enabled))
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

    private func refreshManually() {
        guard !isManuallyRefreshing else { return }
        isManuallyRefreshing = true
        Task {
            defer { isManuallyRefreshing = false }
            await store.refreshAccounts()
        }
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
    @State private var website: String
    @State private var divisor: String
    @State private var valueKind: CustomBalanceProfile.ValueKind
    @State private var balancePath: String
    @State private var totalPath: String
    @State private var curl = ""
    @State private var request: BalanceRequest?
    @State private var selection: BalanceRequestSelection?
    @State private var savedParts: [BalanceRequestPart]?
    @State private var fields: [BalanceField] = []
    @State private var isTesting = false
    @State private var probeAttempts: Int?
    @State private var error: String?
    @State private var testTask: Task<Void, Never>?
    @State private var requestRevision = 0

    init(settings: SettingsStore, store: UsageStore, theme: Theme, profile: CustomBalanceProfile? = nil) {
        self.settings = settings; self.store = store; self.theme = theme; self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _currency = State(initialValue: profile?.currency ?? "CNY")
        _website = State(initialValue: profile?.website ?? "")
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
                    .disabled(!canSave)
            }
        }
        .padding(24).frame(width: 650).foregroundStyle(theme.text).background(theme.windowBackground)
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
                Text(L10n.text("官网或登录页（可选）", "Website or sign-in page (optional)")).font(.ui(12, .medium))
                TextField("https://example.com/account", text: $website)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .accessibilityLabel(L10n.text("官网或登录页", "Website or sign-in page"))
                if !validWebsite {
                    Text(L10n.text("请输入有效的 HTTPS 网址。", "Enter a valid HTTPS URL."))
                        .font(.ui(11)).foregroundStyle(theme.statusText(.warning))
                }
            }
            if let profile {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("已保存的字段映射", "Saved field mapping")).font(.ui(12, .semibold))
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        GridRow {
                            Text(profile.valueKind == .remaining ? L10n.text("余额字段", "Balance field") : L10n.text("已用字段", "Used field"))
                            Text(profile.balancePath.isEmpty ? "/" : profile.balancePath).monospaced().textSelection(.enabled)
                        }
                        GridRow {
                            Text(L10n.text("总量字段", "Total field"))
                            Text(profile.totalPath.map { $0.isEmpty ? "/" : $0 } ?? L10n.text("不设置", "Not set"))
                                .monospaced().textSelection(.enabled)
                        }
                    }.font(.ui(12))
                    Text(L10n.text("点「请求并读取字段」后可重新选择映射。", "Use Request and inspect fields to change the mapping."))
                        .font(.ui(11)).foregroundStyle(theme.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("cURL").font(.ui(12, .medium))
                TextEditor(text: $curl).font(.system(size: 11, design: .monospaced))
                    .frame(height: 110).padding(5).background(theme.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .autocorrectionDisabled()
                    .onChange(of: curl) { _, _ in
                        invalidate(); selection = nil; savedParts = nil
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
                BalanceRequestSelectionView(selection: Binding(get: { selection! }, set: { selection = $0; invalidate() }), theme: theme)
            }
            HStack {
                Button { test() } label: { Label(L10n.text("请求并读取字段", "Request and inspect fields"), systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(isTesting || selection == nil)
                if savedParts == nil, selection?.canProbe == true {
                    Button(L10n.text("智能测试", "Smart test")) { test(smart: true) }
                        .disabled(isTesting)
                        .help(L10n.text("最多尝试三组。失败时可补上原 cURL 中的 Cookie、CSRF、Origin 或 Referer。",
                                        "Try up to three combinations, adding cookies, CSRF, Origin or Referer from the original cURL."))
                }
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                if !fields.isEmpty { Text(L10n.text("读取到 \(fields.count) 个数值字段", "Found \(fields.count) numeric fields")).font(.ui(11)).foregroundStyle(theme.secondary) }
            }
            if !fields.isEmpty {
                if let probeAttempts {
                    Text(L10n.text("第 \(probeAttempts) 组请求成功，已应用推荐勾选。", "Combination \(probeAttempts) worked and its selection is now applied."))
                        .font(.ui(11)).foregroundStyle(theme.secondary)
                }
                Text(L10n.text("设置字段映射", "Set field mapping")).font(.ui(12, .semibold))
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
                        Text(L10n.text("余额 ", "Balance ") + CustomBalanceProfile.format(preview.balance, unit: currencyCode))
                        if let total = preview.total { Text(L10n.text("总量 ", "Total ") + CustomBalanceProfile.format(total, unit: currencyCode)) }
                    }.font(.tabular(14, .semibold)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if let error { Text(error).font(.ui(12)).foregroundStyle(theme.statusText(.warning)).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func invalidate() {
        testTask?.cancel(); requestRevision += 1; request = nil; fields = []; isTesting = false; error = nil; probeAttempts = nil
    }

    private func prepare() {
        invalidate()
        do {
            let saved = curl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let definition = try saved ? BalanceRequestStore.load(id: profile!.id) : BalanceRequest.parse(curl: curl, forSelection: true)
            let parsed = BalanceRequestSelection(definition, preserveSavedSelection: saved)
            selection = parsed
            savedParts = saved ? parsed.parts : nil
        } catch { selection = nil; savedParts = nil; self.error = error.localizedDescription }
    }

    private func fieldPicker(_ selection: Binding<String>, optional: Bool) -> some View {
        Picker("", selection: selection) {
            Text(optional ? L10n.text("不设置", "Not set") : L10n.text("请选择", "Select a field")).tag("")
            if !selection.wrappedValue.isEmpty, !fields.contains(where: { $0.path == selection.wrappedValue }) {
                Text(selection.wrappedValue + L10n.text("（响应未找到）", " (not in response)")).tag(selection.wrappedValue)
            }
            ForEach(fields) { field in
                Text((field.path.isEmpty ? "/" : field.path) + " = " + field.value.formatted(.number.precision(.fractionLength(0...2)))).tag(field.path)
            }
        }.labelsHidden().frame(maxWidth: .infinity)
    }

    private func draft() -> CustomBalanceProfile {
        var value = CustomBalanceProfile(id: profile?.id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currencyCode, balancePath: balancePath,
            totalPath: totalPath.isEmpty ? nil : totalPath, divisor: Decimal(string: divisor, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            enabled: profile?.enabled ?? true, valueKind: valueKind)
        value.avatar = profile?.avatar
        value.credentialRevision = profile?.credentialRevision
        let address = website.trimmingCharacters(in: .whitespacesAndNewlines)
        value.website = address.isEmpty ? nil : address
        return value
    }
    private var preview: (balance: Decimal, total: Decimal?)? { try? draft().amounts(in: fields) }

    private func test(smart: Bool = false) {
        guard let selection, !isTesting else { return }
        error = nil; fields = []; request = nil; probeAttempts = nil; isTesting = true
        let revision = requestRevision
        let requiredPaths = profile.map { Set([$0.balancePath] + ($0.totalPath.map { [$0] } ?? [])) } ?? []
        testTask = Task {
            defer { if requestRevision == revision { isTesting = false } }
            do {
                let testedSelection: BalanceRequestSelection
                let result: [BalanceField]
                let attempts: Int?
                if smart {
                    let match = try await selection.probe(requiredPaths: requiredPaths)
                    (testedSelection, result, attempts) = (match.selection, match.fields, match.attempts)
                } else {
                    (testedSelection, result, attempts) = (selection, try await BalanceRequestClient.fetch(selection.request()), nil)
                }
                try Task.checkCancellation()
                guard requestRevision == revision else { return }
                guard !result.isEmpty else { throw UsageProviderError(L10n.text("响应中没有可选的数值字段", "No numeric fields in the response")) }
                self.selection = testedSelection
                fields = result; request = testedSelection.request(); probeAttempts = attempts
            } catch { if !Task.isCancelled, requestRevision == revision { self.error = error.localizedDescription } }
        }
    }

    private var currencyCode: String { currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    private var validWebsite: Bool {
        let value = draft()
        return value.website == nil || value.websiteURL != nil
    }

    /// An existing source's display details can be edited even when its credentials have expired.
    private var canSaveDetails: Bool {
        guard let profile, curl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selection?.parts == savedParts else { return false }
        let value = draft()
        return value.balancePath == profile.balancePath && value.totalPath == profile.totalPath &&
            value.divisor == profile.divisor && value.valueKind == profile.valueKind
    }

    private var canSave: Bool {
        !isTesting && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !currencyCode.isEmpty &&
            validWebsite && (canSaveDetails || (request != nil && preview != nil))
    }

    private func save() {
        guard canSave else { return }
        do {
            if let profile, !settings.settings.customBalances.contains(profile) {
                throw UsageProviderError(L10n.text("配置已变化，请关闭后重新打开", "Configuration changed; close and reopen this window"))
            }
            var value = draft()
            if !canSaveDetails {
                _ = try value.amounts(in: fields)
                guard let request else { return }
                try BalanceRequestStore.save(request, id: value.id)
                value.credentialRevision = (profile?.credentialRevision ?? 0) + 1
            }
            settings.update { preferences in
                if let index = preferences.customBalances.firstIndex(where: { $0.id == value.id }) { preferences.customBalances[index] = value }
                else { preferences.customBalances.append(value) }
            }
            Task { await store.refreshAccounts() }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
