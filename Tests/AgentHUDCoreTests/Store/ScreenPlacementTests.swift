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

    func testSimpleModeSettingsDecodeWithinTheirBoundsAndDefaultWhenAbsent() throws {
        let saved = try JSONDecoder().decode(ScreenPlacement.self, from: Data(
            #"{"mode":"simple","edge":"left","simpleSize":100,"ringWidth":0.2,"showsRings":false}"#.utf8))
        XCTAssertEqual(saved.mode, .simple)
        XCTAssertEqual(saved.edge, .left)
        XCTAssertEqual(saved.simpleSize, 40)
        XCTAssertEqual(saved.ringWidth, 1)
        XCTAssertFalse(saved.showsRings)
        XCTAssertTrue(saved.showsNumbers)
        XCTAssertFalse(saved.simpleBots)
        let lively = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"simple","simpleBots":true}"#.utf8))
        XCTAssertTrue(lively.simpleBots)

        let older = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"logos","logoSize":24}"#.utf8))
        XCTAssertEqual(older.simpleSize, 22)
        XCTAssertEqual(older.ringWidth, 1.5)
        XCTAssertTrue(older.showsRings)
        XCTAssertTrue(older.showsNumbers)
        XCTAssertEqual(try JSONDecoder().decode(ScreenPlacement.self, from: JSONEncoder().encode(saved)), saved)
    }

    func testOnlyTheNotchIsNotDocked() {
        XCTAssertEqual(HUDMode.allCases.filter(\.isDocked), [.logos, .simple])
    }

    // MARK: The look

    /// A placement saved before the HUD had a look reads as Dark and Solid; a name a newer build saved, or a value of the
    /// wrong type, reads as the default and costs no other field; a look is written and read back as it was.
    func testTheLookDecodesFromOlderAndNewerSettings() throws {
        let older = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"simple","simpleSize":30}"#.utf8))
        XCTAssertEqual(older.appearance, .dark)
        XCTAssertEqual(older.material, .solid)
        XCTAssertEqual(older, ScreenPlacement(mode: .simple, simpleSize: 30))

        let newer = try JSONDecoder().decode(ScreenPlacement.self, from: Data(
            #"{"mode":"logos","logoSize":30,"appearance":"sepia","material":"paper"}"#.utf8))
        XCTAssertEqual(newer, ScreenPlacement(mode: .logos, logoSize: 30), "a name this build does not know is the default")
        let mistyped = try JSONDecoder().decode(ScreenPlacement.self, from: Data(
            #"{"edge":"left","appearance":1,"material":true}"#.utf8))
        XCTAssertEqual(mistyped, ScreenPlacement(edge: .left))

        let chosen = ScreenPlacement(mode: .simple, appearance: .system, material: .glass)
        let written = try JSONEncoder().encode(chosen)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(fields["appearance"] as? String, "system")
        XCTAssertEqual(fields["material"] as? String, "glass")
        XCTAssertEqual(try JSONDecoder().decode(ScreenPlacement.self, from: written), chosen)
        for hasNotch in [true, false] {
            XCTAssertEqual(ScreenPlacement.default(hasNotch: hasNotch).appearance, .dark)
            XCTAssertEqual(ScreenPlacement.default(hasNotch: hasNotch).material, .solid)
        }
    }

    /// One screen's look this build cannot read leaves that screen's other fields and every other screen as saved.
    func testAnUnreadableLookCostsNoOtherScreen() throws {
        let json = #"{"screens":{"A":{"mode":"simple","appearance":"neon"},"B":{"mode":"logos","edge":"left","material":"glass"}}}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.screens["A"], ScreenPlacement(mode: .simple))
        XCTAssertEqual(settings.screens["B"], ScreenPlacement(mode: .logos, edge: .left, material: .glass))
    }

    /// Each display's look survives a reload of the settings.
    @MainActor
    func testEachDisplaysLookSurvivesSettingsReload() throws {
        let suite = "AgentHUDTests.ScreenPlacement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let placements = [
            "one": ScreenPlacement(mode: .simple, appearance: .light, material: .glass),
            "two": ScreenPlacement(mode: .notch, appearance: .system),
        ]
        store.update { $0.screens = placements }
        XCTAssertEqual(SettingsStore(defaults: defaults).settings.screens, placements)
    }

    /// The look a HUD draws: its own, but for the notch's on a display that has one, which stays dark and solid; `system`
    /// as macOS is set; and glass solid under Reduce Transparency.
    func testTheLookDrawnFollowsTheNotchMacOSAndReduceTransparency() {
        let chosen = ScreenPlacement(mode: .notch, appearance: .light, material: .glass)
        XCTAssertFalse(chosen.drawsLook(hasNotch: true))
        XCTAssertFalse(chosen.drawsLight(hasNotch: true, systemIsLight: true), "a notch HUD at a notch stays dark")
        XCTAssertFalse(chosen.drawsGlass(hasNotch: true, reducesTransparency: false), "and solid")
        XCTAssertTrue(chosen.drawsLook(hasNotch: false), "the bar that stands in for a notch draws the look")
        XCTAssertTrue(chosen.drawsLight(hasNotch: false, systemIsLight: false))
        XCTAssertTrue(chosen.drawsGlass(hasNotch: false, reducesTransparency: false))
        for mode in [HUDMode.logos, .simple] {
            var dock = chosen
            dock.mode = mode
            XCTAssertTrue(dock.drawsLook(hasNotch: true), "\(mode) on a display with a notch draws its look")
            XCTAssertTrue(dock.drawsLight(hasNotch: true, systemIsLight: false))
            XCTAssertTrue(dock.drawsGlass(hasNotch: true, reducesTransparency: false))
        }

        let system = ScreenPlacement(appearance: .system)
        XCTAssertTrue(system.drawsLight(hasNotch: false, systemIsLight: true))
        XCTAssertFalse(system.drawsLight(hasNotch: false, systemIsLight: false))
        XCTAssertFalse(ScreenPlacement(appearance: .dark).drawsLight(hasNotch: false, systemIsLight: true))
        XCTAssertTrue(ScreenPlacement(appearance: .light).drawsLight(hasNotch: false, systemIsLight: false))

        let glass = ScreenPlacement(material: .glass)
        XCTAssertTrue(glass.drawsGlass(hasNotch: false, reducesTransparency: false))
        XCTAssertFalse(glass.drawsGlass(hasNotch: false, reducesTransparency: true), "Reduce Transparency draws it solid")
        XCTAssertFalse(ScreenPlacement().drawsGlass(hasNotch: false, reducesTransparency: false))
        XCTAssertFalse(ScreenPlacement().drawsLight(hasNotch: false, systemIsLight: true), "dark unless chosen")
    }
}
