import Foundation

extension UsageLedger {
    public enum QuotaCapacityAdjustmentError: Error, LocalizedError {
        case invalidMultiplier, historicalCycleNotFound, readingsDoNotMatch
        public var errorDescription: String? {
            switch self {
            case .invalidMultiplier: L10n.text("请输入大于 1 的额度倍率。", "Enter a capacity multiplier greater than 1.")
            case .historicalCycleNotFound: L10n.text("未找到对应的周期记录。", "The cycle record could not be found.")
            case .readingsDoNotMatch: L10n.text("读数已过期或与倍率不符，请核对变更记录。", "The readings expired or do not match this multiplier.")
            }
        }
    }

    public func quotaCapacityCandidates(recordID: String) throws -> [QuotaCapacityCandidate] {
        guard let record = try quotaCycleRecords().first(where: { $0.id == recordID }) else { return [] }
        let samples = try capacitySamples(record)
        return zip(samples, samples.dropFirst()).compactMap { before, after in
            guard after.remainingPct > before.remainingPct + 2, after.remainingPct < 100 else { return nil }
            return QuotaCapacityCandidate(before: before, after: after)
        }
    }

    /// Records a user-supplied explanation for one historical rise. Raw samples, cycle boundaries and call amounts
    /// are unchanged. Both adjacent readings must exist and agree with the specified capacity ratio.
    public func confirmQuotaCapacityIncrease(recordID: String, observedAfter: Date, observedAt: Date,
                                            multiplier: Double, note: String = "") throws -> QuotaCycleRecord {
        guard multiplier.isFinite, multiplier > 1 else { throw QuotaCapacityAdjustmentError.invalidMultiplier }
        guard var record = try quotaCycleRecords().first(where: { $0.id == recordID }),
              observedAfter >= record.firstObserved, observedAt <= record.lastObserved else {
            throw QuotaCapacityAdjustmentError.historicalCycleNotFound
        }
        let samples = try capacitySamples(record)
        guard let pair = zip(samples, samples.dropFirst()).first(where: { $0.timestamp == observedAfter && $1.timestamp == observedAt }),
              pair.1.remainingPct > pair.0.remainingPct + 2,
              abs(pair.1.remainingPct - (100 - (100 - pair.0.remainingPct) / multiplier)) <= 2 else {
            throw QuotaCapacityAdjustmentError.readingsDoNotMatch
        }
        let change = QuotaCapacityChange(observedAfter: observedAfter, observedAt: observedAt, multiplier: multiplier, note: note)
        var changes = record.capacityChanges ?? []
        changes.removeAll { $0.observedAfter == observedAfter && $0.observedAt == observedAt }
        changes.append(change)
        record.capacityChanges = changes.sorted { $0.observedAt < $1.observedAt }
        // A confirmed increase explains only this rise, never a separate outage or unexplained recovery.
        record.hasObservationGap = samples.first?.timestamp != record.firstObserved || samples.last?.timestamp != record.lastObserved ||
            hasGap(samples, confirmedChanges: changes)
        let data = try JSONEncoder().encode(record)
        try write { writer in
            try writer.storage.connection.run("UPDATE quota_cycle SET record = ? WHERE id = ?", [.blob(data), .text(recordID)])
        }
        return record
    }

    public func removeQuotaCapacityIncrease(recordID: String, observedAt: Date) throws {
        guard var record = try quotaCycleRecords().first(where: { $0.id == recordID }) else {
            throw QuotaCapacityAdjustmentError.historicalCycleNotFound
        }
        let changes = (record.capacityChanges ?? []).filter { $0.observedAt != observedAt }
        record.capacityChanges = changes.isEmpty ? nil : changes
        let samples = try capacitySamples(record)
        record.hasObservationGap = samples.first?.timestamp != record.firstObserved || samples.last?.timestamp != record.lastObserved ||
            hasGap(samples, confirmedChanges: changes)
        let data = try JSONEncoder().encode(record)
        try write { try $0.storage.connection.run("UPDATE quota_cycle SET record = ? WHERE id = ?", [.blob(data), .text(recordID)]) }
    }

    private func capacitySamples(_ record: QuotaCycleRecord) throws -> [QuotaSample] {
        var samples: [QuotaSample] = []
        try storage.connection.query("""
            SELECT observed_at, MIN(remaining) FROM quota_sample
            WHERE window_id = ? AND observed_at BETWEEN ? AND ? GROUP BY observed_at ORDER BY observed_at
            """, [.text(record.windowID), .real(record.firstObserved.timeIntervalSinceReferenceDate),
                  .real(record.lastObserved.timeIntervalSinceReferenceDate)]) { row in
            samples.append(QuotaSample(agentId: record.windowID,
                timestamp: Date(timeIntervalSinceReferenceDate: row.double(0)), remainingPct: row.double(1)))
        }
        return samples
    }
}
