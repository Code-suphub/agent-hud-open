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
        XCTAssertEqual(saved.simpleSize, 50)
        XCTAssertEqual(saved.ringWidth, 1)
        XCTAssertFalse(saved.showsRings)
        XCTAssertTrue(saved.showsNumbers)
        // The Simple panel once had a bot switch of its own; a placement saved with it still reads, without it.
        let lively = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"simple","simpleBots":true}"#.utf8))
        XCTAssertEqual(lively, ScreenPlacement(mode: .simple))

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

    /// The look a HUD draws is its own in every mode, the notch's at a hardware notch too, which keeps only the notch's
    /// row dark (`HUDLook.inNotchRow`, in the app): `system` as macOS is set, and glass solid under Reduce Transparency.
    func testTheLookDrawnFollowsMacOSAndReduceTransparencyInEveryMode() {
        for mode in HUDMode.allCases {
            let chosen = ScreenPlacement(mode: mode, appearance: .light, material: .glass)
            XCTAssertTrue(chosen.drawsLight(systemIsLight: false), "\(mode) draws its light look")
            XCTAssertTrue(chosen.drawsGlass(reducesTransparency: false), "\(mode) draws its glass")
            XCTAssertFalse(chosen.drawsGlass(reducesTransparency: true), "\(mode) under Reduce Transparency is solid")
        }

        let system = ScreenPlacement(appearance: .system)
        XCTAssertTrue(system.drawsLight(systemIsLight: true))
        XCTAssertFalse(system.drawsLight(systemIsLight: false))
        XCTAssertFalse(ScreenPlacement(appearance: .dark).drawsLight(systemIsLight: true))
        XCTAssertTrue(ScreenPlacement(appearance: .light).drawsLight(systemIsLight: false))

        let glass = ScreenPlacement(material: .glass)
        XCTAssertTrue(glass.drawsGlass(reducesTransparency: false))
        XCTAssertFalse(glass.drawsGlass(reducesTransparency: true), "Reduce Transparency draws it solid")
        XCTAssertFalse(ScreenPlacement().drawsGlass(reducesTransparency: false))
        XCTAssertFalse(ScreenPlacement().drawsLight(systemIsLight: true), "dark unless chosen")
    }

    // MARK: The glass's transparency

    /// Glass lets half the desktop through unless chosen otherwise, on every display's starting point too, and a
    /// transparency is held to 0 through 0.9, the top short of bare glass, whether it is given or read back.
    func testGlassTransparencyStartsAtHalfAndIsHeldToItsRange() throws {
        XCTAssertEqual(ScreenPlacement.standardGlassTransparency, 0.5)
        XCTAssertEqual(ScreenPlacement.glassTransparencyRange, 0...0.9)
        XCTAssertEqual(ScreenPlacement().glassTransparency, ScreenPlacement.standardGlassTransparency)
        for hasNotch in [true, false] {
            XCTAssertEqual(ScreenPlacement.default(hasNotch: hasNotch).glassTransparency, 0.5)
        }
        for (given, kept) in [(0.0, 0.0), (0.3, 0.3), (0.9, 0.9), (1.0, 0.9), (-0.2, 0.0), (Double.nan, 0.0)] {
            XCTAssertEqual(ScreenPlacement(material: .glass, glassTransparency: given).glassTransparency, kept, "\(given)")
        }
        for (saved, kept) in [(0.25, 0.25), (2, 0.9), (-1, 0)] {
            let placement = try JSONDecoder().decode(ScreenPlacement.self, from: Data(
                #"{"material":"glass","glassTransparency":\#(saved)}"#.utf8))
            XCTAssertEqual(placement.glassTransparency, kept, "\(saved)")
            XCTAssertEqual(placement.material, .glass)
        }
    }

    /// A placement saved before glass had a transparency reads as the standard one and costs no other field; a
    /// transparency is written under its own key and read back as it was, kept while the material is solid.
    func testGlassTransparencyDecodesFromOlderSettingsAndRoundTrips() throws {
        let older = try JSONDecoder().decode(ScreenPlacement.self, from: Data(
            #"{"mode":"simple","appearance":"light","material":"glass"}"#.utf8))
        XCTAssertEqual(older.glassTransparency, ScreenPlacement.standardGlassTransparency)
        XCTAssertEqual(older, ScreenPlacement(mode: .simple, appearance: .light, material: .glass))

        let chosen = ScreenPlacement(mode: .logos, material: .glass, glassTransparency: 0.2)
        let written = try JSONEncoder().encode(chosen)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(fields["glassTransparency"] as? Double, 0.2)
        XCTAssertEqual(try JSONDecoder().decode(ScreenPlacement.self, from: written), chosen)

        let solid = ScreenPlacement(material: .solid, glassTransparency: 0.7)
        XCTAssertEqual(try JSONDecoder().decode(ScreenPlacement.self, from: JSONEncoder().encode(solid)).glassTransparency, 0.7,
                       "kept for when glass is chosen again")
        XCTAssertNotEqual(solid, ScreenPlacement(), "a placement is its fields, the transparency among them")
    }
}
