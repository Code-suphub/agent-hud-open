import SwiftUI
import AgentHUDCore

/// Match the statistics window's compact figures, labelled rows and optional help.
struct QuotaCycleDetailsView: View {
    let record: QuotaCycleRecord
    let theme: Theme
    var manageChanges: (() -> Void)?
    @State private var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                figure(L10n.text("参考费用", "Reference cost"), money(record.observedUsage.baseAmounts ?? [:]),
                       note: L10n.text("按基础价", "At base prices"),
                       help: L10n.text("统计时段内的调用按模型基础价折算，不含 API 长上下文加价。", "Recorded calls at base model rates, excluding API context surcharges."))
                separator.padding(.horizontal, 14)
                figure(L10n.text("API 价折算", "API equivalent"), money(record.observedUsage.amounts),
                       note: L10n.text("含长上下文加价", "Includes context surcharges"),
                       help: L10n.text("同一批调用按标准 API 费率折算，用于费用对比，不代表订阅扣费。", "The same calls at standard API rates, for comparison rather than subscription charges."))
                separator.padding(.horizontal, 14)
                figure(L10n.text("本段消耗", "Observed usage"), percent(record.observedPercent),
                       note: (record.capacityChanges ?? []).isEmpty ? L10n.text("统计时段内", "Within this interval") : L10n.text("按调整后上限", "At adjusted capacity"),
                       help: L10n.text("根据额度读数计算；填写额度变更后，两端读数按同一上限比较。", "Based on quota readings, normalized to the same allowance after a capacity change."))
            }
            rule
            VStack(spacing: 7) {
                entry(L10n.text("统计时段", "Recorded"), interval(record.firstObserved, record.lastObserved), help: startHelp)
                entry(L10n.text("剩余额度", "Remaining"), percent(record.initialRemaining) + " → " + percent(record.remaining))
                if let lower = record.resetObservedAfter, let upper = record.endedAt {
                    entry(L10n.text("重置时间", "Reset"), interval(lower, upper) + L10n.text("（约）", " (approx.)"),
                          help: L10n.text("重置发生在这两次读数之间，确切时刻未记录。", "The reset occurred between these readings; the exact time was not recorded."))
                } else {
                    entry(L10n.text("重置时间", "Reset"), date(record.resetAt))
                }
                entry(L10n.text("记录来源", "Source"), record.resetObservedAfter != nil ? L10n.text("历史回填", "Recovered history") : L10n.text("本机采集", "Local readings"))
                if let plan = record.plan { entry(L10n.text("套餐", "Plan"), plan) }
            }
            if !(record.capacityChanges ?? []).isEmpty {
                rule
                HStack {
                    Text(L10n.text("额度变更", "Capacity changes")).font(.ui(12, .semibold))
                    Spacer()
                    manageButton
                }
                ForEach(record.capacityChanges ?? [], id: \.observedAt) { change in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(interval(change.observedAfter, change.observedAt)).font(.tabular(11)).foregroundStyle(theme.secondary)
                        Text(change.multiplier == 2 ? L10n.text("额度翻倍", "Capacity doubled") :
                            L10n.text("上限 ×", "Capacity ×") + change.multiplier.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.ui(12, .medium))
                        Spacer(minLength: 8)
                        if let note = change.note {
                            Text(note).font(.ui(11)).foregroundStyle(theme.secondary).lineLimit(1).help(note)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let notice {
                Label(notice, systemImage: "info.circle").font(.ui(11)).foregroundStyle(theme.secondary)
            }
            HStack {
                if (record.capacityChanges ?? []).isEmpty { manageButton }
                Spacer()
                Button { showsHelp.toggle() } label: {
                    Label(L10n.text("统计说明", "About these figures"), systemImage: "info.circle")
                }
                .themedLink(theme).font(.ui(11))
                .popover(isPresented: $showsHelp, arrowEdge: .bottom) { explanation }
            }
        }
        .foregroundStyle(theme.text)
        .padding(EdgeInsets(top: 2, leading: 29, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("quota-cycle-details")
    }

    @ViewBuilder private var manageButton: some View {
        if let manageChanges {
            Button(L10n.text("管理变更", "Manage changes"), action: manageChanges)
                .themedLink(theme).font(.ui(11))
        }
    }
    private var rule: some View { Rectangle().fill(theme.divider).frame(height: 1) }
    private var separator: some View { Rectangle().fill(theme.divider).frame(width: 1, height: 34).padding(.top, 5) }
    private func figure(_ title: String, _ value: String, note: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.ui(10)).foregroundStyle(theme.secondary)
            Text(value).font(.tabular(15, .semibold)).lineLimit(1).minimumScaleFactor(0.8).textSelection(.enabled)
            Text(note).font(.ui(10)).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).help(help)
        .accessibilityElement(children: .combine)
    }
    private func entry(_ label: String, _ value: String, help: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).font(.ui(11)).foregroundStyle(theme.secondary).frame(width: 66, alignment: .leading)
            Text(value).font(.tabular(12)).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .help(help).accessibilityElement(children: .combine)
    }
    private var startHelp: String {
        if let lower = record.startObservedAfter {
            return L10n.text("周期开始于 ", "The cycle began between ") + interval(lower, record.firstObserved)
        }
        return L10n.text("仅统计两次额度读数之间的本机调用。", "Only calls recorded on this Mac between the quota readings are included.")
    }
    private var notice: String? {
        if record.hasObservationGap { return L10n.text("额度读数有间断，暂不估算整轮用量。", "Quota readings have gaps; the full-cycle estimate is unavailable.") }
        if record.usageUnavailable { return L10n.text("调用记录尚未完整。", "Call records are incomplete.") }
        if record.observedUsage.unpricedTokens > 0 { return L10n.text("部分模型暂无价格，费用未计全。", "Some models have no price; the cost is incomplete.") }
        if record.observedUsage.baseAmounts == nil { return L10n.text("参考费用尚未回填。", "Reference costs have not been recovered.") }
        if record.initialRemaining < 99 { return L10n.text("从周期中途开始记录。", "Recording began partway through the cycle.") }
        return nil
    }
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("统计说明", "About these figures")).font(.ui(12, .semibold))
            helpItem(L10n.text("已用 / 预计整轮", "Used / Estimated total"), L10n.text("左侧是已记录的用量，右侧是整轮预估，并非剩余可用量。预估使用同一观测时段的 Token 或费用除以额度消耗比例；模型构成变化会影响结果。", "The left value is recorded usage; the right is a full-cycle projection, not the remaining allowance. Projections divide same-interval tokens or cost by quota consumption; changes in model mix affect the result."))
            helpItem(L10n.text("参考费用", "Reference cost"), L10n.text("按模型基础价折算，不含长上下文加价。整轮参考值以本段费用和额度消耗估算，不代表官方美元额度。", "Uses base model rates without context surcharges. The full-cycle reference uses this cost and observed quota consumption; it is not an official dollar allowance."))
            helpItem(L10n.text("API 价折算", "API equivalent"), L10n.text("按标准 API 费率逐次计算，包含长上下文加价。仅供费用对比，不作为订阅额度倍率。", "Uses each recorded call's standard API rates, including context surcharges. For cost comparison, not subscription multipliers."))
            helpItem(L10n.text("记录范围", "Coverage"), L10n.text("仅统计本机日志，暂不区分账户。重置前后的未记录时段不计入费用；历史重置时间显示观测范围。", "Includes this Mac's logs across accounts. Unrecorded reset intervals are excluded; historical reset times are shown as observed ranges."))
            helpItem(L10n.text("额度变更", "Capacity changes"), L10n.text("变更由手动填写。原始读数保留，消耗比例换算到调整后的上限。", "Changes are entered manually. Original readings are retained and consumption is normalized to the adjusted capacity."))
        }
        .padding(14).frame(width: 340).foregroundStyle(theme.text)
    }
    private func helpItem(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.ui(11, .semibold))
            Text(message).font(.ui(11)).foregroundStyle(theme.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func interval(_ first: Date, _ last: Date) -> String {
        date(first) + " – " + date(last, timeOnly: Calendar.current.isDate(first, inSameDayAs: last))
    }
    private func date(_ value: Date, timeOnly: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.locale = L10n.dateLocale
        formatter.dateFormat = timeOnly ? "HH:mm" : "MM/dd HH:mm"
        return formatter.string(from: value)
    }
    private func money(_ amounts: [String: Decimal]) -> String {
        let values = amounts.keys.sorted().map { MoneyFormat.amount(amounts[$0] ?? 0, currency: $0) }
        return values.isEmpty ? "—" : values.joined(separator: " · ")
    }
    private func percent(_ value: Double) -> String { TokenFormat.percent1(value) }
}
