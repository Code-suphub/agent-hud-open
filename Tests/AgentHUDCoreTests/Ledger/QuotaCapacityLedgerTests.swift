import XCTest
@testable import AgentHUDCore

final class QuotaCapacityLedgerTests: XCTestCase, @unchecked Sendable {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let model = "codex-model:gpt-6.1-sol"
    private var observation: QuotaObservation {
        .init(start: base.addingTimeInterval(600), end: base.addingTimeInterval(700), remainingAtStart: 80, remainingAtEnd: 70)
    }
    private var snapshot: UsageSnapshot {
        .init(agentId: "q", remainingPct: 70, resetAt: base.addingTimeInterval(604800), windowDuration: 604800,
              updatedAt: base.addingTimeInterval(700))
    }
    private func event(_ key: String, _ second: Double, model: String? = nil, tokens: Int = 1_000) -> UsageLedger.Event {
        .init(key: key, timestamp: base.addingTimeInterval(second), agentId: model ?? self.model, tokensIn: tokens, tokensOut: 0)
    }
    private func estimate(_ ledger: UsageLedger, consumers: Set<String>? = nil, observation: QuotaObservation? = nil) async throws -> QuotaCapacityEstimate? {
        try await ledger.quotaCapacityEstimate(snapshot: snapshot, observation: observation ?? self.observation,
            consumers: consumers ?? [model], regions: PriceRegions(report: nil), now: base.addingTimeInterval(710))
    }
    func testExactCallsAcrossPartialBucketsExcludeBaselineAndIncludeFinalReading() async throws {
        let ledger = UsageLedger.inMemory()
        try await ledger.write { try $0.upsert(source: "codex", contribution: "events", events: [
            self.event("before", 500), self.event("baseline", 600), self.event("inside", 650),
            self.event("final", 700), self.event("after", 750), self.event("other", 650, model: "other")]) }
        let estimated = try await estimate(ledger)
        let value = try XCTUnwrap(estimated)
        XCTAssertEqual(value.tokens, 20_000)
        let cost = try XCTUnwrap(ModelCatalog.cost(agentId: model, summed: TokenKinds(input: 2_000)))
        XCTAssertEqual(value.amounts?[cost.currency], cost.amount * 10)
        let buckets = try await ledger.buckets(since: base)
        XCTAssertNil(QuotaMath.capacityEstimate(snapshot: snapshot, observation: observation, consumers: [model], usage: buckets,
            regions: PriceRegions(report: nil), now: base.addingTimeInterval(710)))
        let insights = UsageInsights(burnRatePctPerHour: 10, timeToExhaust: 3600, weeklyCapHits: 0,
            weeklyWaitTotal: 0, weeklyWaitLongest: 0, weeklyWaitLongestAt: nil, capacityObservation: observation, exactCapacityEstimate: value)
        let decoded = try JSONDecoder().decode(UsageInsights.self, from: JSONEncoder().encode(insights))
        XCTAssertEqual(decoded.exactCapacityEstimate, value)
    }
    func testLateCorrectionsInvalidateCachedProjection() async throws {
        let ledger = UsageLedger.inMemory()
        try await ledger.write { try $0.upsert(source: "codex", contribution: "events", events: [self.event("old", 500), self.event("inside", 650)]) }
        let first = try await estimate(ledger)
        XCTAssertEqual(first?.tokens, 10_000)
        try await ledger.write { try $0.upsert(source: "codex", contribution: "events", events: [self.event("old", 500), self.event("inside", 650, tokens: 2_000)]) }
        let corrected = try await estimate(ledger)
        XCTAssertEqual(corrected?.tokens, 20_000)
    }
    func testUnknownPriceDoesNotHideKnownTokens() async throws {
        let ledger = UsageLedger.inMemory()
        let unknown = "codex-model:no-price-test-model"
        try await ledger.write { try $0.upsert(source: "codex", contribution: "events", events: [self.event("old", 500), self.event("inside", 650, model: unknown)]) }
        let value = try await estimate(ledger, consumers: [unknown])
        XCTAssertEqual(value?.tokens, 10_000)
        XCTAssertNil(value?.amounts)
        XCTAssertTrue(value?.hasUnpricedUsage == true)
    }
    func testReportUsesExactProjectionButHidesItWhileIndexingOrAfterReset() {
        let value = QuotaCapacityEstimate(tokens: 20_000, amounts: ["USD": 40], hasUnpricedUsage: false)
        let insight = UsageInsights(burnRatePctPerHour: 10, timeToExhaust: 3600, weeklyCapHits: 0,
            weeklyWaitTotal: 0, weeklyWaitLongest: 0, weeklyWaitLongestAt: nil, capacityObservation: observation, exactCapacityEstimate: value)
        let agent = AgentDescriptor(id: "q", vendor: "Codex", model: "Weekly", source: "test", enabled: true)
        func view(indexing: IndexProgress? = nil, now: Date? = nil) -> ReportView {
            let report = UsageReport(generatedAt: snapshot.updatedAt, snapshots: [snapshot], sessions: [],
                discoveredAgents: [agent], indexing: indexing, insightsByAgent: ["q": insight], consumerIdsByQuota: ["q": [model]])
            return ReportView(report: report, agents: [agent], settings: Settings(), now: now ?? base.addingTimeInterval(710))
        }
        XCTAssertEqual(view().capacityEstimate(for: "q"), value)
        XCTAssertNil(view(indexing: .init(done: 1, total: 2)).capacityEstimate(for: "q"))
        XCTAssertNil(view(now: base.addingTimeInterval(604801)).capacityEstimate(for: "q"))
    }
    func testInsufficientOrMismatchedQuotaEvidenceDoesNotProject() async throws {
        let ledger = UsageLedger.inMemory()
        try await ledger.write { try $0.upsert(source: "codex", contribution: "events", events: [self.event("inside", 650)]) }
        let tiny = QuotaObservation(start: observation.start, end: observation.end, remainingAtStart: 74, remainingAtEnd: 70)
        let mismatch = QuotaObservation(start: observation.start, end: observation.end, remainingAtStart: 80, remainingAtEnd: 69)
        let small = try await estimate(ledger, observation: tiny)
        let stale = try await estimate(ledger, observation: mismatch)
        XCTAssertNil(small)
        XCTAssertNil(stale)
    }
}
