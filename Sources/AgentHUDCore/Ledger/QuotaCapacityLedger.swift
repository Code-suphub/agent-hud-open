import Foundation
import AgentHUDSupport

struct QuotaCapacityLedgerKey: Hashable {
    let observation: QuotaObservation
    let consumers: Set<String>
    let regions: PriceRegions
}
struct QuotaCapacityLedgerCache {
    let mark: Int
    let generation: Int
    let priceRevision: String
    var values: [QuotaCapacityLedgerKey: QuotaCapacityEstimate] = [:]
}

extension UsageLedger {
    /// Match raw calls in (start, end] to the quota readings. Keeps the HUD's base-rate cost convention.
    public func quotaCapacityEstimate(snapshot: UsageSnapshot, observation: QuotaObservation?, consumers: Set<String>,
                                      regions: PriceRegions, now: Date) throws -> QuotaCapacityEstimate? {
        guard let observation,
              let consumed = QuotaMath.capacityConsumed(snapshot: snapshot, observation: observation, consumers: consumers, now: now) else { return nil }
        let revision = ModelPriceFeed.sourceInfo.revision
        if quotaCapacityRead?.mark != writeMark || quotaCapacityRead?.generation != generation || quotaCapacityRead?.priceRevision != revision {
            quotaCapacityRead = QuotaCapacityLedgerCache(mark: writeMark, generation: generation, priceRevision: revision)
        }
        let key = QuotaCapacityLedgerKey(observation: observation, consumers: consumers, regions: regions)
        if let cached = quotaCapacityRead?.values[key] { return cached }
        let ids = String(decoding: try JSONEncoder().encode(consumers.sorted()), as: UTF8.self)
        let listings = Dictionary(uniqueKeysWithValues: consumers.compactMap { id in
            ModelCatalog.listing(for: id, in: regions.region(for: id)).map { (id, $0) }
        })
        var tokens = 0, amounts: [String: Decimal] = [:], unpriced = false, invalid = false
        try storage.connection.query("""
            SELECT e.timestamp_ms, a.name, e.tokens_in, e.tokens_out, e.cache_read, e.cache_write, e.reasoning
            FROM usage_event e JOIN contribution c ON c.id = e.contribution_id JOIN agent a ON a.id = e.agent
            WHERE c.counted = 1 AND e.timestamp_ms > ? AND e.timestamp_ms <= ?
              AND a.name IN (SELECT value FROM json_each(?))
            """, [.integer(RecordCoding.milliseconds(observation.start)), .integer(RecordCoding.milliseconds(observation.end)), .text(ids)]) { row in
            let input = Int(row.int(2)), output = Int(row.int(3)), read = Int(row.int(4))
            let write = Int(row.int(5)), reasoning = Int(row.int(6))
            let (fresh, firstOverflow) = input.addingReportingOverflow(output)
            let (total, secondOverflow) = fresh.addingReportingOverflow(read)
            let (sum, thirdOverflow) = tokens.addingReportingOverflow(total)
            guard !firstOverflow, !secondOverflow, !thirdOverflow, [input, output, read, write, reasoning].allSatisfy({ $0 >= 0 }) else {
                invalid = true; return
            }
            tokens = sum
            guard total > 0 else { return }
            let kinds = TokenKinds(tokensIn: input, tokensOut: output, cacheRead: read, cacheWrite: write, reasoning: reasoning)
            if let listing = listings[row.text(1) ?? ""] {
                let cost = ModelCatalog.cost(kinds, tier: nil, on: listing, at: RecordCoding.date(row.int(0) / 900000 * 900000))
                amounts[cost.currency, default: 0] += cost.amount
            } else { unpriced = true }
        }
        let projected = (Double(tokens) * 100 / consumed).rounded()
        guard !invalid, projected.isFinite, projected > 0, projected < Double(Int.max) else { return nil }
        let money = QuotaListCost(amounts: amounts, hours: observation.end.timeIntervalSince(observation.start) / 3600,
                                 hasUnpricedUsage: unpriced).estimatedCapacity(usedPercent: consumed)
        let result = QuotaCapacityEstimate(tokens: Int(projected), amounts: money, hasUnpricedUsage: unpriced)
        if (quotaCapacityRead?.values.count ?? 0) >= 64 { quotaCapacityRead?.values = [:] }
        quotaCapacityRead?.values[key] = result
        return result
    }
}
