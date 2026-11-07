import SwiftUI
import AgentHUDCore

struct BalanceRequestSelectionView: View {
    @Binding var selection: BalanceRequestSelection
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("保留的请求项", "Request allowlist")).font(.ui(12, .semibold))
                Spacer()
                Text(L10n.text("认证字段", "Renewable")).font(.ui(11)).foregroundStyle(theme.secondary)
            }
            Text(L10n.text("仅保存勾选项。认证失效后，只需更新右侧勾选的字段。", "Only checked items are saved. Mark the fields to update when authentication expires."))
                .font(.ui(11)).foregroundStyle(theme.secondary)
            if selection.parts.isEmpty {
                Text(L10n.text("这个请求没有请求头或 Cookie", "This request has no headers or cookies")).font(.ui(11)).foregroundStyle(theme.secondary)
            }
            ForEach(selection.parts.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Toggle(isOn: $selection.parts[index].keep) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text((selection.parts[index].isCookie ? "Cookie · " : "") + selection.parts[index].name).font(.ui(11, .medium))
                            Text(selection.parts[index].isAuthentication || selection.parts[index].isCookie ? "••••••••" : selection.parts[index].value)
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.secondary).lineLimit(1)
                        }
                    }.toggleStyle(.checkbox)
                    Spacer(minLength: 8)
                    Toggle(L10n.text("认证字段", "Renewable credential"), isOn: Binding(
                        get: { selection.parts[index].keep && selection.parts[index].isAuthentication },
                        set: { selection.parts[index].isAuthentication = $0 }))
                        .labelsHidden().toggleStyle(.checkbox).disabled(!selection.parts[index].keep || selection.parts[index].isCookie)
                }
            }
        }
        .padding(12).background(theme.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
