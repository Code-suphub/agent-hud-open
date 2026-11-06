import Foundation

/// A confirmed quota occurrence and its locally observed calls. These summaries outlive raw ledger retention.
/// No subscription quota is denominated in money: amounts and estimates are public API price equivalents only.
public struct QuotaCycleRecord: Identifiable, Hashable, Codable, Sendable {
    public enum Boundary: String, Codable, Sendable { case firstObservation, naturalReset, restored, planChanged }
    public let id: String
    public let windowID: String
    public let accountID: String
    public var vendor: String
    public var window: String
    public var accountLabel: String
    public let plan: String?
    public let start: Date
    public let firstObserved: Date
    public let initialRemaining: Double
    public let beganBy: Boundary
    public var lastObserved: Date
    public var remaining: Double
    public var resetAt: Date
    public var duration: TimeInterval
    public var endedAt: Date?
    public var endedBy: Boundary?
    /// Day partitions are replaced while raw calls remain available; older partitions remain frozen.
    public var usageDays: [String: QuotaCycleUsage] = [:]
    public var observedDays: [String: QuotaCycleUsage] = [:]
    public var hasObservationGap = false
    public var hasUnobservedTail = false
    public var hasUnassignedUsage = false
    public var usageUnavailable = false

    public var usage: QuotaCycleUsage { usageDays.values.reduce(QuotaCycleUsage(), +) }
    public var observedUsage: QuotaCycleUsage { observedDays.values.reduce(QuotaCycleUsage(), +) }
    public var consumedPercent: Double { max(0, min(100, 100 - remaining)) }
    public var observedPercent: Double { max(0, initialRemaining - remaining) }
    public var partial: Bool {
        initialRemaining < 99 || firstObserved.timeIntervalSince(start) > 300 || hasObservationGap || hasUnobservedTail ||
            hasUnassignedUsage || usageUnavailable || usage.unpricedTokens > 0
    }
    /// An observed-interval estimate, not the service's official quota. At least five percentage points and two
    /// readings are needed; unpriced or unattributed calls, indexing and gaps suppress the estimate.
    public var estimatedCapacity: [String: Decimal]? {
        let observed = observedUsage
        guard observedPercent >= 5, lastObserved > firstObserved, !hasObservationGap, !hasUnassignedUsage,
              !usageUnavailable, observed.unpricedTokens == 0, observed.tokens > 0,
              observed.amounts.count == 1, observed.amounts.values.allSatisfy({ $0 > 0 }) else { return nil }
        return observed.amounts.mapValues { $0 * 100 / Decimal(observedPercent) }
    }
}

public struct QuotaCycleUsage: Hashable, Codable, Sendable {
    public var tokens: Int = 0
    public var unpricedTokens: Int = 0
    public var unassignedTokens: Int = 0
    public var amounts: [String: Decimal] = [:]

    public static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result.tokens += rhs.tokens
        result.unpricedTokens += rhs.unpricedTokens
        result.unassignedTokens += rhs.unassignedTokens
        for (currency, amount) in rhs.amounts { result.amounts[currency, default: 0] += amount }
        return result
    }
}
