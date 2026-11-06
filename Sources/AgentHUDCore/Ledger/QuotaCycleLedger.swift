import AgentHUDSupport
import Foundation

extension UsageLedger {
    /// Every saved occurrence, newest first. Archived records are deliberately independent of raw event retention.
    public func quotaCycleRecords() throws -> [QuotaCycleRecord] {
        var result: [QuotaCycleRecord] = []
        try storage.connection.query("SELECT record FROM quota_cycle ORDER BY observed_at DESC, id") { row in
            if let data = row.blob(0) { result.append(try JSONDecoder().decode(QuotaCycleRecord.self, from: data)) }
        }
        return result
    }

    /// A serial collection pass updates histories from confirmed readings only. Receiving reset credits has no
    /// bearing here; neither does the wall clock passing a deadline. All changes form one ledger transaction.
    public func recordQuotaCycles(report: UsageReport, agents: [AgentDescriptor]) throws -> [QuotaCycleRecord] {
        let original = try quotaCycleRecords()
        let forgotten = report.forgottenAccountProviders ?? []
        var records = original.filter { !forgotten.contains($0.vendor) }
        let regions = PriceRegions(report: report)
        let rows = Dictionary((agents + report.discoveredAgents).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for index in records.indices where records[index].endedAt == nil {
            if let row = rows[records[index].windowID], !report.isCurrent(row) ||
                report.snapshot(for: row.id).map({ $0.remainingPct == nil }) == true {
                records[index].hasObservationGap = true
            }
        }
        for agent in rows.values where !agent.isAPIBilled && !forgotten.contains(agent.vendor) {
            guard let account = agent.account, account.evidence != .unresolved,
                  report.assess(.window(agent), now: report.generatedAt).confirmsEvents,
                  let snapshot = report.snapshot(for: agent.id), let cycle = snapshot.cycle,
                  let remaining = snapshot.remainingPct, remaining.isFinite, (0...100).contains(remaining),
                  snapshot.updatedAt >= cycle.start else { continue }
            let observation = report.observation(accountID: account.id)
            let plan = observation?.plan
            let previous = records.firstIndex { $0.windowID == agent.id && $0.endedAt == nil }
            var boundary = QuotaCycleRecord.Boundary.firstObservation
            var start = cycle.start
            if let previous {
                var old = records[previous]
                guard snapshot.updatedAt > old.lastObserved else { continue }
                let advanced = cycle.resetAt > old.resetAt && snapshot.updatedAt >= old.resetAt
                let restored = remaining == 100 && remaining - old.remaining >= AlertPolicy.resetRise
                let changedPlan = plan != nil && old.plan != nil && plan != old.plan
                if advanced || restored || changedPlan {
                    boundary = changedPlan ? .planChanged : advanced ? .naturalReset : .restored
                    old.endedBy = boundary
                    old.endedAt = advanced ? old.resetAt : snapshot.updatedAt
                    // A reset's first reading cannot tell what was spent since the old window's last reading.
                    if old.endedAt!.timeIntervalSince(old.lastObserved) > 0 { old.hasUnobservedTail = true }
                    records[previous] = old
                    start = advanced ? max(old.resetAt, cycle.start) : snapshot.updatedAt
                } else {
                    if snapshot.updatedAt.timeIntervalSince(old.lastObserved) > 6 * 3600 ||
                        remaining > old.remaining + 2 || cycle.duration != old.duration {
                        old.hasObservationGap = true
                    }
                    old.lastObserved = snapshot.updatedAt
                    old.remaining = remaining
                    old.resetAt = cycle.resetAt
                    old.duration = cycle.duration
                    try updateUsage(&old, consumers: report.consumerIdsByQuota[agent.id] ?? [],
                                    report: report, regions: regions)
                    records[previous] = old
                    continue
                }
            }
            var record = QuotaCycleRecord(
                id: RecordCoding.hash([agent.id, String(snapshot.updatedAt.timeIntervalSince1970)]),
                windowID: agent.id, accountID: account.id, vendor: agent.vendor, window: agent.model,
                accountLabel: observation?.label ?? String(account.id.suffix(8)), plan: plan,
                start: start, firstObserved: snapshot.updatedAt, initialRemaining: remaining, beganBy: boundary,
                lastObserved: snapshot.updatedAt, remaining: remaining, resetAt: cycle.resetAt, duration: cycle.duration)
            try updateUsage(&record, consumers: report.consumerIdsByQuota[agent.id] ?? [], report: report, regions: regions)
            records.append(record)
        }
        let oldByID = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
        let saved = records.filter { oldByID[$0.id] != $0 }
        let remainingIDs = Set(records.map(\.id))
        let removed = original.filter { !remainingIDs.contains($0.id) }.map(\.id)
        if !saved.isEmpty || !removed.isEmpty { try write { writer in
            for id in removed { try writer.storage.connection.run("DELETE FROM quota_cycle WHERE id = ?", [.text(id)]) }
            for record in saved {
                try writer.storage.connection.run("""
                    INSERT INTO quota_cycle (id, window_id, observed_at, record) VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET observed_at = excluded.observed_at, record = excluded.record
                    """, [.text(record.id), .text(record.windowID), .real(record.firstObserved.timeIntervalSince1970),
                          .blob(try JSONEncoder().encode(record))])
            }
        }
        }
        return records.sorted { ($0.firstObserved, $0.id) > ($1.firstObserved, $1.id) }
    }

    private func updateUsage(_ record: inout QuotaCycleRecord, consumers: Set<String>, report: UsageReport,
                             regions: PriceRegions) throws {
        guard !consumers.isEmpty else { record.usageUnavailable = true; return }
        record.usageUnavailable = report.indexing != nil
        // Keep full UTC days older than the raw ledger's retention. Never replace an expired partition with zero.
        let rawCutoff = report.generatedAt.addingTimeInterval(-Self.retention).timeIntervalSince1970
        let safeDay = ceil(rawCutoff / 86400) * 86400
        let since = max(record.start, Date(timeIntervalSince1970: safeDay))
        if since > record.start && record.usageDays.isEmpty { record.hasObservationGap = true }
        let accounts = Set(report.accountObservations.filter { $0.account.provider == record.vendor && $0.isCurrent }.map { $0.account.id })
        let allowLocal = accounts == [record.accountID]
        let known = try cycleUsageDays(since: since, until: record.lastObserved, consumers: consumers,
                                       account: record.accountID, allowLocal: allowLocal, regions: regions)
        replaceDays(&record.usageDays, with: known, since: since)
        let observedSince = max(record.firstObserved, since)
        let observed = try cycleUsageDays(since: observedSince, until: record.lastObserved, consumers: consumers,
                                          account: record.accountID, allowLocal: allowLocal, regions: regions)
        replaceDays(&record.observedDays, with: observed, since: observedSince)
        record.hasUnassignedUsage = record.hasUnassignedUsage || record.usage.unassignedTokens > 0 || !allowLocal
    }

    private func replaceDays(_ days: inout [String: QuotaCycleUsage], with new: [String: QuotaCycleUsage], since: Date) {
        let first = Int64(floor(since.timeIntervalSince1970 / 86400))
        days = days.filter { (Int64($0.key) ?? 0) < first }
        days.merge(new, uniquingKeysWith: { _, new in new })
    }

    /// Exact call timestamps, not whole 15-minute chart buckets, keep reset boundaries and sample intervals aligned.
    private func cycleUsageDays(since: Date, until: Date, consumers: Set<String>, account: String,
                                allowLocal: Bool, regions: PriceRegions) throws -> [String: QuotaCycleUsage] {
        guard until > since else { return [:] }
        let ids = String(decoding: try JSONEncoder().encode(consumers.sorted()), as: UTF8.self)
        var days: [String: QuotaCycleUsage] = [:]
        try storage.connection.query("""
            SELECT e.timestamp_ms / 86400000, a.name, c.account,
                   SUM(e.tokens_in), SUM(e.tokens_out), SUM(e.cache_read), SUM(e.cache_write), SUM(e.reasoning),
                   e.timestamp_ms / 900000 * 900000
            FROM usage_event e JOIN contribution c ON c.id = e.contribution_id JOIN agent a ON a.id = e.agent
            WHERE c.counted = 1 AND e.timestamp_ms > ? AND e.timestamp_ms <= ?
              AND a.name IN (SELECT value FROM json_each(?))
              AND (c.account = ? OR (? = 1 AND c.account = ''))
            GROUP BY e.timestamp_ms / 86400000, a.name, c.account, e.timestamp_ms / 900000
            """, [.integer(RecordCoding.milliseconds(since)), .integer(RecordCoding.milliseconds(until)), .text(ids),
                  .text(account), .integer(allowLocal ? 1 : 0)]) { row in
            let agent = row.text(1) ?? ""
            let bucket = UsageBucket(start: RecordCoding.date(row.int(8)), agentId: agent,
                                     tokensIn: Int(row.int(3)), tokensOut: Int(row.int(4)), cacheReadTokens: Int(row.int(5)),
                                     cacheWriteTokens: Int(row.int(6)), reasoningTokens: Int(row.int(7)))
            var usage = QuotaCycleUsage()
            usage.tokens = bucket.total + bucket.cacheReadTokens
            if row.text(2) != account { usage.unassignedTokens = usage.tokens }
            if let cost = ModelCatalog.cost(of: bucket, regions: regions) { usage.amounts[cost.currency] = cost.total }
            else { usage.unpricedTokens = usage.tokens }
            let key = String(row.int(0))
            days[key] = (days[key] ?? QuotaCycleUsage()) + usage
        }
        return days
    }
}
