import SwiftUI
import AgentHUDCore

/// Quota history uses the statistics window's existing cards, compact rows and typography.
struct QuotaCycleHistoryView: View {
    let store: UsageStore
    let theme: Theme
    @Binding var windowID: String
    @State private var expanded: Set<String> = []
    @State private var editingCapacity: QuotaCycleRecord?
    @State private var visibleCount = 20
    private static let pageSize = 20

    private struct WindowGroup: Identifiable {
        let id: String
        let records: [QuotaCycleRecord]
        let total: Int
    }

    private var filteredRecords: [QuotaCycleRecord] {
        store.quotaCycles.filter { windowID.isEmpty || $0.windowID == windowID }
            .sorted { ($0.firstObserved, $0.id) > ($1.firstObserved, $1.id) }
    }
    private func groups(_ records: [QuotaCycleRecord], totals: [String: Int]) -> [WindowGroup] {
        Dictionary(grouping: records, by: \.windowID).map { id, records in
            WindowGroup(id: id, records: records, total: totals[id] ?? records.count)
        }.sorted { ($0.records.first?.firstObserved ?? .distantPast) > ($1.records.first?.firstObserved ?? .distantPast) }
    }

    var body: some View {
        let records = filteredRecords
        let shown = Array(records.prefix(visibleCount))
        let totals = Dictionary(grouping: records, by: \.windowID).mapValues { $0.count }
        let groups = groups(shown, totals: totals)
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.quotaCyclesError {
                Text(L10n.text("周期记录暂不可用：", "Cycle history unavailable: ") + error)
                    .font(.ui(12)).foregroundStyle(theme.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).card(theme)
            }
            if groups.isEmpty {
                Text(L10n.text("暂无周期记录，等待下一次有效额度读数。", "No cycle history yet. Waiting for a confirmed quota reading."))
                    .font(.ui(12)).foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).card(theme)
            } else {
                ForEach(groups) { group in groupCard(group) }
            }
            if records.count > Self.pageSize {
                pagination(shown: shown.count, total: records.count)
            }
            HStack(spacing: 5) {
                Text(L10n.text("本机记录 · 未区分账户", "Local records · Across accounts"))
                Spacer(minLength: 12)
                Text(L10n.text("费率 ", "Prices ") + store.modelPriceSource.source)
                if let updatedAt = store.modelPriceSource.updatedAt {
                    Text("· " + date(updatedAt))
                }
            }
            .font(.ui(11)).foregroundStyle(theme.secondary).padding(.horizontal, 2)
            .help(L10n.text("费率每日更新；下载失败时使用本地缓存。展开周期可查看统计说明。", "Prices update daily, retaining the cache on failure. Expand a cycle for calculation details."))
        }
        .sheet(item: $editingCapacity) { record in QuotaCapacityEditor(record: record, store: store, theme: theme) }
        .onChange(of: windowID) { _, _ in
            visibleCount = Self.pageSize
            expanded = []
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quota-cycle-history")
    }

    private func pagination(shown: Int, total: Int) -> some View {
        HStack {
            Text(L10n.text("已显示 \(shown) / \(total) 个周期", "Showing \(shown) of \(total) cycles"))
                .font(.tabular(11)).foregroundStyle(theme.secondary)
            Spacer()
            if shown < total {
                Button(L10n.text("加载更多", "Load more")) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        visibleCount = min(visibleCount + Self.pageSize, total)
                    }
                }
                .themedLink(theme).font(.ui(11))
                .accessibilityIdentifier("quota-cycle-load-more")
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func groupCard(_ group: WindowGroup) -> some View {
        if let latest = group.records.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    AgentLogo(vendor: latest.vendor, size: 14)
                    Text(latest.vendor).font(.ui(13, .semibold)).foregroundStyle(theme.text)
                    Text(latest.accountLabel).font(.ui(11)).lineLimit(1)
                    Text("·").font(.ui(11))
                    Text(latest.window).font(.ui(11)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let plan = latest.plan { Text(plan).font(.ui(11)) }
                    Text(L10n.text("\(group.total) 个周期", "\(group.total) cycles")).font(.tabular(11))
                }
                .foregroundStyle(theme.secondary)
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
                columns(alignment: .top) {
                    Text(L10n.text("周期", "Cycle"))
                    pairHeading("Token", "Tokens")
                    pairHeading("参考费用", "Reference cost")
                    Text(L10n.text("额度消耗", "Quota used"))
                    Text(L10n.text("状态", "Status"))
                }
                .font(.ui(11)).foregroundStyle(theme.secondary)
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 8, trailing: 14))
                ForEach(group.records) { record in
                    Rectangle().fill(theme.divider).frame(height: 1)
                    row(record)
                }
            }
            .card(theme, padding: EdgeInsets())
        }
    }

    private func columns<A: View, B: View, C: View, D: View, E: View>(alignment: VerticalAlignment = .center, @ViewBuilder content: () -> TupleView<(A, B, C, D, E)>) -> some View {
        let cells = content().value
        return HStack(alignment: alignment, spacing: 10) {
            cells.0.frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            cells.1.frame(width: 138, alignment: .leading)
            cells.2.frame(width: 150, alignment: .leading)
            cells.3.frame(width: 68, alignment: .leading)
            cells.4.frame(width: 60, alignment: .leading)
        }
    }

    private func row(_ record: QuotaCycleRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if !expanded.insert(record.id).inserted { expanded.remove(record.id) }
                }
            } label: {
                columns {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(expanded.contains(record.id) ? 90 : 0)).frame(width: 10)
                                .foregroundStyle(theme.secondary)
                            Text(cycleLabel(record))
                                .font(.ui(12, .medium)).foregroundStyle(theme.text).lineLimit(1)
                                .help(cycleHelp(record))
                        }
                        if record.endedAt == nil {
                            Text((record.resetAt > store.now ? L10n.text("下次重置 ", "Next reset ") : L10n.text("预计重置 ", "Expected reset ")) + date(record.resetAt))
                                .font(.ui(11)).foregroundStyle(theme.secondary).padding(.leading, 15).lineLimit(1)
                                .help(L10n.text("服务返回的预计重置时间。", "Expected reset time reported by the service."))
                        }
                    }
                    tokenCell(record)
                    costCell(record)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(percent(record.consumedPercent)).font(.tabular(12, .medium)).foregroundStyle(theme.text)
                        ProgressTrack(fraction: record.consumedPercent / 100, fill: theme.status(.ok), track: theme.track)
                            .frame(height: 3).accessibilityHidden(true)
                    }
                    Text(record.endedAt != nil ? L10n.text("已封存", "Archived") : L10n.text("进行中", "In progress"))
                        .font(.ui(11, .medium))
                        .foregroundStyle(record.endedAt == nil && !waiting(record) ? theme.statusText(.ok) : theme.secondary)
                        .help(record.endedAt == nil && waiting(record) ? L10n.text("等待最新额度读数。", "Waiting for a fresh quota reading.") : "")
                }
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityText(record))
            .accessibilityValue(expanded.contains(record.id) ? L10n.text("已展开", "Expanded") : L10n.text("已折叠", "Collapsed"))
            if expanded.contains(record.id) { details(record) }
        }
    }

    private func accessibilityText(_ record: QuotaCycleRecord) -> String {
        let tokens = L10n.text("Token 已用 ", "Tokens used ") + record.usage.tokens.formatted() +
            L10n.text("，预计整轮 ", ", estimated total ") + (record.estimatedTokenCapacity.map { $0.formatted() } ?? "—")
        let cost = L10n.text("费用已用 ", "Cost used ") + preciseMoney(record.usage.baseAmounts ?? [:]) +
            L10n.text("，预计整轮 ", ", estimated total ") + (record.estimatedReferenceCapacity.map { preciseMoney($0) } ?? "—")
        return [record.vendor + " " + record.window, date(record.start), tokens, cost, percent(record.consumedPercent),
                record.endedAt != nil ? L10n.text("已封存", "Archived") : L10n.text("进行中", "In progress")].joined(separator: ", ")
    }

    private func tokenCell(_ record: QuotaCycleRecord) -> some View {
        let projected = record.estimatedTokenCapacity
        let predictedText = projected.map { $0.formatted() + " Token" }
            ?? L10n.text("样本不足或读数有间断", "Insufficient or interrupted readings")
        let help = L10n.text("已用：", "Used: ") + record.usage.tokens.formatted() +
            L10n.text(" Token\n预计整轮：", " tokens\nEstimated full cycle: ") + predictedText
        return pair(TokenFormat.short(record.usage.tokens), projected.map { TokenFormat.short($0) }).help(help)
    }
    private func costCell(_ record: QuotaCycleRecord) -> some View {
        let projected = record.estimatedReferenceCapacity
        let predictedText = projected.map { preciseMoney($0) } ?? unavailableReason(record)
        let help = L10n.text("已用：", "Used: ") + preciseMoney(record.usage.baseAmounts ?? [:]) +
            L10n.text("\n预计整轮：", "\nEstimated full cycle: ") + predictedText +
            L10n.text("\n按基础价折算，不含 API 长上下文加价。", "\nAt base prices, excluding API context surcharges.")
        return pair(money(record.usage.baseAmounts ?? [:]), projected.map { money($0) }).help(help)
    }

    private func pairHeading(_ zh: String, _ en: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(zh, en))
            Text(L10n.text("已用 / 预计整轮", "Used / Estimated total")).font(.ui(10))
        }
    }
    private func pair(_ used: String, _ estimated: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(used).font(.tabular(12, .semibold)).foregroundStyle(theme.text)
            Text("/").font(.ui(11)).foregroundStyle(theme.secondary)
            Text(estimated ?? "—").font(.tabular(12)).foregroundStyle(theme.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private func details(_ record: QuotaCycleRecord) -> some View {
        QuotaCycleDetailsView(record: record, theme: theme,
            manageChanges: store.ledger == nil ? nil : { editingCapacity = record })
    }

    private func waiting(_ record: QuotaCycleRecord) -> Bool {
        record.resetAt <= store.now || store.now.timeIntervalSince(record.lastObserved) >= AlertPolicy.maximumReadingAge ||
            store.report?.observation(accountID: record.accountID)?.isCurrent == false
    }

    private func unavailableReason(_ record: QuotaCycleRecord) -> String {
        if record.hasUnassignedUsage && record.localUsageOnly != true { return L10n.text("归属待确认", "Uncertain attribution") }
        if record.hasObservationGap { return L10n.text("观测有缺口", "Observation gap") }
        if record.usageUnavailable { return L10n.text("记录不完整", "Incomplete calls") }
        if record.observedUsage.unpricedTokens > 0 { return L10n.text("部分缺价", "Missing prices") }
        if record.observedUsage.amounts.count > 1 { return L10n.text("多币种", "Separate currencies") }
        if record.observedUsage.baseAmounts == nil { return L10n.text("参考价待回填", "Reference needs backfill") }
        return L10n.text("等待样本", "More samples needed")
    }
    private func cycleLabel(_ record: QuotaCycleRecord) -> String {
        let start = (record.startObservedAfter == nil ? "" : "≈") + date(record.start)
        if let end = record.endedAt {
            return start + " → " + (record.resetObservedAfter == nil ? "" : "≈") + date(end)
        }
        return start + " → " + (waiting(record) ? date(record.lastObserved) : L10n.text("现在", "Now"))
    }
    private func cycleHelp(_ record: QuotaCycleRecord) -> String {
        if let lower = record.resetObservedAfter, let upper = record.endedAt {
            return L10n.text("重置发生在 ", "The reset occurred between ") + date(lower) + " – " + date(upper) +
                L10n.text(" 之间。统计时段可在详情中查看。", ". Expand for the recorded usage interval.")
        }
        return cycleLabel(record)
    }
    private func date(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = L10n.dateLocale
        format.dateFormat = "MM/dd HH:mm"
        return format.string(from: date)
    }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + "%" }
    private func money(_ amounts: [String: Decimal]) -> String {
        let values = amounts.keys.sorted().map { MoneyFormat.short(amounts[$0] ?? 0, currency: $0) }
        return values.isEmpty ? "—" : values.joined(separator: " · ")
    }
    private func preciseMoney(_ amounts: [String: Decimal]) -> String {
        let values = amounts.keys.sorted().map { MoneyFormat.amount(amounts[$0] ?? 0, currency: $0) }
        return values.isEmpty ? "—" : values.joined(separator: " · ")
    }
}
