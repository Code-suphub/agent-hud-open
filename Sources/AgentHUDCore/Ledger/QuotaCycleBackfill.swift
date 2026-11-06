import AgentHUDSupport
import Foundation

extension UsageLedger {
    /// A current report may cover only seven days while legacy calls span thirty-one. Plan-wide windows must include
    /// retained models from those same execution clients, even when the current report no longer lists them.
    func quotaCycleConsumers(agent: AgentDescriptor, report: UsageReport) throws -> Set<String> {
        var ids = report.consumerIdsByQuota[agent.id] ?? []
        guard agent.allModels else { return ids }
        let prefixes = Set(ids.compactMap { id in id.range(of: "-model:").map { String(id[..<$0.upperBound]) } })
        guard !prefixes.isEmpty else { return ids }
        try storage.connection.query("SELECT name FROM agent") { row in
            if let name = row.text(0), prefixes.contains(where: { name.hasPrefix($0) }) { ids.insert(name) }
        }
        return ids
    }

    /// Old samples preserve percentages, not reset deadlines or plan history. Import only the prefix before the
    /// first confirmed cycle, splitting on observed recoveries to 100%; never manufacture weekly boundaries.
    func backfillQuotaCycles(_ records: inout [QuotaCycleRecord], agent: AgentDescriptor, report: UsageReport,
                             regions: PriceRegions, localUsageOnly: Bool) throws {
        let indices = records.indices.filter { records[$0].windowID == agent.id }
        guard !indices.contains(where: { records[$0].legacyHistoryImported == true }),
              let index = indices.min(by: { records[$0].firstObserved < records[$1].firstObserved }) else { return }
        let original = records[index]
        guard original.beganBy == .firstObservation else {
            records[index].legacyHistoryImported = true
            return
        }
        var samples: [QuotaSample] = []
        try storage.connection.query("""
            SELECT observed_at, MIN(remaining) FROM quota_sample
            WHERE window_id = ? AND observed_at <= ? AND remaining BETWEEN 0 AND 100
            GROUP BY observed_at ORDER BY observed_at
            """, [.text(agent.id), .real(original.lastObserved.timeIntervalSinceReferenceDate)]) { row in
            samples.append(QuotaSample(agentId: agent.id, timestamp: Date(timeIntervalSinceReferenceDate: row.double(0)),
                                       remainingPct: row.double(1)))
        }
        records[index].legacyHistoryImported = true
        guard let first = samples.first, first.timestamp < original.firstObserved else { return }
        var segments: [[QuotaSample]] = [[first]]
        for sample in samples.dropFirst() {
            let previous = segments[segments.count - 1].last!
            if sample.remainingPct == 100, sample.remainingPct - previous.remainingPct >= AlertPolicy.resetRise,
               sample.timestamp <= original.firstObserved {
                segments.append([sample])
            } else {
                segments[segments.count - 1].append(sample)
            }
        }
        let consumers = try quotaCycleConsumers(agent: agent, report: report)
        for offset in segments.indices.dropLast() {
            let segment = segments[offset]
            let first = segment.first!, last = segment.last!, next = segments[offset + 1].first!
            var record = QuotaCycleRecord(
                id: RecordCoding.hash([agent.id, "legacy", String(first.timestamp.timeIntervalSince1970)]),
                windowID: agent.id, accountID: original.accountID, vendor: agent.vendor, window: agent.model,
                accountLabel: original.accountLabel, plan: nil,
                start: first.timestamp, firstObserved: first.timestamp, initialRemaining: first.remainingPct,
                beganBy: offset == 0 ? .firstObservation : .observedRecovery,
                lastObserved: last.timestamp, remaining: last.remainingPct, resetAt: next.timestamp, duration: 0)
            record.endedAt = next.timestamp
            record.endedBy = .observedRecovery
            record.resetObservedAfter = last.timestamp
            if offset > 0 { record.startObservedAfter = segments[offset - 1].last!.timestamp }
            record.hasUnobservedTail = true
            record.localUsageOnly = localUsageOnly
            record.legacyHistoryImported = true
            record.hasObservationGap = hasGap(segment)
            try updateUsage(&record, consumers: consumers, report: report, regions: regions)
            records.append(record)
        }
        // The final segment is the cycle already on screen, not another cycle created by installing this build.
        // A service deadline can stay unchanged after a manual reset. Do not charge earlier cycles again.
        let tail = segments.last!.filter { $0.timestamp >= original.start }
        guard let baseline = tail.first, baseline.timestamp < original.firstObserved else { return }
        let recoveryLower = segments.count > 1 ? segments[segments.count - 2].last!.timestamp : nil
        let inferredStart = recoveryLower.map { original.start < $0 } ?? false
        var merged = QuotaCycleRecord(
            id: original.id, windowID: original.windowID, accountID: original.accountID, vendor: original.vendor,
            window: original.window, accountLabel: original.accountLabel, plan: original.plan,
            start: inferredStart ? baseline.timestamp : original.start,
            firstObserved: baseline.timestamp, initialRemaining: baseline.remainingPct,
            beganBy: inferredStart ? .observedRecovery : original.beganBy,
            lastObserved: original.lastObserved, remaining: original.remaining, resetAt: original.resetAt, duration: original.duration)
        merged.endedAt = original.endedAt
        merged.endedBy = original.endedBy
        merged.localUsageOnly = localUsageOnly
        merged.legacyHistoryImported = true
        merged.hasObservationGap = original.hasObservationGap || hasGap(tail)
        merged.hasUnobservedTail = original.hasUnobservedTail
        merged.capacityChanges = original.capacityChanges
        if inferredStart { merged.startObservedAfter = recoveryLower }
        merged.usageDays = original.usageDays
        merged.observedDays = original.observedDays
        try updateUsage(&merged, consumers: consumers, report: report, regions: regions)
        records[index] = merged
    }

    func hasGap(_ samples: [QuotaSample], confirmedChanges: [QuotaCapacityChange] = []) -> Bool {
        zip(samples, samples.dropFirst()).contains { previous, next in
            let explained = confirmedChanges.contains { $0.observedAfter == previous.timestamp && $0.observedAt == next.timestamp }
            return next.timestamp.timeIntervalSince(previous.timestamp) > 6 * 3600 ||
                (next.remainingPct > previous.remainingPct + 2 && !explained)
        }
    }
}
