import SwiftUI
import AgentHUDCore

/// Reported remaining and total stay distinct from local API-equivalent cost estimates.
struct CustomBalanceFigures: View {
    let balance: AccountBalance?
    let currency: String
    let theme: Theme
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                figure(L10n.text("剩余额度", "Remaining"), amount: balance?.total)
                Spacer(minLength: 20)
                figure(L10n.text("总额度", "Total"), amount: balance?.limit)
            }
            if let balance, let limit = balance.limit, limit > 0 {
                let used = NSDecimalNumber(decimal: (limit - balance.total) / limit * 100).doubleValue
                if used.isFinite {
                    ProgressView(value: min(100, max(0, used)), total: 100)
                        .tint(isCurrent ? theme.text.opacity(0.65) : theme.secondary)
                        .help(L10n.text("已用 ", "Used ") + used.formatted(.number.precision(.fractionLength(0...1))) + "%")
                }
            }
        }
        .help((isCurrent ? balance?.runsOutAt : nil).map {
            L10n.text("预计耗尽：", "Runs out: ") + BalanceMetrics.runOutLabel($0, now: Date())
        } ?? L10n.text("来自自定义余额接口", "From the configured balance endpoint"))
    }

    private func figure(_ label: String, amount: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.ui(11)).foregroundStyle(theme.secondary)
            Text(amount.map { CustomBalanceProfile.format($0, unit: currency) } ?? "—")
                .font(.tabular(15, .semibold)).foregroundStyle(isCurrent ? theme.text : theme.secondary)
        }
    }
}
