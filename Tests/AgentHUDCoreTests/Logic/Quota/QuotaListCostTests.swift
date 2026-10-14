import XCTest
@testable import AgentHUDCore

final class QuotaListCostTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600
    private let priced = "claude-model:claude-opus-5-5"
    private let regions = PriceRegions(report: nil)

    /// A window that resets in two hours and is five long: its cycle began three hours ago.
    private var window: UsageSnapshot {
        UsageSnapshot(agentId: "w", remainingPct: 50, resetAt: now.addingTimeInterval(2 * hour), windowDuration: 5 * hour, updatedAt: now)
    }

    private func bucket(_ offset: TimeInterval, _ model: String, _ tokensIn: Int, out: Int = 0) -> UsageBucket {
        UsageBucket(start: now.addingTimeInterval(offset), agentId: model, tokensIn: tokensIn, tokensOut: out)
    }

    func testACycleCostsWhatItsConsumersSpentInItAtListPrice() throws {
        let inside = [bucket(-2 * hour, priced, 2_000_000, out: 500_000), bucket(-hour, priced, 1_000_000)]
        let usage = [bucket(-4 * hour, priced, 9_000_000)] + inside
            + [bucket(-hour, "claude-model:claude-fable-5-1", 7_000_000), bucket(-hour, "claude-model:no-such-model", 5_000_000),
               bucket(60, priced, 3_000_000)]
        let cost = try XCTUnwrap(QuotaMath.listCost(snapshot: window, consumers: [priced, "claude-model:no-such-model"],
                                                    usage: usage.sorted { $0.start < $1.start }, regions: regions, now: now))
        // What was spent before the cycle, after now, by a model the window does not count, or by one without a price
        // is left out.
        let expected = try inside.map { try XCTUnwrap(ModelCatalog.cost(of: $0, regions: regions)).total }.reduce(0, +)
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(cost.amounts, ["USD": expected])
        XCTAssertEqual(cost.currencies, ["USD"])
        XCTAssertEqual(cost.hours, 3, accuracy: 0.0001)
        XCTAssertEqual(cost.perHour("USD"), expected / 3)
        XCTAssertNil(cost.perHour("CNY"))
    }

    func testTheObservedPartStartsWhereTheHistoryDoes() throws {
        let cost = try XCTUnwrap(QuotaMath.listCost(snapshot: window, consumers: [priced], usage: [bucket(-hour, priced, 1_000_000)],
                                                    regions: regions, now: now))
        XCTAssertEqual(cost.hours, 1, accuracy: 0.0001, "history that begins inside the cycle is all the cycle that was seen")
    }

    func testThereIsNoCostWithoutACycleAConsumerOrAPrice() {
        let usage = [bucket(-hour, priced, 1_000_000)]
        XCTAssertNil(QuotaMath.listCost(snapshot: window, consumers: [], usage: usage, regions: regions, now: now))
        XCTAssertNil(QuotaMath.listCost(snapshot: window, consumers: [priced], usage: [], regions: regions, now: now))
        let untimed = UsageSnapshot(agentId: "w", remainingPct: 50, updatedAt: now)
        XCTAssertNil(QuotaMath.listCost(snapshot: untimed, consumers: [priced], usage: usage, regions: regions, now: now))
        XCTAssertNil(QuotaMath.listCost(snapshot: window, consumers: ["claude-model:no-such-model"],
                                        usage: [bucket(-hour, "claude-model:no-such-model", 1_000_000)], regions: regions, now: now),
                     "tokens of a model without a list price cost nothing that can be said")
    }

    func testAShortAmountDropsItsDecimalsFromAHundredUp() {
        for language in [AppLanguage.zhHans, .en] {
            L10n.setLanguage(language)
            XCTAssertEqual(MoneyFormat.short(Decimal(string: "3.1")!, currency: "USD"), "$3.10")
            XCTAssertEqual(MoneyFormat.short(Decimal(string: "99.994")!, currency: "USD"), "$99.99")
            XCTAssertEqual(MoneyFormat.short(Decimal(string: "412.4")!, currency: "USD"), "$412")
            XCTAssertEqual(MoneyFormat.short(Decimal(string: "1234.5")!, currency: "USD"), "$1,234")
        }
        L10n.setLanguage(.system)
    }
}
