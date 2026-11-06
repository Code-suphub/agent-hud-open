import SwiftUI
import AgentHUDCore

/// Persisted quota occurrences. Reading the page never polls a provider or rebuilds the ledger.
struct QuotaCycleHistoryView: View {
    let store: UsageStore
    let theme: Theme
    @State private var windowID: String = ""
    @State private var expanded: Set<String> = []

    private var windows: [QuotaCycleRecord] {
        var seen = Set<String>()
        return store.quotaCycles.filter { seen.insert($0.windowID).inserted }
    }
    private var records: [QuotaCycleRecord] {
        store.quotaCycles.filter { windowID.isEmpty || $0.windowID == windowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("每个周期，用了多少", "Usage in each quota cycle")).font(.ui(20, .semibold))
                    Text(L10n.text("实际额度恢复后开启新周期；重置卡到账不会拆分周期。",
                                   "A confirmed quota reset starts a cycle; receiving reset credits does not."))
                        .foregroundStyle(theme.secondary).font(.ui(12))
                }
                Spacer()
                Picker(L10n.text("账户与窗口", "Account and window"), selection: $windowID) {
                    Text(L10n.text("全部账户与窗口", "All accounts and windows")).tag("")
                    ForEach(windows) { record in
                        Text("\(record.vendor) · \(record.accountLabel) · \(record.window)").tag(record.windowID)
                    }
                }
                .labelsHidden().frame(maxWidth: 340)
                .accessibilityIdentifier("quota-cycle-filter")
            }
            if let error = store.quotaCyclesError {
                Text(L10n.text("周期记录暂不可用：", "Cycle history unavailable: ") + error)
                    .foregroundStyle(theme.secondary).textSelection(.enabled)
            }
            if records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 30)).foregroundStyle(theme.secondary)
                    Text(L10n.text("等待第一次有效额度读数", "Waiting for a confirmed quota reading")).font(.ui(15, .semibold))
                    Text(L10n.text("从首次观测开始保存。旧百分比记录缺少重置边界，不会推造历史周期。",
                                   "History starts with the first observation. Old percentage samples cannot reconstruct reset boundaries."))
                        .font(.ui(12)).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 60)
            } else {
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        columns {
                            Text(L10n.text("周期 / 重置时间", "Cycle / reset"))
                            Text(L10n.text("调用用量 · API 等值", "Calls · API equivalent"))
                            Text(L10n.text("额度消耗", "Quota consumed"))
                            Text(L10n.text("预计满额 · API 等值", "Est. full API equivalent"))
                            Text(L10n.text("状态", "Status"))
                        }
                        .font(.ui(11, .semibold)).foregroundStyle(theme.secondary).padding(.vertical, 12)
                        ForEach(records) { record in
                            Rectangle().fill(theme.divider).frame(height: 1)
                            row(record)
                        }
                    }
                    .frame(minWidth: 740)
                }
            }
            Text(L10n.text("金额为本机已记录调用按公开 API 价格折算的等值，并非订阅扣费或官方额度。估算使用同一观测区间的金额 ÷ 消耗比例；至少消耗 5 个百分点。缺价、账户归属不明或观测中断时不估算。",
                           "Amounts price locally recorded calls at public API rates; they are not subscription charges or official limits. Estimates divide same-interval cost by quota consumption, with at least five percentage points. Missing prices, uncertain attribution or observation gaps suppress estimates."))
                .font(.ui(11)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("quota-cycle-history")
    }

    private func columns<A: View, B: View, C: View, D: View, E: View>(@ViewBuilder content: () -> TupleView<(A, B, C, D, E)>) -> some View {
        let cells = content().value
        return HStack(alignment: .center, spacing: 12) {
            cells.0.frame(width: 235, alignment: .leading)
            cells.1.frame(width: 130, alignment: .leading)
            cells.2.frame(width: 100, alignment: .leading)
            cells.3.frame(width: 145, alignment: .leading)
            cells.4.frame(width: 82, alignment: .leading)
        }
    }

    private func row(_ record: QuotaCycleRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !expanded.insert(record.id).inserted { expanded.remove(record.id) }
            } label: {
                columns {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: expanded.contains(record.id) ? "chevron.down" : "chevron.right").font(.ui(9))
                            Text(date(record.start) + " → " + (record.endedAt.map(date) ?? (waiting(record) ? date(record.lastObserved) : L10n.text("现在", "Now"))))
                                .font(.ui(12, .semibold)).lineLimit(1)
                        }
                        Text("\(record.vendor) · \(record.accountLabel) · \(record.plan ?? "") · \(record.window)")
                            .font(.ui(11)).foregroundStyle(theme.secondary).lineLimit(1)
                        Text(L10n.text("重置：", "Reset: ") + date(record.resetAt))
                            .font(.ui(11)).foregroundStyle(theme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(money(record.usage.amounts)).font(.ui(16, .semibold)).monospacedDigit()
                        Text("\(record.usage.tokens.formatted()) tokens").font(.ui(11)).foregroundStyle(theme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(percent(record.consumedPercent)).font(.ui(14, .semibold)).monospacedDigit()
                        ProgressView(value: record.consumedPercent, total: 100).tint(.mint).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.estimatedCapacity.map { "≈" + money($0) } ?? "—").font(.ui(16, .semibold)).monospacedDigit()
                        Text(record.estimatedCapacity == nil ? unavailableReason(record) : L10n.text("观测区间估算", "Observed interval"))
                            .font(.ui(11)).foregroundStyle(theme.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.endedAt != nil ? L10n.text("已封存", "Archived") : waiting(record) ? L10n.text("待更新", "Awaiting update") : L10n.text("进行中", "In progress"))
                            .font(.ui(12, .semibold)).foregroundStyle(record.endedAt == nil && !waiting(record) ? Color.mint : theme.secondary)
                        Text(record.partial ? L10n.text("记录不全", "Partial record") : L10n.text("持续观测", "Observed"))
                            .font(.ui(11)).foregroundStyle(theme.secondary)
                    }
                }
                .padding(.vertical, 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(record.vendor) \(record.window), \(date(record.start)), \(money(record.usage.amounts)), \(percent(record.consumedPercent))")
            .accessibilityValue(expanded.contains(record.id) ? L10n.text("已展开", "Expanded") : L10n.text("已折叠", "Collapsed"))
            if expanded.contains(record.id) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("剩余额度：", "Remaining: ") + percent(record.initialRemaining) + " → " + percent(record.remaining)
                         + L10n.text("；观测消耗：", "; observed consumption: ") + percent(record.observedPercent))
                    Text(L10n.text("观测范围：", "Observed: ") + date(record.firstObserved) + " → " + date(record.lastObserved))
                    Text(L10n.text("起点：", "Start: ") + boundary(record.beganBy)
                         + L10n.text("；结束：", "; end: ") + (record.endedBy.map(boundary) ?? L10n.text("尚未确认重置", "No reset confirmed")))
                    if record.endedBy == .restored || record.beganBy == .restored {
                        Text(L10n.text("额度提前恢复，时间为首次确认时间；服务未提供精确的手动重置时刻。",
                                       "Quota was restored early. Time is when it was first confirmed, not an exact service-provided reset time."))
                    }
                    if record.hasUnobservedTail {
                        Text(L10n.text("最后读数到重置之间未被完整观测；历史消耗保留最后读数，估算仅对应已观测区间。",
                                       "The interval from the last reading to reset was not fully observed. Consumption keeps the last reading; estimates cover only the observed interval."))
                    }
                    if record.hasUnassignedUsage {
                        Text(L10n.text("本地调用未全部标明账户；可能为该账户的调用单独列示，无法确认归属时不估算容量。",
                                       "Local calls do not all name an account. Possibly related calls are shown, but uncertain attribution prevents a capacity estimate."))
                    }
                    Text(L10n.text("估算区间调用等值：", "Observed-interval API equivalent: ") + money(record.observedUsage.amounts))
                }
                .font(.ui(12)).foregroundStyle(theme.secondary).textSelection(.enabled)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.divider.opacity(0.3), in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 14)
            }
        }
    }

    private func waiting(_ record: QuotaCycleRecord) -> Bool {
        record.resetAt <= store.now || store.now.timeIntervalSince(record.lastObserved) >= AlertPolicy.maximumReadingAge ||
            store.report?.observation(accountID: record.accountID)?.isCurrent == false
    }

    private func unavailableReason(_ record: QuotaCycleRecord) -> String {
        if record.hasUnassignedUsage { return L10n.text("账户归属待确认", "Uncertain attribution") }
        if record.hasObservationGap { return L10n.text("观测存在缺口", "Observation gap") }
        if record.usageUnavailable { return L10n.text("调用记录不完整", "Incomplete calls") }
        if record.observedUsage.unpricedTokens > 0 { return L10n.text("部分模型缺价", "Missing model prices") }
        if record.observedUsage.amounts.count > 1 { return L10n.text("多币种分别记录", "Separate currencies") }
        return L10n.text("等待足够样本", "More samples needed")
    }
    private func boundary(_ value: QuotaCycleRecord.Boundary) -> String {
        switch value {
        case .firstObservation: L10n.text("首次观测", "First observation")
        case .naturalReset: L10n.text("自然重置", "Scheduled reset")
        case .restored: L10n.text("提前恢复 / 手动重置", "Early / manual reset")
        case .planChanged: L10n.text("套餐变更", "Plan changed")
        }
    }
    private func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()
            .locale(Locale(identifier: L10n.text("zh_CN", "en_US"))))
    }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + "%" }
    private func money(_ amounts: [String: Decimal]) -> String {
        amounts.keys.sorted().map { currency in
            amounts[currency, default: 0].formatted(.currency(code: currency).precision(.fractionLength(2)))
        }.joined(separator: " · ").nonEmpty ?? "—"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
