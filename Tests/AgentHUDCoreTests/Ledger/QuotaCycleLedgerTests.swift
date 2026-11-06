import XCTest
@testable import AgentHUDCore

final class QuotaCycleLedgerTests: XCTestCase, @unchecked Sendable {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private var account: ProviderAccount { .init(provider: "Codex", user: "test", workspace: "", evidence: .account) }
    private let consumer = "codex-model:gpt-6.1-sol"
    private var agent: AgentDescriptor {
        .init(id: account.windowID("weekly"), vendor: "Codex", model: "Weekly limit", source: "test", enabled: true, account: account)
    }
    private func report(_ seconds: Double, remaining: Double, reset: Double = 604800, duration: Double = 604800,
                        credits: Int = 0, notice: String? = nil, current: Bool = true, plan: String = "pro") -> UsageReport {
        let date = base.addingTimeInterval(seconds)
        return UsageReport(generatedAt: date, snapshots: [UsageSnapshot(agentId: agent.id, remainingPct: remaining,
            resetAt: base.addingTimeInterval(reset), windowDuration: duration, updatedAt: date)], sessions: [],
            discoveredAgents: [agent], sourceNotices: notice.map { ["Codex": $0] } ?? [:],
            consumerIdsByQuota: [agent.id: [consumer]], codexResetCredits: .init(availableCount: credits, credits: nil),
            accounts: ["Codex": [.init(account: account, label: "Test account", plan: plan, observedAt: date, isCurrent: current)]])
    }
    private func event(_ key: String, at: Double, model: String = "codex-model:gpt-6.1-sol", input: Int = 1_000_000) -> UsageLedger.Event {
        .init(key: key, timestamp: base.addingTimeInterval(at), agentId: model, tokensIn: input, tokensOut: 0)
    }
    private func feed(_ ledger: UsageLedger, _ seconds: Double, remaining: Double, reset: Double = 604800) async throws -> [QuotaCycleRecord] {
        try await ledger.recordQuotaCycles(report: report(seconds, remaining: remaining, reset: reset), agents: [agent])
    }

    func testRepeatedSamplesAndResetCreditGrantsDoNotStartCycles() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await feed(ledger, 0, remaining: 100)
        let granted = report(120, remaining: 100, credits: 2)
        _ = try await ledger.recordQuotaCycles(report: granted, agents: [agent])
        let repeated = try await ledger.recordQuotaCycles(report: granted, agents: [agent])
        XCTAssertEqual(repeated.count, 1)
        XCTAssertEqual(repeated.first?.lastObserved, base.addingTimeInterval(120))
        let stale = try await feed(ledger, 60, remaining: 20)
        XCTAssertEqual(stale.first?.remaining, 100)
    }

    func testMatchedIntervalEstimateUsesExactCallsAndPreservesIntegers() async throws {
        let ledger = UsageLedger.inMemory()
        let id = account.id
        _ = try await feed(ledger, 600, remaining: 80)
        try await ledger.write { writer in
            try writer.upsert(source: "codex", contribution: "test", account: id, events: [
                self.event("before-baseline", at: 500), self.event("after-baseline", at: 650),
                self.event("after-reading", at: 750),
            ])
        }
        let records = try await feed(ledger, 700, remaining: 70)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.usage.tokens, 2_000_000)
        XCTAssertEqual(record.observedUsage.tokens, 1_000_000)
        let amount = try XCTUnwrap(record.observedUsage.amounts["USD"])
        XCTAssertGreaterThan(amount, 0)
        XCTAssertEqual(record.estimatedCapacity?["USD"], amount * 10)
        XCTAssertTrue(record.partial, "first observation was midcycle")
        let repeated = try await feed(ledger, 700, remaining: 70)
        XCTAssertEqual(records, repeated)
        XCTAssertNotNil(ModelCatalog.model(for: consumer), "fixture must be a priced model")
    }

    func testManualResetRetainingDeadlineArchivesWithoutInferringFinalUsage() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await feed(ledger, 0, remaining: 100)
        _ = try await feed(ledger, 100, remaining: 8)
        let records = try await feed(ledger, 200, remaining: 100)
        XCTAssertEqual(records.count, 2)
        let old = try XCTUnwrap(records.first { $0.endedAt != nil })
        XCTAssertEqual(old.endedBy, .restored)
        XCTAssertEqual(old.remaining, 8, "reset does not imply the old cycle reached zero")
        XCTAssertEqual(records.first?.start, base.addingTimeInterval(200))
        XCTAssertEqual(records.first?.resetAt, old.resetAt)
    }

    func testNaturalResetNeedsANewConfirmedReadingAndDoesNotGuessMissingCycles() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await feed(ledger, 0, remaining: 100, reset: 300)
        let pastDeadline = UsageReport(generatedAt: base.addingTimeInterval(500), snapshots: report(0, remaining: 100, reset: 300).snapshots,
                                      sessions: [], discoveredAgents: [agent])
        let waiting = try await ledger.recordQuotaCycles(report: pastDeadline, agents: [agent])
        XCTAssertEqual(waiting.count, 1)
        let records = try await feed(ledger, 510, remaining: 95, reset: 604800 + 300)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.endedAt != nil }?.endedBy, .naturalReset)
    }

    func testUnattributedCallsAndUnknownModelsSuppressEstimate() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await feed(ledger, 0, remaining: 100)
        try await ledger.write { try $0.upsert(source: "codex", contribution: "local", events: [self.event("local", at: 10)]) }
        let sampled = try await feed(ledger, 120, remaining: 90)
        let record = try XCTUnwrap(sampled.first)
        XCTAssertEqual(record.usage.tokens, 1_000_000)
        XCTAssertTrue(record.hasUnassignedUsage)
        XCTAssertNil(record.estimatedCapacity)
        let id = account.id
        let unknown = "codex-model:no-price-test-model"
        try await ledger.write { try $0.upsert(source: "codex", contribution: "unknown", account: id,
                                              events: [self.event("unknown", at: 130, model: unknown)]) }
        var next = report(240, remaining: 80)
        next = UsageReport(generatedAt: next.generatedAt, snapshots: next.snapshots, sessions: [], discoveredAgents: [agent],
                           consumerIdsByQuota: [agent.id: [consumer, unknown]], accounts: next.accounts)
        let records = try await ledger.recordQuotaCycles(report: next, agents: [agent])
        XCTAssertEqual(records.first?.usage.unpricedTokens, 1_000_000)
        XCTAssertNil(records.first?.estimatedCapacity)
    }

    func testFailedAndOtherAccountsCannotChangeBaselineOrContributeCalls() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await feed(ledger, 0, remaining: 100)
        let id = account.id
        try await ledger.write {
            try $0.upsert(source: "codex", contribution: "mine", account: id, events: [self.event("mine", at: 10)])
            try $0.upsert(source: "codex", contribution: "other", account: "another-account", events: [self.event("other", at: 10)])
        }
        let failed = try await ledger.recordQuotaCycles(report: report(60, remaining: 90, notice: "offline"), agents: [agent])
        XCTAssertEqual(failed.first?.remaining, 100)
        let inactive = try await ledger.recordQuotaCycles(report: report(70, remaining: 90, current: false), agents: [agent])
        XCTAssertEqual(inactive.first?.remaining, 100)
        let records = try await feed(ledger, 120, remaining: 90)
        XCTAssertEqual(records.first?.usage.tokens, 1_000_000)
    }

    func testSmallConsumptionDoesNotEstimateAndPlanChangesSplitHistory() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await feed(ledger, 0, remaining: 100)
        let id = account.id
        try await ledger.write { try $0.upsert(source: "codex", contribution: "test", account: id, events: [self.event("a", at: 10)]) }
        let small = try await feed(ledger, 120, remaining: 98)
        XCTAssertNil(small.first?.estimatedCapacity)
        let records = try await ledger.recordQuotaCycles(report: report(240, remaining: 97, plan: "max"), agents: [agent])
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.endedAt != nil }?.endedBy, .planChanged)
    }

    func testLateCorrectionsReplaceDayTotalsInsteadOfAddingThemAgain() async throws {
        let ledger = UsageLedger.inMemory()
        let id = account.id
        _ = try await feed(ledger, 0, remaining: 100)
        try await ledger.write { try $0.upsert(source: "codex", contribution: "test", account: id, events: [self.event("a", at: 10)]) }
        _ = try await feed(ledger, 120, remaining: 90)
        try await ledger.write { try $0.upsert(source: "codex", contribution: "test", account: id,
                                              events: [self.event("a", at: 10, input: 2_000_000)]) }
        let corrected = try await feed(ledger, 240, remaining: 80)
        XCTAssertEqual(corrected.first?.usage.tokens, 2_000_000)
        XCTAssertEqual(corrected.first?.observedUsage.tokens, 2_000_000)
    }

    func testActiveLongCycleKeepsExpiredDaySummaries() async throws {
        let ledger = UsageLedger.inMemory()
        let id = account.id
        let duration = 60.0 * 86400
        _ = try await ledger.recordQuotaCycles(report: report(0, remaining: 100, reset: duration, duration: duration), agents: [agent])
        try await ledger.write { try $0.upsert(source: "codex", contribution: "early", account: id, events: [self.event("a", at: 10)]) }
        _ = try await ledger.recordQuotaCycles(report: report(120, remaining: 90, reset: duration, duration: duration), agents: [agent])
        let later = 40.0 * 86400
        try await ledger.expire(now: base.addingTimeInterval(later))
        try await ledger.write { try $0.upsert(source: "codex", contribution: "later", account: id,
                                              events: [self.event("b", at: later - 10, input: 2_000_000)]) }
        let records = try await ledger.recordQuotaCycles(report: report(later, remaining: 50, reset: duration, duration: duration), agents: [agent])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.usage.tokens, 3_000_000)
        XCTAssertTrue(records.first?.hasObservationGap == true)
    }

    func testCurrenciesStaySeparateAndCannotFormOneEstimate() throws {
        var record = try XCTUnwrap(DemoData.quotaCycles.first)
        var usage = QuotaCycleUsage()
        usage.tokens = 1_000
        usage.amounts = ["USD": 10, "CNY": 20]
        record.usageDays = ["day": usage]
        record.observedDays = ["day": usage]
        XCTAssertEqual(record.usage.amounts, ["USD": 10, "CNY": 20])
        XCTAssertNil(record.estimatedCapacity)
    }

    func testSummariesSurviveReopenAndRawExpiryAndForgetConsent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let ledger = try UsageLedger(url: url)
        _ = try await feed(ledger, 0, remaining: 100)
        let id = account.id
        try await ledger.write { try $0.upsert(source: "codex", contribution: "test", account: id, events: [self.event("a", at: 10)]) }
        _ = try await feed(ledger, 100, remaining: 90)
        _ = try await feed(ledger, 200, remaining: 100)
        try await ledger.expire(now: base.addingTimeInterval(40 * 86400))
        let reopened = try UsageLedger(url: url)
        let records = try await reopened.quotaCycleRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.endedAt != nil }?.usage.tokens, 1_000_000)
        let forgotten = UsageReport(generatedAt: base, snapshots: [], sessions: [], forgottenAccountProviders: ["Codex"])
        let cleared = try await reopened.recordQuotaCycles(report: forgotten, agents: [agent])
        XCTAssertTrue(cleared.isEmpty)
    }
}
