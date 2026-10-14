import SwiftUI
import AgentHUDCore

/// An account's quota windows side by side, up to four to a line, each in an equal share of the width. A last line
/// with fewer windows keeps the columns of the lines above it.
struct QuotaCellGrid<Cell: View>: View {
    let rows: [AgentRow]
    @ViewBuilder let cell: (AgentRow) -> Cell

    private static var perLine: Int { 4 }

    private var lines: [[AgentRow]] {
        stride(from: 0, to: rows.count, by: Self.perLine).map { Array(rows[$0..<min($0 + Self.perLine, rows.count)]) }
    }

    var body: some View {
        let lines = lines
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(line) { row in
                        cell(row).frame(maxWidth: .infinity)
                    }
                    if lines.count > 1 {
                        ForEach(0..<(Self.perLine - line.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, IslandRowLayout.inset)
        .padding(.vertical, 2)
    }
}

/// One quota window as a ring or a number: the readings a bar row shows, in a cell. A ring is the share used, with
/// the selected measure in the line under its name; a number is the selected measure itself. Either keeps one height
/// in every measure, so flipping the picker never resizes the panel.
struct QuotaCell: View {
    enum Style { case ring, number }

    let row: AgentRow
    let metrics: QuotaRowMetrics
    let metric: PanelMeasure
    let style: Style
    let showReset: Bool
    var forecastHint: String?
    var isLoading = false
    private let theme = Theme.island

    var body: some View {
        Group {
            switch style {
            case .ring: ring
            case .number: number
            }
        }
        .help(forecastHint ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.agent.name)
        .accessibilityValue(spokenValue)
    }

    /// What the cell says in place of its parts: everything it shows. A ring shows the share used whatever the
    /// measure, so that comes first, before the selected measure and its caption.
    var spokenValue: String {
        let share = style == .ring && metric != .quota ? metrics.value(.quota) : nil
        return [share, metrics.value(metric), caption].compactMap { $0 }.joined(separator: ", ")
    }

    private var levelColor: Color { theme.status(row.level ?? .ok) }

    private var metricColor: Color {
        guard row.level != nil else { return theme.secondary }
        switch metric {
        case .quota: return levelColor
        case .burnRate: return metrics.runsOut ? theme.status(.warning) : theme.status(.ok)
        case .tokens, .cost: return theme.status(.ok)
        }
    }

    private var captionColor: Color { metric == .burnRate && metrics.runsOut ? theme.status(.warning) : theme.secondary }

    /// The line beside the value: the reset for the share used, where the countdown is shown; else the measure's detail.
    private var caption: String? {
        metric == .quota && !showReset ? nil : metrics.detail(metric, isLoading: isLoading)
    }

    private var projectedUsedPct: Double? {
        guard metric == .burnRate, let used = row.usedPct else { return nil }
        return metrics.runsOut ? 100 : metrics.projectedAtReset ?? used
    }

    // MARK: Ring

    private var ring: some View {
        VStack(spacing: 5) {
            ZStack {
                RingTrack(fraction: (row.usedPct ?? 0) / 100, projectedFraction: projectedUsedPct.map { $0 / 100 },
                          fill: isLoading || row.level == nil ? theme.secondary : levelColor,
                          projectionFill: metrics.runsOut ? theme.status(.warning) : theme.secondary,
                          track: theme.track, isLoading: isLoading)
                Text(row.usedPct.map(TokenFormat.percent) ?? row.missingQuotaLabel)
                    .font(.tabular(11, .semibold))
                    .foregroundStyle(row.level == nil ? theme.secondary : levelColor)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .frame(width: 46, height: 46)
            name(.ui(12, .medium), color: theme.text)
            // The share used is in the ring, so the line under the name carries the selected measure.
            line(metric == .quota ? caption : [metrics.value(metric), caption].compactMap { $0 }.joined(separator: " · "),
                 short: metric == .quota ? nil : metrics.value(metric))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Number

    private var number: some View {
        VStack(alignment: .leading, spacing: 3) {
            name(.ui(11), color: theme.secondary)
            Text(metrics.value(metric) ?? "—")
                .font(.tabular(15, .semibold))
                .foregroundStyle(metrics.value(metric) == nil ? theme.secondary : metricColor)
                .lineLimit(1)
                .contentTransition(.numericText())
            line(caption, short: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Parts

    /// A name is never cut: one too long for the cell gives way to the window's short name.
    private func name(_ font: Font, color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(row.agent.name)
            Text(row.agent.shortName)
        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
    }

    /// The caption in one line; where it is too long for the cell, its short form. A missing caption keeps the line's
    /// height, so the cell is as tall in every measure.
    private func line(_ text: String?, short: String?) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(text.flatMap { $0.isEmpty ? nil : $0 } ?? " ")
            if let short { Text(short) }
        }
        .font(.tabular(11))
        .foregroundStyle(captionColor)
        .lineLimit(1)
        .contentTransition(.numericText())
    }
}

/// A ring's used share from twelve o'clock, with the share projected by the reset under it: what `ProgressTrack` is
/// to a bar.
struct RingTrack: View {
    var fraction: Double
    var projectedFraction: Double? = nil
    let fill: Color
    var projectionFill: Color? = nil
    let track: Color
    var lineWidth: CGFloat = 4
    var isLoading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().strokeBorder(track, lineWidth: lineWidth)
            if isLoading {
                if reduceMotion {
                    Circle().strokeBorder(fill.opacity(0.3), lineWidth: lineWidth)
                } else {
                    Circle().strokeBorder(fill, lineWidth: lineWidth)
                        .phaseAnimator([false, true]) { content, bright in
                            content.opacity(bright ? 0.45 : 0.12)
                        } animation: { _ in
                            .easeInOut(duration: 1)
                        }
                }
            } else {
                // The projection is always drawn, from the used share on, so it grows out of the ring's end.
                arc(to: max(projectedFraction ?? 0, fraction), color: (projectionFill ?? fill).opacity(0.38))
                arc(to: fraction, color: fill)
            }
        }
    }

    private func arc(to end: Double, color: Color) -> some View {
        Circle().inset(by: lineWidth / 2)
            .trim(from: 0, to: min(1, max(0, end)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}
