import XCTest
@testable import AgentHUDCore

/// What an API account spent over a period by its recorded costs, the pace that sets, when a balance runs out at it,
/// and the columns a balance's chart draws.
final class BalanceSpendTests: XCTestCase {
    /// On a quarter hour, so recorded costs fall on bucket starts.
    private let now = Date(timeIntervalSince1970: 1_790_001_000)

    /// Recorded 15-minute costs, as (hours before `now`, amounts by currency).
    private func billing(_ costs: [(Double, [String: String])]) -> APIBilling {
        APIBilling(vendor: "DeepSeek", balances: [AccountBalance(currency: "CNY", total: 10, granted: 0, toppedUp: 10)],
                   isAvailable: true, updatedAt: now,
                   costs: costs.map { hours, amounts in
                       CostBucket(start: now.addingTimeInterval(-hours * 3600), amounts: amounts.mapValues { Decimal(string: $0)! })
                   },
                   notice: nil)
    }

    private func week(endingAt end: Date) -> DateInterval { DateInterval(start: end.addingTimeInterval(-7 * 86400), end: end) }

    func testTheSpendIsTheCostOverThePeriodSpreadOverWhatOfItHasRun() throws {
        let account = billing([(200, ["CNY": "9"]), (100, ["CNY": "1.5"]), (2, ["CNY": "0.25", "USD": "0.04"]), (1, ["CNY": "0.25"])])
        let spend = try XCTUnwrap(account.spend(currency: "CNY", during: week(endingAt: now), now: now))
        XCTAssertEqual(spend.cost, Decimal(string: "2"), "the costs recorded within the week, and none from before it")
        XCTAssertEqual(spend.cost, account.estimatedCost(currency: "CNY", during: week(endingAt: now)))
        XCTAssertEqual(spend.span, 7 * 86400)
        XCTAssertEqual(NSDecimalNumber(decimal: spend.perDay).doubleValue, 2.0 / 7, accuracy: 1e-12,
                       "the days without a recorded request count")

        // A period that runs a quarter of an hour past the time of the data, as the panel's do, has run that much less.
        let ahead = week(endingAt: now.addingTimeInterval(900))
        let early = try XCTUnwrap(account.spend(currency: "CNY", during: ahead, now: now))
        XCTAssertEqual(early.span, 7 * 86400 - 900)
        XCTAssertNil(account.spend(currency: "CNY", during: DateInterval(start: now.addingTimeInterval(60), duration: 3600), now: now),
                     "a period that has not begun has no pace")
    }

    func testARequestWithoutAPriceInTheCurrencyLeavesTheSpendUnknown() {
        let account = billing([(3, ["CNY": "0.5", "USD": "0.07"]), (1, ["CNY": "0.25"])])
        XCTAssertNotNil(account.spend(currency: "CNY", during: week(endingAt: now), now: now))
        XCTAssertNil(account.spend(currency: "USD", during: week(endingAt: now), now: now), "the latest request had no dollar price")
        XCTAssertEqual(account.spend(currency: "USD", during: DateInterval(start: now.addingTimeInterval(-4 * 3600), duration: 2 * 3600),
                                     now: now)?.cost, Decimal(string: "0.07"), "a period that leaves it out is priced")
        XCTAssertEqual(billing([]).spend(currency: "CNY", during: week(endingAt: now), now: now)?.cost, 0,
                       "a period without requests costs nothing")
    }

    func testABalanceRunsOutAtThePaceFromTheTimeItWasRead() throws {
        let spend = BalanceSpend(currency: "CNY", cost: 2, span: 2 * 86400)
        XCTAssertEqual(spend.perDay, 1)
        let read = now.addingTimeInterval(-600)
        XCTAssertEqual(try XCTUnwrap(spend.runsOutAt(Decimal(string: "8.5")!, readAt: read)).timeIntervalSince(read), 8.5 * 86400,
                       accuracy: 0.001, "a yuan a day leaves eight and a half days")
        XCTAssertNil(BalanceSpend(currency: "CNY", cost: 0, span: 86400).runsOutAt(10, readAt: read), "nothing spent gives no time")
        XCTAssertNil(spend.runsOutAt(0, readAt: read), "a balance at zero has run out")
        XCTAssertNil(spend.runsOutAt(-1, readAt: read))
    }

    func testABalancesChartAddsUpToItsEstimatedCostInThePeriodsColumns() throws {
        let account = billing([(30, ["CNY": "1"]), (23.75, ["CNY": "0.5"]), (23.5, ["CNY": "0.25"]), (0.25, ["CNY": "0.125", "USD": "0.02"]),
                               (0, ["CNY": "0.125"])])
        let day = DateInterval(start: now.addingTimeInterval(900 - 86400), end: now.addingTimeInterval(900))
        let columns = ChartData.costBars(costs: account.costs, currency: "CNY", interval: day, bucketSize: .minutes15)
        XCTAssertEqual(columns.count, 96)
        XCTAssertEqual(columns.first?.interval.start, day.start)
        XCTAssertEqual(columns.compactMap(\.amount).reduce(0, +), account.estimatedCost(currency: "CNY", during: day))
        XCTAssertEqual(columns.compactMap(\.amount).reduce(0, +), Decimal(string: "1"), "the costs within the day, and none from before it")
        XCTAssertEqual(columns.last?.amount, Decimal(string: "0.125"), "the quarter hour of the data")
        XCTAssertEqual(columns.filter { $0.amount != 0 }.count, 4, "an empty column keeps its place at zero")

        let dollars = ChartData.costBars(costs: account.costs, currency: "USD", interval: day, bucketSize: .minutes15)
        XCTAssertNil(dollars.last?.amount, "a column with a request that had no dollar price has no amount")
        XCTAssertEqual(dollars[dollars.count - 2].amount, Decimal(string: "0.02"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let week = DateInterval(start: day.end.addingTimeInterval(-7 * 86400), end: day.end)
        let days = ChartData.costBars(costs: account.costs, currency: "CNY", interval: week, bucketSize: .day1, calendar: calendar)
        XCTAssertEqual(days.count, 8, "seven days and the part of the day the week starts in, as the token chart lays them out")
        XCTAssertEqual(days.compactMap(\.amount).reduce(0, +), Decimal(string: "2"))
    }
}
