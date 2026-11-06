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

    func testLegacyHistoryBackfillsRecoveriesAndMergesCurrentCycleIdempotently() async throws {
        let ledger = UsageLedger.inMemory()
        let samples = [(0.0, 100.0), (100, 70), (200, 100), (300, 40), (400, 100), (500, 70)].map {
            QuotaSample(agentId: agent.id, timestamp: base.addingTimeInterval($0.0), remainingPct: $0.1)
        }
        try await ledger.write {
            try $0.appendSamples(samples, scope: "codex")
            try $0.upsert(source: "codex", contribution: "legacy", events: [
                self.event("first", at: 50), self.event("second", at: 250, model: "codex-model:gpt-6-luna"), self.event("current", at: 450),
                self.event("uncertain-reset-interval", at: 150), self.event("after-reading", at: 650),
            ])
        }
        let result = try await ledger.recordQuotaCycles(report: report(600, remaining: 60), agents: [agent], localUsageOnly: true)
        XCTAssertEqual(result.count, 3)
        let archived = result.filter { $0.endedAt != nil }.sorted { $0.firstObserved < $1.firstObserved }
        XCTAssertEqual(archived.map(\.usage.tokens), [1_000_000, 1_000_000])
        XCTAssertEqual(archived.first?.resetObservedAfter, base.addingTimeInterval(100))
        XCTAssertEqual(archived.first?.endedAt, base.addingTimeInterval(200))
        XCTAssertEqual(archived.first?.endedBy, .observedRecovery)
        XCTAssertNil(archived.first?.plan, "do not apply today's plan to historical records")
        XCTAssertNotNil(archived.first?.estimatedCapacity)
        let current = try XCTUnwrap(result.first { $0.endedAt == nil })
        XCTAssertEqual(current.firstObserved, base.addingTimeInterval(400))
        XCTAssertEqual(current.start, base.addingTimeInterval(400), "manual recovery must exclude earlier cycles even when the deadline is unchanged")
        XCTAssertEqual(current.initialRemaining, 100)
        XCTAssertEqual(current.observedUsage.tokens, 1_000_000)
        XCTAssertEqual(current.usage.tokens, 1_000_000)
        XCTAssertEqual(current.resetAt, base.addingTimeInterval(604800))
        let repeated = try await ledger.recordQuotaCycles(report: report(600, remaining: 60), agents: [agent], localUsageOnly: true)
        XCTAssertEqual(result, repeated)
    }

    func testLocalUsageModeIncludesCallsAcrossAccountsWithoutSuppressingEstimate() async throws {
        let ledger = UsageLedger.inMemory()
        _ = try await ledger.recordQuotaCycles(report: report(0, remaining: 100), agents: [agent], localUsageOnly: true)
        try await ledger.write {
            try $0.upsert(source: "codex", contribution: "local", events: [self.event("a", at: 10)])
            try $0.upsert(source: "codex", contribution: "other", account: "another-account", events: [self.event("b", at: 20)])
        }
        let result = try await ledger.recordQuotaCycles(report: report(100, remaining: 90), agents: [agent], localUsageOnly: true)
        let record = try XCTUnwrap(result.first)
        XCTAssertEqual(record.usage.tokens, 2_000_000)
        XCTAssertTrue(record.hasUnassignedUsage)
        XCTAssertNotNil(record.estimatedCapacity)
        let amount = try XCTUnwrap(record.observedUsage.amounts["USD"])
        XCTAssertEqual(record.estimatedCapacity?["USD"], amount * 10)
    }

    func testLegacyRecoveryWithObservationGapStillShowsCostButDoesNotEstimate() async throws {
        let ledger = UsageLedger.inMemory()
        let samples = [(0.0, 100.0), (30_000, 10), (30_100, 100)].map {
            QuotaSample(agentId: agent.id, timestamp: base.addingTimeInterval($0.0), remainingPct: $0.1)
        }
        try await ledger.write {
            try $0.appendSamples(samples, scope: "codex")
            try $0.upsert(source: "codex", contribution: "legacy", events: [self.event("a", at: 50)])
        }
        let result = try await ledger.recordQuotaCycles(report: report(30_200, remaining: 90), agents: [agent], localUsageOnly: true)
        let old = try XCTUnwrap(result.first { $0.endedAt != nil })
        XCTAssertTrue(old.hasObservationGap)
        XCTAssertEqual(old.usage.tokens, 1_000_000)
        XCTAssertNotNil(old.usage.amounts["USD"])
        XCTAssertNil(old.estimatedCapacity)
    }

    func testLegacyHistoryDoesNotInventResetFromSmallRisesOrElapsedWeeks() async throws {
        let ledger = UsageLedger.inMemory()
        let samples = [(0.0, 80.0), (100, 82), (700_000, 10)].map {
            QuotaSample(agentId: agent.id, timestamp: base.addingTimeInterval($0.0), remainingPct: $0.1)
        }
        try await ledger.write { try $0.appendSamples(samples, scope: "codex") }
        let result = try await ledger.recordQuotaCycles(report: report(700_100, remaining: 9, reset: 1_209_600), agents: [agent], localUsageOnly: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.legacyHistoryImported == true)
        XCTAssertNil(result.first?.endedAt)
    }

    func testLegacyImportKeepsItsSummariesAfterSampleExpiryAndReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let ledger = try UsageLedger(url: url)
        let samples = [(0.0, 100.0), (100, 10), (200, 100)].map {
            QuotaSample(agentId: agent.id, timestamp: base.addingTimeInterval($0.0), remainingPct: $0.1)
        }
        try await ledger.write {
            try $0.appendSamples(samples, scope: "codex")
            try $0.upsert(source: "codex", contribution: "legacy", events: [self.event("a", at: 50)])
        }
        _ = try await ledger.recordQuotaCycles(report: report(300, remaining: 90), agents: [agent], localUsageOnly: true)
        try await ledger.expire(now: base.addingTimeInterval(40 * 86400))
        let reopened = try UsageLedger(url: url)
        let saved = try await reopened.quotaCycleRecords()
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first { $0.endedAt != nil }?.usage.tokens, 1_000_000)
        let repeated = try await reopened.recordQuotaCycles(report: report(300, remaining: 90), agents: [agent], localUsageOnly: true)
        XCTAssertEqual(repeated.count, 2)
    }

    func testCapacityIncreaseIsEditableDataAndNormalizesTheSameCycle() async throws {
        let ledger = UsageLedger.inMemory()
        let samples = [(0.0, 80.0), (100, 0), (200, 50), (300, 40), (400, 100)].map {
            QuotaSample(agentId: agent.id, timestamp: base.addingTimeInterval($0.0), remainingPct: $0.1)
        }
        try await ledger.write {
            try $0.appendSamples(samples, scope: "codex")
            try $0.upsert(source: "codex", contribution: "legacy", events: [self.event("a", at: 50), self.event("b", at: 250)])
        }
        let result = try await ledger.recordQuotaCycles(report: report(500, remaining: 90), agents: [agent], localUsageOnly: true)
        let old = try XCTUnwrap(result.first { $0.endedAt != nil })
        XCTAssertTrue(old.hasObservationGap)
        XCTAssertNil(old.estimatedCapacity)
        let candidates = try await ledger.quotaCapacityCandidates(recordID: old.id)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.suggestedMultiplier, 2)
        let changed = try await ledger.confirmQuotaCapacityIncrease(recordID: old.id,
            observedAfter: base.addingTimeInterval(100), observedAt: base.addingTimeInterval(200), multiplier: 2, note: "Promotion")
        XCTAssertFalse(changed.hasObservationGap)
        XCTAssertEqual(changed.observedPercent, 50, "20% used before doubling is 10% of the final capacity; end is 60% used")
        XCTAssertEqual(changed.initialRemaining, 80, "original readings remain unchanged")
        XCTAssertEqual(changed.capacityChanges?.first?.note, "Promotion")
        let cost = try XCTUnwrap(changed.observedUsage.amounts["USD"])
        XCTAssertEqual(changed.estimatedCapacity?["USD"], cost * 2)
        _ = try await ledger.confirmQuotaCapacityIncrease(recordID: old.id,
            observedAfter: base.addingTimeInterval(100), observedAt: base.addingTimeInterval(200), multiplier: 2, note: "Edited")
        let saved = try await ledger.quotaCycleRecords()
        XCTAssertEqual(saved.count, 2, "a capacity increase does not create a cycle")
        XCTAssertEqual(saved.first { $0.id == old.id }?.capacityChanges?.count, 1)
        try await ledger.removeQuotaCapacityIncrease(recordID: old.id, observedAt: base.addingTimeInterval(200))
        let removed = try await ledger.quotaCycleRecords()
        XCTAssertTrue(removed.first { $0.id == old.id }?.hasObservationGap == true)
        XCTAssertNil(removed.first { $0.id == old.id }?.estimatedCapacity)
        let original = try await ledger.samples(scope: "codex", windowID: agent.id, since: base)
        XCTAssertEqual(original, samples)
    }

    func testConfirmedCapacityChangeDoesNotHideAnUnrelatedObservationGap() async throws {
        let ledger = UsageLedger.inMemory()
        let samples = [(0.0, 100.0), (30_000, 0), (30_100, 50), (30_200, 0), (30_300, 100)].map {
            QuotaSample(agentId: agent.id, timestamp: base.addingTimeInterval($0.0), remainingPct: $0.1)
        }
        try await ledger.write { try $0.appendSamples(samples, scope: "codex") }
        let result = try await ledger.recordQuotaCycles(report: report(30_400, remaining: 90), agents: [agent], localUsageOnly: true)
        let old = try XCTUnwrap(result.first { $0.endedAt != nil })
        let changed = try await ledger.confirmQuotaCapacityIncrease(recordID: old.id,
            observedAfter: base.addingTimeInterval(30_000), observedAt: base.addingTimeInterval(30_100), multiplier: 2)
        XCTAssertTrue(changed.hasObservationGap, "the separate 8-hour outage still matters")
        var rejected = false
        do {
            _ = try await ledger.confirmQuotaCapacityIncrease(recordID: old.id,
                observedAfter: base.addingTimeInterval(30_000), observedAt: base.addingTimeInterval(30_100), multiplier: 3)
        } catch { rejected = true }
        XCTAssertTrue(rejected, "a multiplier inconsistent with the original pair is rejected")
    }

    func testCycleMoneyUsesEachPromptsTierBeforeCombiningTokens() async throws {
        let ledger = UsageLedger.inMemory()
        let id = account.id
        _ = try await feed(ledger, 0, remaining: 100)
        try await ledger.write {
            try $0.upsert(source: "codex", contribution: "tiers", account: id, events: [
                self.event("short-1", at: 10, input: 150_000),
                self.event("short-2", at: 20, input: 150_000),
                self.event("long", at: 30, input: 300_000),
                .init(key: "cached-long", timestamp: self.base.addingTimeInterval(40), agentId: self.consumer,
                      tokensIn: 10_000, tokensOut: 20_000, cacheReadTokens: 290_000),
            ])
        }
        let result = try await feed(ledger, 100, remaining: 90)
        let record = try XCTUnwrap(result.first)
        // Two short prompts: $0.60, one long prompt: $1.20, cached long prompt: $0.398.
        // A cache-heavy prompt reaches the tier using fresh + cached input, not fresh input alone.
        XCTAssertEqual(record.usage.amounts["USD"], Decimal(string: "2.198")!)
        XCTAssertEqual(record.observedUsage.amounts, record.usage.amounts)
        XCTAssertEqual(record.estimatedCapacity?["USD"], Decimal(string: "21.98")!)
        XCTAssertEqual(record.usage.baseAmounts?["USD"], Decimal(string: "1.449")!)
        XCTAssertEqual(record.estimatedReferenceCapacity?["USD"], Decimal(string: "14.49")!,
                       "API long-context surcharges must not inflate the base-price quota reference")
        XCTAssertEqual(record.usage.tokens, 920_000)
        XCTAssertEqual(record.estimatedTokenCapacity, 9_200_000)
    }

    func testLegacyAmountsCannotSilentlyBecomeTheQuotaReference() throws {
        var old = QuotaCycleUsage()
        old.tokens = 1_000
        old.amounts = ["USD": 10]
        old.baseAmounts = nil
        var known = QuotaCycleUsage()
        known.tokens = 1_000
        known.amounts = ["USD": 20]
        known.baseAmounts = ["USD": 12]
        let total = old + known
        XCTAssertEqual(total.amounts["USD"], 30)
        XCTAssertNil(total.baseAmounts, "an expired day's unknown base amount must not become a partial dollar total")
        var record = try XCTUnwrap(DemoData.quotaCycles.first)
        record.observedDays = ["old": old]
        let saved = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(QuotaCycleRecord.self, from: saved)
        XCTAssertNotNil(decoded.estimatedCapacity)
        XCTAssertNil(decoded.estimatedReferenceCapacity)
    }

    func testTokenProjectionNeedsCoverageButDoesNotNeedModelPrices() throws {
        var record = try XCTUnwrap(DemoData.quotaCycles.first)
        var observed = QuotaCycleUsage()
        observed.tokens = 1_000
        observed.unpricedTokens = 1_000
        record.observedDays = ["sample": observed]
        XCTAssertNotNil(record.estimatedTokenCapacity, "missing prices must not hide known tokens")
        record.hasObservationGap = true
        XCTAssertNil(record.estimatedTokenCapacity)
        record.hasObservationGap = false
        record.remaining = 99
        XCTAssertNil(record.estimatedTokenCapacity, "one percent is too little evidence")
        record.remaining = 90
        XCTAssertEqual(record.estimatedTokenCapacity, 10_000)
    }
}
