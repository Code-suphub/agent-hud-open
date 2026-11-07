import XCTest
@testable import AgentHUDCore

final class LocalBalanceSettingsTests: XCTestCase, @unchecked Sendable {
    func testNonCurrencyBalancesNeverExposeRawPrecisionOnDailySurfaces() throws {
        L10n.setLanguage(.en)
        defer { L10n.setLanguage(.system) }
        let value = try XCTUnwrap(Decimal(string: "123.456789"))
        XCTAssertEqual(MoneyFormat.amount(value, currency: "CREDITS"), "123.46 CREDITS")
        XCTAssertEqual(MoneyFormat.short(value, currency: "CREDITS"), "123.46 CREDITS")
        XCTAssertEqual(CustomBalanceProfile.format(value, unit: "CREDITS"), "123.46 CREDITS")
        XCTAssertEqual(MoneyFormat.amount(0, currency: "CREDITS"), "0.00 CREDITS")
        XCTAssertEqual(MoneyFormat.amount(value, currency: "USD"), "$123.46")
        XCTAssertTrue(CustomBalanceProfile.format(value, unit: "CNY").hasSuffix("123.46"))
        XCTAssertEqual(CustomBalanceProfile.format(value, unit: "POINTS"), "123.46 POINTS")
    }

    func testWebsiteIsOptionalAndOnlyOpensAnHTTPSDestinationWithoutUserInfo() throws {
        var profile = CustomBalanceProfile(id: "sample", name: "Sample", currency: "CNY", balancePath: "/left")
        let pool = CustomBalanceUsageProvider.pool(profile)
        let old = try JSONDecoder().decode(CustomBalanceProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertNil(old.websiteURL)
        profile.website = "https://example.com/sign-in"
        let restored = try JSONDecoder().decode(CustomBalanceProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored.websiteURL?.absoluteString, "https://example.com/sign-in")
        XCTAssertEqual(CustomBalanceUsageProvider.pool(restored), pool)
        for address in ["file:///tmp/demo", "http://example.com", "javascript:alert(1)", "https://user:secret@example.com"] {
            profile.website = address
            XCTAssertNil(profile.websiteURL)
        }
    }

    func testLocalStoreRoundTripsAtomicReplacementAndPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BalanceRequestFiles(directory: root.appendingPathComponent("requests"))
        var request = BalanceRequest(url: URL(string: "https://example.com/balance")!, headers: ["X-Token": "first-example"])
        try store.save(request, id: "sample")
        XCTAssertEqual(try store.load(id: "sample"), request)
        request.headers["X-Token"] = "second-example"
        try store.save(request, id: "sample")
        XCTAssertEqual(try store.load(id: "sample"), request)
        let files = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as? Int, 0o600)
        try store.remove(id: "sample")
        XCTAssertThrowsError(try store.load(id: "sample"))
    }

    func testLocalStoreRejectsSymlinkDirectoriesAndKeepsFailedUpdateIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let request = BalanceRequest(url: URL(string: "https://example.com")!, headers: ["X-Token": "example"])
        XCTAssertThrowsError(try BalanceRequestFiles(directory: link).save(request, id: "sample"))
        let store = BalanceRequestFiles(directory: real)
        try store.save(request, id: "../../outside")
        var invalid = request
        invalid.headers["X-Token"] = "bad\r\nheader"
        XCTAssertThrowsError(try store.save(invalid, id: "../../outside"))
        XCTAssertEqual(try store.load(id: "../../outside"), request)
        let files = try FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].lastPathComponent.contains(".."))
    }

    func testAvatarIsOptionalForOldProfilesAndRoundTripsWithoutChangingQuotaIdentity() throws {
        var profile = CustomBalanceProfile(id: "sample", name: "Sample", currency: "CREDITS", balancePath: "/left")
        let pool = CustomBalanceUsageProvider.pool(profile)
        let old = try JSONDecoder().decode(CustomBalanceProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertNil(old.avatar)
        profile.avatar = try CustomBalanceAvatar(emoji: "🤖", animated: true)
        XCTAssertEqual(try JSONDecoder().decode(CustomBalanceProfile.self, from: JSONEncoder().encode(profile)), profile)
        XCTAssertEqual(CustomBalanceUsageProvider.pool(profile), pool)
        XCTAssertThrowsError(try CustomBalanceAvatar(emoji: ""))
        XCTAssertThrowsError(try CustomBalanceAvatar(imagePNG: Data("invalid".utf8)))
    }
}
