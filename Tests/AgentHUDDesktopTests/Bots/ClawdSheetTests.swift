import XCTest
@testable import AgentHUDDesktop

final class ClawdSheetTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try ClawdFixture.folder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: The archive

    func testAnArchiveReadsItsTableAndOnlyTheFileAskedFor() throws {
        let url = folder.appendingPathComponent("app.asar")
        try ClawdFixture.archive([
            "package.json": Data("{\"name\":\"claude\"}".utf8),
            "a/b/c.js": Data("let c = 3".utf8),
            "a/b/empty.txt": Data(),
            "a/native.node": Data("binary".utf8),
        ], unpacked: ["a/native.node"]).write(to: url)
        let archive = try XCTUnwrap(AsarArchive(url: url))
        XCTAssertEqual(archive.names(in: ""), ["a", "package.json"])
        XCTAssertEqual(archive.names(in: "a/b"), ["c.js", "empty.txt"])
        XCTAssertEqual(archive.names(in: "a/b/c.js"), [], "a file has nothing in it")
        let entry = try XCTUnwrap(archive.entry(at: "a/b/c.js"))
        XCTAssertEqual(entry.size, 9)
        XCTAssertEqual(archive.contents(of: entry), Data("let c = 3".utf8))
        XCTAssertEqual(archive.contents(of: try XCTUnwrap(archive.entry(at: "package.json"))), Data("{\"name\":\"claude\"}".utf8))
        XCTAssertEqual(archive.contents(of: try XCTUnwrap(archive.entry(at: "a/b/empty.txt"))), Data())
        // A file the app keeps beside its archive has no bytes in it.
        let native = try XCTUnwrap(archive.entry(at: "a/native.node"))
        XCTAssertTrue(native.unpacked)
        XCTAssertNil(archive.contents(of: native))
        XCTAssertNil(archive.entry(at: "a/b"), "a folder is not a file")
        XCTAssertNil(archive.entry(at: "a/b/missing.js"))
    }

    func testWhatIsNotAnArchiveReadsAsNothing() throws {
        let url = folder.appendingPathComponent("not.asar")
        let real = ClawdFixture.archive(["x.js": Data("x".utf8)])
        for bytes in [Data(), Data("hello".utf8), Data(repeating: 0xFF, count: 64), real.prefix(20)] {
            try bytes.write(to: url)
            XCTAssertNil(AsarArchive(url: url), "\(bytes.count) bytes")
        }
        XCTAssertNil(AsarArchive(url: folder.appendingPathComponent("missing.asar")))
        // A table pointing past the end of the archive gives no bytes.
        try real.dropLast().write(to: url)
        let archive = try XCTUnwrap(AsarArchive(url: url))
        XCTAssertNil(archive.contents(of: try XCTUnwrap(archive.entry(at: "x.js"))))
    }

    // MARK: The table

    func testEveryWayTheGameWritesASpriteReads() throws {
        let sprites = ClawdSpriteTable.sprites(in: Array(ClawdFixture.script.utf8))
        XCTAssertEqual(Set(sprites.keys), ["Walking", "Thinking", "Waving"], "a sprite with a bad pixel is left out")

        let walking = try XCTUnwrap(sprites["Walking"])
        XCTAssertEqual(walking.category, "Core")
        XCTAssertEqual(walking.width, 4)
        XCTAssertEqual(walking.height, 3)
        XCTAssertEqual(walking.fps, 12)
        XCTAssertEqual(walking.palette, [ClawdSprite.Color(red: 0xd9, green: 0x77, blue: 0x57, alpha: 255),
                                         ClawdSprite.Color(red: 0x14, green: 0x14, blue: 0x13, alpha: 255)])
        XCTAssertEqual(walking.frames, ClawdFixture.walking)
        XCTAssertEqual(walking.anchor.x, 2, "the middle of its box")
        XCTAssertEqual(walking.anchor.y, 3, "under its box")
        XCTAssertTrue(walking.standMatch)

        // Split by "(": an empty piece is a frame like the one before.
        let thinking = try XCTUnwrap(sprites["Thinking"])
        let clear = ClawdSprite.clear
        XCTAssertEqual(thinking.frames, [[0, 1, 2, 2, clear, 1], [0, 1, 2, 2, clear, 1],
                                         [0, 2, clear, 2, clear, 1], [0, 2, clear, 2, clear, 1]])
        XCTAssertTrue(thinking.standMatch, "!0 is true")

        // A quoted name, keys in any order, an unknown value passed over, an empty box for the whole sprite.
        let waving = try XCTUnwrap(sprites["Waving"])
        XCTAssertEqual(waving.palette, [ClawdSprite.Color(red: 255, green: 255, blue: 255, alpha: 255)])
        XCTAssertEqual(waving.frames, [[0, clear], [0, 0], [0, 0], [0, 0]])
        XCTAssertEqual(waving.anchor.x, 1)
        XCTAssertEqual(waving.anchor.y, 1)
        XCTAssertEqual(waving.fps, 6)
        XCTAssertFalse(waving.standMatch)
    }

    func testAFrameMovesOnlyThePixelsItsDeltaNames() throws {
        // Pixel numbers run past one base-36 digit; a value of "." clears a pixel.
        let frames = try XCTUnwrap(ClawdSpriteTable.frames(base: String(repeating: "0", count: 40), deltas: ["10.,z1", "", "131"],
                                                           pixels: 40, colors: 2))
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[1][36], ClawdSprite.clear, "10 is pixel 36")
        XCTAssertEqual(frames[1][35], 1)
        XCTAssertEqual(frames[2], frames[1])
        XCTAssertEqual(frames[3][39], 1, "13 is pixel 39")
        XCTAssertEqual(frames[3].filter { $0 == 0 }.count, 37)

        XCTAssertNil(ClawdSpriteTable.frames(base: "00", deltas: ["21"], pixels: 2, colors: 2), "no pixel 2")
        XCTAssertNil(ClawdSpriteTable.frames(base: "00", deltas: ["12"], pixels: 2, colors: 2), "no colour 2")
        XCTAssertNil(ClawdSpriteTable.frames(base: "0", deltas: [], pixels: 2, colors: 2), "too few pixels")
        XCTAssertNil(ClawdSpriteTable.frames(base: "0!", deltas: [], pixels: 2, colors: 2))
        XCTAssertEqual(ClawdSpriteTable.frames(base: "00", deltas: ["1"], pixels: 2, colors: 2)?.count, 2,
                       "a change too short to name a pixel changes nothing, as in the game")
    }

    func testColoursReadInEveryLength() {
        XCTAssertEqual(ClawdSpriteTable.color(from: "#d97757"), ClawdSprite.Color(red: 217, green: 119, blue: 87, alpha: 255))
        XCTAssertEqual(ClawdSpriteTable.color(from: "#FA0"), ClawdSprite.Color(red: 255, green: 170, blue: 0, alpha: 255))
        XCTAssertEqual(ClawdSpriteTable.color(from: "#11223380"), ClawdSprite.Color(red: 17, green: 34, blue: 51, alpha: 128))
        XCTAssertNil(ClawdSpriteTable.color(from: "d97757"))
        XCTAssertNil(ClawdSpriteTable.color(from: "#d9775"))
        XCTAssertNil(ClawdSpriteTable.color(from: "#gg0000"))
    }

    func testAScriptWithNoTableHasNoSprites() {
        for script in ["", "const a={b:{c:1}}", "x:{w:", "Walking:{cat:\"Core\",w:4,h:3,palette:[\"#000\"],base:\"0", "::{{"] {
            XCTAssertTrue(ClawdSpriteTable.sprites(in: Array(script.utf8)).isEmpty, script)
        }
    }

    // MARK: The sheet

    func testFramesThatLookTheSameAreOneFrame() throws {
        let sheet = ClawdFixture.sheet()
        XCTAssertEqual(sheet.canonical(ClawdFrame(.walking, 1)), ClawdFrame(.walking, 0), "an empty delta repeats a frame")
        XCTAssertEqual(sheet.canonical(ClawdFrame(.walking, 2)), ClawdFrame(.walking, 2))
        XCTAssertEqual(sheet.canonical(ClawdFrame(.thinking, 3)), ClawdFrame(.thinking, 2))
        XCTAssertEqual(sheet.canonical(ClawdFrame(.waving, 3)), ClawdFrame(.waving, 1))
        XCTAssertTrue(sheet.has(ClawdFrame(.walking, 3)))
        XCTAssertFalse(sheet.has(ClawdFrame(.walking, 4)))
        XCTAssertFalse(sheet.has(ClawdFrame(.laptop, 0)))

        // Frames of two sprites match where their pixels land from the anchor, whatever their sizes.
        let small = ClawdSprite(name: "Walking", category: "", width: 2, height: 1, fps: 12,
                                palette: [ClawdSprite.Color(red: 1, green: 2, blue: 3, alpha: 255)], frames: [[0, 0]],
                                anchor: (1, 1), standMatch: true)
        let big = ClawdSprite(name: "Excited", category: "", width: 4, height: 3, fps: 12,
                              palette: [ClawdSprite.Color(red: 9, green: 9, blue: 9, alpha: 255), ClawdSprite.Color(red: 1, green: 2, blue: 3, alpha: 255)],
                              frames: [[255, 255, 255, 255, 255, 255, 255, 255, 255, 1, 1, 255], [255, 255, 255, 255, 255, 255, 255, 255, 1, 1, 255, 255]],
                              anchor: (2, 3), standMatch: true)
        let both = ClawdSheet(version: "", sprites: ["Walking": small, "Excited": big])
        XCTAssertEqual(both.canonical(ClawdFrame(.excited, 0)), .standing)
        XCTAssertEqual(both.canonical(ClawdFrame(.excited, 1)), ClawdFrame(.excited, 1), "a pixel to the left")
    }

    // MARK: The app

    func testTheGameIsReadOutOfAnInstalledApp() async throws {
        let app = try ClawdFixture.app(in: folder, version: "2.5.0")
        XCTAssertEqual(ClawdSheetSource.version(of: app), "2.5.0 (1)")
        let sheet = try XCTUnwrap(ClawdSheetSource.sheet(app: app))
        XCTAssertEqual(sheet.version, "2.5.0 (1)")
        XCTAssertEqual(Set(sheet.sprites.keys), ["Walking", "Thinking", "Waving"])
        XCTAssertEqual(sheet[.walking]?.frames, ClawdFixture.walking)

        // A made-up table has none of the frames the clips play, so the app's Clawd is not used and nothing fails.
        let source = ClawdSheetSource(apps: [folder.appendingPathComponent("Missing.app"), app])
        let fitting = await source.sheet()
        XCTAssertNil(fitting)
        let none = await ClawdSheetSource(apps: [folder.appendingPathComponent("Missing.app")]).sheet()
        XCTAssertNil(none)
    }

    func testAnAppWithoutTheGameGivesNoSprites() throws {
        let app = try ClawdFixture.app(in: folder, script: "console.log('no game here')")
        XCTAssertNil(ClawdSheetSource.sheet(app: app))
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNil(ClawdSheetSource.version(of: app))
        XCTAssertNil(ClawdSheetSource.sheet(app: app), "an app with no version")
    }

    /// Stills may be published, so the debug code that draws them reads the Claude app only when asked to on this Mac.
    func testDebugStillsReadTheClaudeAppOnlyWhenAskedTo() throws {
        let debug = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Sources/AgentHUDDesktop/Debug").standardized
        let files = try FileManager.default.contentsOfDirectory(at: debug, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for file in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("ClawdSheetSource") else { continue }
            XCTAssertTrue(source.contains("environment[\"AGENT_HUD_REAL_CLAUDE_APP\"] == \"1\""), file.lastPathComponent)
        }
    }
}
