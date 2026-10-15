import Foundation

/// The span of actual readings in the same uninterrupted series used for the burn rate.
public struct QuotaSampling: Hashable, Codable, Sendable {
    public let elapsed: TimeInterval
    public let required: TimeInterval
    public let afterReset: Bool

    public init(elapsed: TimeInterval, required: TimeInterval, afterReset: Bool) {
        self.elapsed = elapsed
        self.required = required
        self.afterReset = afterReset
    }

    public var hint: String {
        let reason = afterReset
            ? L10n.text("额度已重置，正在重新采样", "Quota reset; collecting new readings")
            : L10n.text("首次采样，正在积累预测数据", "Collecting initial readings for a forecast")
        // Round down the observed span: a partial minute must not claim the minimum has been met.
        let observed = elapsed < 60 ? L10n.text("不足1分", "less than 1m") : Countdown.forecast(floor(elapsed / 60) * 60)
        let minimum = Countdown.forecast(required)
        return reason + "\n" + L10n.text("已采样 \(observed)，预测至少需要\(minimum)的有效记录", "Sampled \(observed); at least \(minimum) of readings needed")
    }
}
