import Foundation

/// What an API account spent in one currency over a period, by the costs Agent HUD recorded for its requests, and the
/// pace that sets: a balance's burn rate, as a quota window's is the pace its share rises at. The cost is the estimate
/// of the requests this Mac's clients logged, priced as the Tokens page prices them, so spending elsewhere is not in it;
/// `BalanceTrend` reads the balance's own fall instead, which counts it, over the day before its reading.
public struct BalanceSpend: Hashable, Sendable {
    public let currency: String
    /// The estimated cost of the recorded requests over the period.
    public let cost: Decimal
    /// How long the period had run at the time of the data, in seconds: from its start to that time, or to its end where
    /// that came first. Above zero.
    public let span: TimeInterval

    public init(currency: String, cost: Decimal, span: TimeInterval) {
        self.currency = currency
        self.cost = cost
        self.span = span
    }

    /// The cost per day over the period so far, the days without a recorded request included.
    public var perDay: Decimal { cost * Decimal(Self.day) / Decimal(span) }

    /// When `amount`, read at `readAt`, reaches zero at `perDay`: nil where nothing was spent over the period, so the
    /// pace gives no time, and for an amount at or below zero, which has run out.
    public func runsOutAt(_ amount: Decimal, readAt: Date) -> Date? {
        guard cost > 0, amount > 0 else { return nil }
        let seconds = NSDecimalNumber(decimal: amount / cost).doubleValue * span
        guard seconds.isFinite else { return nil }
        return readAt.addingTimeInterval(seconds)
    }

    private static let day: Int = 86400
}

public extension APIBilling {
    /// What the account spent in `currency` over `interval`, by its recorded costs, up to `now`: the sum of the recorded
    /// 15-minute costs that overlap it, as `estimatedCost(currency:during:)` adds them, over the part of it that had run
    /// by `now`. Nil when one of those requests had no price in the currency, or before the interval begins.
    func spend(currency: String, during interval: DateInterval, now: Date) -> BalanceSpend? {
        let span = min(now, interval.end).timeIntervalSince(interval.start)
        guard span > 0, let cost = estimatedCost(currency: currency, during: interval) else { return nil }
        return BalanceSpend(currency: currency, cost: cost, span: span)
    }
}
