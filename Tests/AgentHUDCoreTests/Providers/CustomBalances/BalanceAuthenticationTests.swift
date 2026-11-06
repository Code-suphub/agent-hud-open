import XCTest
@testable import AgentHUDCore

final class BalanceAuthenticationTests: XCTestCase, @unchecked Sendable {
    func testSelectionDropsBrowserMetadataAndKeepsExplicitCredentialChoices() throws {
        let original = try BalanceRequest.parse(curl: #"curl 'https://example.com/balance' -H 'User-Agent: Browser' -H 'Accept-Encoding: gzip, br' -H 'Sec-Fetch-Site: same-origin' -H 'Origin: https://example.com' -H 'X-Authorization-Token: old-token' -H 'Accept: application/json' -b 'session=one; analytics=two'"#)
        var selection = BalanceRequestSelection(original)
        for index in selection.parts.indices where selection.parts[index].name == "analytics" { selection.parts[index].keep = false }
        let request = selection.request()
        XCTAssertNil(request.headers["User-Agent"])
        XCTAssertNil(request.headers["Accept-Encoding"])
        XCTAssertNil(request.headers["Sec-Fetch-Site"])
        XCTAssertNil(request.headers["Origin"])
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.headers["Cookie"], "session=one")
        XCTAssertEqual(Set(request.credentialHeaderNames), ["Cookie", "X-Authorization-Token"])
        try request.validate()
    }

    func testCSRFOriginAndCustomAuthenticationCanBeExplicitlyKept() throws {
        let original = try BalanceRequest.parse(curl: #"curl https://example.com -H 'Origin: https://example.com' -H 'X-Business: opaque'"#)
        var selection = BalanceRequestSelection(original)
        for index in selection.parts.indices {
            if selection.parts[index].name == "Origin" { selection.parts[index].keep = true }
            if selection.parts[index].name == "X-Business" { selection.parts[index].isAuthentication = true }
        }
        let saved = selection.request()
        XCTAssertEqual(saved.headers["Origin"], "https://example.com")
        XCTAssertEqual(saved.credentialHeaderNames, ["X-Business"])
        let edited = BalanceRequestSelection(saved, preserveSavedSelection: true)
        XCTAssertTrue(edited.parts.first { $0.name == "Origin" }?.keep == true)
        XCTAssertTrue(edited.parts.first { $0.name == "X-Business" }?.isAuthentication == true)
    }

    func testManagedHeadersCanBeRemovedBeforeValidation() throws {
        let original = try BalanceRequest.parse(curl: #"curl https://example.com -H 'Host: example.com' -H 'Connection: keep-alive'"#, forSelection: true)
        let selected = BalanceRequestSelection(original).request()
        XCTAssertTrue(selected.headers.isEmpty)
        try selected.validate()
    }

    func testRenewalPreservesEndpointBodyAndOnlySelectedCookieNames() throws {
        var request = BalanceRequest(url: URL(string: "https://example.com/balance?scope=one")!, method: "POST",
            headers: ["Cookie": "session=old; csrf=unchanged", "Authorization": "Bearer old", "X-Routing": "zone-a"], body: "{}")
        request.authenticationHeaders = ["cookie", "authorization"]
        let updated = try request.replacingCredentials(["Cookie": "session=new; analytics=not-selected", "Authorization": "new-token", "X-Routing": "ignored"])
        XCTAssertEqual(updated.headers["Cookie"], "session=new; csrf=unchanged")
        XCTAssertEqual(updated.headers["Authorization"], "Bearer new-token")
        XCTAssertEqual(updated.headers["X-Routing"], "zone-a")
        XCTAssertEqual(updated.url, request.url)
        XCTAssertEqual(updated.body, request.body)
        XCTAssertEqual(updated.method, request.method)
    }

    func testRenewalRejectsMissingSelectedCookiesOrNewlines() throws {
        let request = BalanceRequest(url: URL(string: "https://example.com")!, headers: ["Cookie": "session=old", "X-Token": "old"])
        XCTAssertThrowsError(try request.replacingCredentials(["Cookie": "analytics=one"]))
        XCTAssertThrowsError(try request.replacingCredentials(["X-Token": "new\r\nInjected: value"]))
        XCTAssertThrowsError(try BalanceRequest.parse(curl: "curl https://example.com -H 'X-Token: old\r\nInjected: value'"))
        XCTAssertThrowsError(try BalanceRequest.parse(curl: "curl https://example.com -b 'session=old\r\nInjected: value'"))
        XCTAssertThrowsError(try request.replacingCredentials([:]))
    }

    func testOlderSavedRequestsInferCredentialNamesAndSettingsRemainDecodable() throws {
        let request = try JSONDecoder().decode(BalanceRequest.self, from: Data(#"{"url":"https://example.com","method":"GET","headers":{"X-Token":"old","Accept":"application/json"}}"#.utf8))
        XCTAssertEqual(request.credentialHeaderNames, ["X-Token"])
        let profile = try JSONDecoder().decode(CustomBalanceProfile.self, from: Data(#"{"id":"sample","name":"Sample","currency":"USD","balancePath":"/left","divisor":1,"enabled":true,"valueKind":"remaining"}"#.utf8))
        XCTAssertNil(profile.credentialRevision)
    }

    func testReminderIsOncePerAuthenticationEpisodeAndRemainsQuietAfterLater() {
        var reminders = BalanceAuthenticationReminders()
        reminders.update(required: ["a", "b"])
        XCTAssertEqual(reminders.waiting, ["a", "b"])
        reminders.acknowledge("a")
        reminders.update(required: ["a", "b"])
        XCTAssertEqual(reminders.waiting, ["b"])
        reminders.update(required: ["b"])
        reminders.update(required: ["a", "b"])
        XCTAssertEqual(reminders.waiting, ["a", "b"])
        reminders.update(required: [])
        XCTAssertTrue(reminders.waiting.isEmpty)
    }

    func testApplicationAuthenticationStatusRequiresExplicitKnownCode() {
        for body in [#"{"code":401,"message":"private"}"#, #"{"error":{"code":"403"}}"#] {
            XCTAssertNotNil(BalanceRequestFailure.applicationAuthenticationStatus(Data(body.utf8)))
        }
        for body in [#"{"balance":403}"#, #"{"code":500}"#, #"{"message":"timeout"}"#] {
            XCTAssertNil(BalanceRequestFailure.applicationAuthenticationStatus(Data(body.utf8)))
        }
    }

    func testHTTP200ApplicationAuthenticationFailureIsTypedAndSanitized() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ApplicationAuthProtocol.self]
        do {
            _ = try await BalanceRequestClient.fetch(BalanceRequest(url: URL(string: "https://example.com")!), configuration: config)
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertTrue(error is BalanceRequestFailure)
            XCTAssertFalse(error.localizedDescription.contains("private"))
        }
    }

    func testFailedAuthenticationPausesPollingUntilCredentialsChange() async throws {
        let fixture = AuthProviderFixture()
        let provider = CustomBalanceUsageProvider(profiles: { await fixture.profiles() }, read: { _ in try await fixture.read() })
        await provider.refreshAccountUsage(historyHours: 1)
        await provider.refreshAccountUsage(historyHours: 1)
        let calls = await fixture.calls
        XCTAssertEqual(calls, 1)
        let failed = try await provider.fetchUsage(agents: [], historyHours: 1)
        XCTAssertTrue(failed.billing.first?.requiresAuthentication == true)
        await fixture.renew()
        await provider.refreshAccountUsage(historyHours: 1)
        let recovered = try await provider.fetchUsage(agents: [], historyHours: 1)
        XCTAssertFalse(recovered.billing.first?.requiresAuthentication == true)
        XCTAssertEqual(recovered.billing.first?.balances.first?.total, 12)
    }

    func testMergeAndRetentionPreserveTypedAuthenticationFailure() {
        let now = Date()
        let good = APIBilling(vendor: "Example", balances: [AccountBalance(currency: "USD", total: 12, granted: 0, toppedUp: 0)],
                              isAvailable: true, updatedAt: now, notice: nil)
        let denied = APIBilling(vendor: "Example", balances: [], isAvailable: nil, updatedAt: nil, notice: "expired",
                                readingIssue: .readFailed("expired"), requiresAuthentication: true)
        let previous = UsageReport(generatedAt: now, snapshots: [], sessions: [], billing: [good])
        let current = UsageReport(generatedAt: now, snapshots: [], sessions: [], billing: CombinedUsageProvider.mergeBilling([denied]))
        let retained = current.retainingReadings(from: previous)
        XCTAssertEqual(retained.billing.first?.balances.first?.total, 12)
        XCTAssertTrue(retained.billing.first?.requiresAuthentication == true)
    }
}

private actor AuthProviderFixture {
    var calls = 0
    var revision: Int?
    func profiles() -> [CustomBalanceProfile] {
        var profile = CustomBalanceProfile(id: "sample", name: "Sample", currency: "USD", balancePath: "/left")
        profile.credentialRevision = revision
        return [profile]
    }
    func renew() { revision = 1 }
    func read() throws -> [BalanceField] {
        calls += 1
        if revision == nil { throw BalanceRequestFailure.authentication(status: 401) }
        return try BalanceFields.parse(Data(#"{"left":12}"#.utf8))
    }
}

private final class ApplicationAuthProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":403,"message":"private"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
