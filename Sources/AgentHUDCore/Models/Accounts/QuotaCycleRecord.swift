import Foundation

/// A confirmed quota occurrence and its locally observed calls. These summaries outlive raw ledger retention.
/// No subscription quota is denominated in money: amounts and estimates are public API price equivalents only.
public struct QuotaCycleRecord: Identifiable, Hashable, Codable, Sendable {
    public enum Boundary: String, Codable, Sendable { case firstObservation, naturalReset, restored, planChanged, observedRecovery }
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
    /// Optional fields keep records written by earlier builds decodable.
    public var localUsageOnly: Bool?
    public var legacyHistoryImported: Bool?
    /// Legacy readings bracket a recovery; they do not contain the service's reset deadline.
    public var startObservedAfter: Date?
    public var resetObservedAfter: Date?
    public var capacityChanges: [QuotaCapacityChange]?
    public var pricingRevision: String?

    public var usage: QuotaCycleUsage { usageDays.values.reduce(QuotaCycleUsage(), +) }
    public var observedUsage: QuotaCycleUsage { observedDays.values.reduce(QuotaCycleUsage(), +) }
    public var consumedPercent: Double { max(0, min(100, 100 - remaining)) }
    /// Compare both endpoints against the final capacity. An increase is not a reset: e.g. 20% spent before a
    /// doubling becomes 10% of the final allowance. Original provider percentages remain untouched.
    public var observedPercent: Double {
        let multiplier = (capacityChanges ?? []).filter { $0.observedAt > firstObserved && $0.observedAt <= lastObserved }
            .reduce(1.0) { $0 * $1.multiplier }
        guard multiplier.isFinite, multiplier >= 1 else { return 0 }
        return max(0, (100 - remaining) - (100 - initialRemaining) / multiplier)
    }
    public var partial: Bool {
        initialRemaining < 99 || firstObserved.timeIntervalSince(start) > 300 || hasObservationGap || hasUnobservedTail ||
            (hasUnassignedUsage && localUsageOnly != true) || usageUnavailable || usage.unpricedTokens > 0
    }
    /// An observed-interval estimate, not the service's official quota. At least five percentage points and two
    /// readings are needed. Missing calls and sampling gaps are tolerated; unpriced calls cost zero.
    public var estimatedCapacity: [String: Decimal]? {
        estimate(observedUsage.amounts)
    }
    /// A comparable base-price reference, without API long-context surcharges. It is not a subscription rate card.
    public var estimatedReferenceCapacity: [String: Decimal]? {
        estimate(observedUsage.baseAmounts)
    }
    /// A projection from the same observed interval as the money estimate, independent of price availability.
    public var estimatedTokenCapacity: Int? {
        guard canEstimateObservedInterval else { return nil }
        let value = Double(observedUsage.tokens) * 100 / observedPercent
        guard value.isFinite, value > 0, value.rounded() < Double(Int.max) else { return nil }
        return Int(value.rounded())
    }
    private var canEstimateObservedInterval: Bool {
        observedPercent >= 5 && lastObserved > firstObserved &&
            (!hasUnassignedUsage || localUsageOnly == true) && !usageUnavailable && observedUsage.tokens > 0
    }
    private func estimate(_ amounts: [String: Decimal]?) -> [String: Decimal]? {
        let observed = observedUsage
        guard canEstimateObservedInterval, let amounts else { return nil }
        let known = amounts.isEmpty && observed.unpricedTokens > 0 ? ["USD": Decimal.zero] : amounts
        guard known.count == 1, known.values.allSatisfy({ !$0.isNaN && $0 >= 0 }) else { return nil }
        return known.mapValues { $0 * 100 / Decimal(observedPercent) }
    }
}

/// An explicit user explanation of a historical capacity increase, bracketed by the original readings.
/// Never infer these changes from a rising percentage alone.
public struct QuotaCapacityChange: Hashable, Codable, Sendable {
    public let observedAfter: Date
    public let observedAt: Date
    public let multiplier: Double
    public let note: String?

    public init(observedAfter: Date, observedAt: Date, multiplier: Double, note: String = "") {
        self.observedAfter = observedAfter
        self.observedAt = observedAt
        self.multiplier = multiplier
        self.note = note.isEmpty ? nil : String(note.prefix(500))
    }
}

public struct QuotaCapacityCandidate: Identifiable, Hashable, Sendable {
    public let before: QuotaSample
    public let after: QuotaSample
    public var id: Date { after.timestamp }
    public var suggestedMultiplier: Double { (100 - before.remainingPct) / (100 - after.remainingPct) }
}

public struct QuotaCycleUsage: Hashable, Codable, Sendable {
    public var tokens: Int = 0
    public var unpricedTokens: Int = 0
    public var unassignedTokens: Int = 0
    public var amounts: [String: Decimal] = [:]
    /// Nil for old summaries that have not been repriced; never substitute a tiered API amount for this reference.
    public var baseAmounts: [String: Decimal]? = [:]

    public static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result.tokens += rhs.tokens
        result.unpricedTokens += rhs.unpricedTokens
        result.unassignedTokens += rhs.unassignedTokens
        for (currency, amount) in rhs.amounts { result.amounts[currency, default: 0] += amount }
        if (lhs.baseAmounts == nil && lhs.tokens > 0) || (rhs.baseAmounts == nil && rhs.tokens > 0) {
            result.baseAmounts = nil
        } else {
            var base = lhs.baseAmounts ?? [:]
            for (currency, amount) in rhs.baseAmounts ?? [:] { base[currency, default: 0] += amount }
            result.baseAmounts = base
        }
        return result
    }
}
