import SwiftUI
import AgentHUDCore

/// An API balance's estimated cost over a period in the hover panel, a bar for each of the period's columns, as the
/// token chart lays them out, in one colour: the balance's level, as its figures are drawn, so the bars tell how the
/// balance stands and their heights what each column cost. Hovering a column raises its period and its amount on the
/// HUD's own surface, as the token chart's columns do; a column with a request that had no price in the currency is
/// drawn empty and says it is unpriced.
struct CostBarsChart: View {
    let columns: [CostColumn]
    let interval: DateInterval
    let currency: String
    let color: Color
    let theme: Theme
    var isLoading = false
    @State private var hoveredID: Date?
    /// The look of the HUD the chart is drawn in, whose surface the column details are raised off.
    @Environment(\.hudLook) private var look

    private var inspectedColumn: CostColumn? {
        hoveredID.flatMap { id in columns.first { $0.id == id } }
    }

    /// Complete columns at both ends; their amounts still cover only the period.
    private var plotInterval: DateInterval {
        guard let first = columns.first, let last = columns.last else { return interval }
        return DateInterval(start: first.interval.start, end: last.interval.end)
    }

    var body: some View {
        let values = columns.map { $0.amount.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 }
        let peak = values.max() ?? 0
        let inspectedColumn = inspectedColumn
        GeometryReader { proxy in
            let usable = proxy.size.height - 2
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(theme.divider).frame(height: 1)
                if let column = inspectedColumn {
                    let bounds = xBounds(column, width: proxy.size.width)
                    Rectangle().fill(theme.text.opacity(0.08))
                        .frame(width: bounds.upperBound - bounds.lowerBound, height: usable)
                        .offset(x: bounds.lowerBound)
                    Rectangle().fill(theme.secondary.opacity(0.5))
                        .frame(width: 1, height: usable)
                        .offset(x: (bounds.lowerBound + bounds.upperBound) / 2)
                }
                // Dense periods are drawn in one surface instead of a view for every bar.
                Canvas { context, size in
                    guard peak > 0 else { return }
                    for (column, value) in zip(columns, values) where value > 0 {
                        let bounds = xBounds(column, width: size.width)
                        let gap = min(2, (bounds.upperBound - bounds.lowerBound) * 0.2)
                        let height = CGFloat(value / peak) * usable
                        let bar = CGRect(x: bounds.lowerBound + gap / 2, y: size.height - 1 - height,
                                         width: max(0, bounds.upperBound - bounds.lowerBound - gap), height: height)
                        var barContext = context
                        barContext.opacity = inspectedColumn == nil || inspectedColumn?.id == column.id ? 1 : 0.55
                        barContext.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(color))
                    }
                }
                if peak == 0 && !isLoading {
                    Text(L10n.text("此时间窗口内没有费用", "No cost in this range"))
                        .font(.ui(11))
                        .foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoveredID = isLoading ? nil : column(at: point.x, width: proxy.size.width)?.id
                case .ended: hoveredID = nil
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let column = inspectedColumn {
                    let width = min(220, proxy.size.width)
                    let bounds = xBounds(column, width: proxy.size.width)
                    let midpoint = (bounds.lowerBound + bounds.upperBound) / 2
                    let preferred = midpoint < proxy.size.width / 2 ? midpoint + 12 : midpoint - width - 12
                    detail(column)
                        .frame(width: width)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: max(0, min(preferred, proxy.size.width - width)), y: -6)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("费用估算图表", "Estimated cost chart"))
        .accessibilityValue(inspectedColumn.map(description) ?? L10n.text("悬停查看时间段", "Hover to inspect a period"))
    }

    private func xBounds(_ column: CostColumn, width: CGFloat) -> ClosedRange<CGFloat> {
        let left = column.interval.start.timeIntervalSince(plotInterval.start) / plotInterval.duration * width
        let right = column.interval.end.timeIntervalSince(plotInterval.start) / plotInterval.duration * width
        return left...right
    }

    private func column(at x: CGFloat, width: CGFloat) -> CostColumn? {
        guard width > 0 else { return nil }
        let date = plotInterval.start.addingTimeInterval(max(0, min(1, x / width)) * plotInterval.duration)
        return columns.first { date >= $0.interval.start && date < $0.interval.end }
            ?? columns.last.flatMap { date == $0.interval.end ? $0 : nil }
    }

    private func detail(_ column: CostColumn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(period(column)).font(.ui(11)).foregroundStyle(theme.secondary)
            Text(amount(column)).font(.tabular(14, .semibold))
            if column.interval.start < interval.start || column.interval.end > interval.end {
                Text(L10n.text("仅统计所选范围内的部分时段", "Partial period within the selected range"))
                    .font(.ui(11)).foregroundStyle(theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .foregroundStyle(theme.text)
        // Raised in the HUD's look, as the token chart's column details are on the island.
        .raisedBox(theme, hud: look)
    }

    /// The column's estimated cost, as the card writes an estimate; unpriced where a request in it had no price.
    private func amount(_ column: CostColumn) -> String {
        column.amount.map { MoneyFormat.amount($0, currency: currency, estimated: true) } ?? L10n.text("暂无价格", "Unpriced")
    }

    private func period(_ column: CostColumn) -> String {
        let start = max(column.interval.start, interval.start)
        return ChartData.period(DateInterval(start: start, end: max(start, min(column.interval.end, interval.end))))
    }

    private func description(_ column: CostColumn) -> String {
        [period(column), amount(column)].joined(separator: "\n")
    }
}
