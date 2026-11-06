import XCTest
@testable import AgentHUDCore

final class CustomBalanceTests: XCTestCase, @unchecked Sendable {
    func testBrowserCurlPreservesHeadersCookiesAndJSONWithoutRunningShell() throws {
        let request = try BalanceRequest.parse(curl: #"curl 'https://example.com/balance?scope=a&kind=b' -X POST -H 'Content-Type: application/json' -H 'X-Token: placeholder' -b 'session=example' --data-raw '{"filter":"$(ignored)"}' --compressed"#)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Cookie"], "session=example")
        XCTAssertEqual(request.body, #"{"filter":"$(ignored)"}"#)
        XCTAssertEqual(request.url.query, "scope=a&kind=b")
    }

    func testRejectsShellAndLocalFileOptionsAndInsecureTransport() {
        for curl in ["curl https://example.com; touch test", "curl https://example.com -o private", "curl https://example.com --data @private",
                     "curl https://example.com -b private", "curl http://example.com", "curl https://example.com -L", "curl https://example.com -X DELETE",
                     "curl 'https://user:pass@example.com'", "curl https://example.com -H 'Host: other.example'", "curl 'https://example.com"] {
            XCTAssertThrowsError(try BalanceRequest.parse(curl: curl), curl)
        }
    }

    func testContinuedLinesAndQuotedJSONEscapes() throws {
        let request = try BalanceRequest.parse(curl: "curl 'https://example.com' \\\n -H 'X-Token: example' \\\n --data-raw \"{\\\"path\\\":\\\"a\\\\b\\\"}\"")
        XCTAssertEqual(request.body, #"{"path":"a\b"}"#)
        XCTAssertEqual(request.headers["X-Token"], "example")
    }

    func testFieldsKeepExactDecimalsAndJSONPointerKeysAndExcludeBooleans() throws {
        let fields = try BalanceFields.parse(Data(#"{"data":{"left":"123.4567890123456789","total":600,"ok":true,"a/b~c":[7],"bad":"1,000"}}"#.utf8))
        XCTAssertEqual(fields.first { $0.path == "/data/left" }?.value, Decimal(string: "123.4567890123456789"))
        XCTAssertEqual(fields.first { $0.path == "/data/a~1b~0c/0" }?.value, 7)
        XCTAssertFalse(fields.contains { $0.path == "/data/ok" || $0.path == "/data/bad" })
    }

    func testUsedAndTotalCanDeriveRemainingAndApplyDivisor() throws {
        let fields = try BalanceFields.parse(Data(#"{"used":"403.54","total":600}"#.utf8))
        let profile = CustomBalanceProfile(name: "Example", currency: "CNY", balancePath: "/used", totalPath: "/total", valueKind: .used)
        let amounts = try profile.amounts(in: fields)
        XCTAssertEqual(amounts.balance, Decimal(string: "196.46"))
        XCTAssertEqual(amounts.total, 600)
        let scaled = CustomBalanceProfile(name: "Example", currency: "CNY", balancePath: "/used", divisor: 100)
        XCTAssertEqual(try scaled.amounts(in: fields).balance, Decimal(string: "4.0354"))
    }

    func testInvalidOrMissingMappedFieldsNeverBecomeZero() throws {
        let fields = try BalanceFields.parse(Data(#"{"left":12,"limit":-1}"#.utf8))
        let missing = CustomBalanceProfile(name: "Example", currency: "USD", balancePath: "/missing")
        XCTAssertThrowsError(try missing.amounts(in: fields))
        let badLimit = CustomBalanceProfile(name: "Example", currency: "USD", balancePath: "/left", totalPath: "/limit")
        XCTAssertThrowsError(try badLimit.amounts(in: fields))
        let usedWithoutLimit = CustomBalanceProfile(name: "Example", currency: "USD", balancePath: "/left", valueKind: .used)
        XCTAssertThrowsError(try usedWithoutLimit.amounts(in: fields))
        let zeroDivisor = CustomBalanceProfile(name: "Example", currency: "USD", balancePath: "/left", divisor: 0)
        XCTAssertThrowsError(try zeroDivisor.amounts(in: fields))
    }

    func testBalanceOnlySourceAndOldSettingsDecode() throws {
        let fields = try BalanceFields.parse(Data(#"{"balance":"0"}"#.utf8))
        let profile = CustomBalanceProfile(name: "Example", currency: "USD", balancePath: "/balance")
        let amounts = try profile.amounts(in: fields)
        XCTAssertEqual(amounts.balance, 0)
        XCTAssertNil(amounts.total)
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.customBalances.isEmpty)
        let old = try JSONDecoder().decode(AccountBalance.self, from: Data(#"{"currency":"USD","total":10,"granted":0,"toppedUp":10}"#.utf8))
        XCTAssertNil(old.limit)
    }

    func testProviderKeepsLastGoodBalanceOnFailureAndDoesNotLeakRequest() async throws {
        let profile = CustomBalanceProfile(id: "sample", name: "Example", currency: "USD", balancePath: "/left", totalPath: "/limit")
        let reader = FixtureReader()
        let provider = CustomBalanceUsageProvider(profiles: { [profile] }, read: { _ in try await reader.read() })
        await provider.refreshAccountUsage(historyHours: 1)
        let first = try await provider.fetchUsage(agents: [], historyHours: 1)
        XCTAssertEqual(first.billing.first?.balances.first?.total, 12)
        XCTAssertEqual(first.billing.first?.balances.first?.limit, 20)
        await reader.fail()
        await provider.refreshAccountUsage(historyHours: 1)
        let failed = try await provider.fetchUsage(agents: [], historyHours: 1)
        XCTAssertEqual(failed.billing.first?.balances.first?.total, 12)
        XCTAssertEqual(failed.billing.first?.updatedAt, first.billing.first?.updatedAt)
        XCTAssertNotNil(failed.billing.first?.readingIssue)
        let json = String(decoding: try JSONEncoder().encode(failed), as: UTF8.self)
        XCTAssertFalse(json.contains("sensitive.example"))
    }

    func testDisabledProfilesDoNotQueryOrAppear() async throws {
        let profile = CustomBalanceProfile(name: "Example", currency: "USD", balancePath: "/left", enabled: false)
        let reader = FixtureReader()
        let provider = CustomBalanceUsageProvider(profiles: { [profile] }, read: { _ in try await reader.read() })
        await provider.refreshAccountUsage(historyHours: 1)
        let report = try await provider.fetchUsage(agents: [], historyHours: 1)
        XCTAssertTrue(report.billing.isEmpty)
        let calls = await reader.calls
        XCTAssertEqual(calls, 0)
    }

    func testHTTPClientReadsJSONAndSanitizesAuthenticationFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BalanceFixtureProtocol.self]
        let request = BalanceRequest(url: URL(string: "https://example.com/success")!, headers: ["X-Token": "example"])
        let fields = try await BalanceRequestClient.fetch(request, configuration: config)
        XCTAssertEqual(fields.first { $0.path == "/balance" }?.value, 12)
        let denied = BalanceRequest(url: URL(string: "https://example.com/denied?secret=do-not-log")!)
        do {
            _ = try await BalanceRequestClient.fetch(denied, configuration: config)
            XCTFail("Expected an authentication failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
            XCTAssertFalse(error.localizedDescription.contains("private-response"))
        }
    }

    @MainActor
    func testChangedMappingCannotShowRetainedBalanceFromFormerUnits() async throws {
        var profile = CustomBalanceProfile(id: "sample", name: "Example", currency: "USD", balancePath: "/left")
        let oldPool = CustomBalanceUsageProvider.pool(profile)
        profile.divisor = 100
        let row = AgentDescriptor(id: "custom-balance:sample", vendor: "Example", model: "Balance", source: "", enabled: true,
                                  billingPool: CustomBalanceUsageProvider.pool(profile))
        let now = Date()
        let old = APIBilling(vendor: "Example", balances: [AccountBalance(currency: "USD", total: 1200, granted: 0, toppedUp: 0)],
                             isAvailable: true, updatedAt: now, notice: nil, billingPool: oldPool)
        var settings = Settings()
        settings.customBalances = [profile]
        let report = UsageReport(generatedAt: now, snapshots: [], sessions: [], billing: [old])
        let view = ReportView(report: report, agents: [row], settings: settings, now: now)
        XCTAssertTrue(view.billing.isEmpty)
    }
}

private actor FixtureReader {
    var calls = 0
    var failed = false
    func fail() { failed = true }
    func read() throws -> [BalanceField] {
        calls += 1
        if failed { throw URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://sensitive.example?token=private"]) }
        return try BalanceFields.parse(Data(#"{"left":12,"limit":20}"#.utf8))
    }
}

private final class BalanceFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let denied = request.url!.path == "/denied"
        let response = HTTPURLResponse(url: request.url!, statusCode: denied ? 401 : 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((denied ? "private-response" : #"{"balance":12}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
