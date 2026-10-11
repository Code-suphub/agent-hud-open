import XCTest
@testable import AgentHUDCore

final class ScreenPlacementTests: XCTestCase {
    func testLogoSizeAndEdgeDistanceBoundsAreIndependentOfSpacing() throws {
        for (size, distance, expectedSize, expectedDistance) in [
            (30.0, 0.0, 30.0, 0.0), (36, 20, 36, 20), (100, 100, 36, 20), (-1, -1, 12, 0)
        ] {
            let data = try JSONEncoder().encode(["logoSize": size, "logoEdgeDistance": distance, "gapScale": 0.35])
            let placement = try JSONDecoder().decode(ScreenPlacement.self, from: data)
            XCTAssertEqual(placement.logoSize, expectedSize)
            XCTAssertEqual(placement.logoEdgeDistance, expectedDistance)
            XCTAssertEqual(placement.gapScale, 0.35)
        }
    }

    func testSavedPlacementWithoutEdgeDistanceUsesTheDefault() throws {
        let placement = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"logoSize":24,"gapScale":0.2}"#.utf8))
        XCTAssertEqual(placement.logoSize, 24)
        XCTAssertEqual(placement.logoEdgeDistance, 2)
        XCTAssertEqual(placement.gapScale, 0.2)
    }

    @MainActor
    func testEachDisplaysLogoSizeAndEdgeDistanceSurviveSettingsReload() throws {
        let suite = "AgentHUDTests.ScreenPlacement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let placements = [
            "one": ScreenPlacement(edge: .top, logoSize: 30, logoEdgeDistance: 0, gapScale: 0.3),
            "two": ScreenPlacement(edge: .right, logoSize: 36, logoEdgeDistance: 20, gapScale: 0.6),
        ]
        store.update { $0.screens = placements }
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.screens, placements)
    }
}
