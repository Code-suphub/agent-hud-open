import XCTest
@testable import AgentHUDDesktop

/// Reads the Claude app installed on this Mac, which CI does not have: run with AGENT_HUD_REAL_CLAUDE_APP=1. Nothing
/// read is kept or written anywhere.
@MainActor
final class ClawdRealAppTests: XCTestCase {
    func testTheInstalledClaudeAppHasEveryClipsFrame() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENT_HUD_REAL_CLAUDE_APP"] == "1",
                          "set AGENT_HUD_REAL_CLAUDE_APP=1 to read the installed Claude app")
        let app = try XCTUnwrap(ClawdSheetSource.installed.first { FileManager.default.fileExists(atPath: $0.path) },
                                "no Claude app installed")
        let started = Date()
        let sheet = try XCTUnwrap(ClawdSheetSource.sheet(app: app))
        let seconds = Date().timeIntervalSince(started)
        XCTAssertEqual(Set(sheet.sprites.keys), Set(ClawdClipsTests.realFrameCounts.keys.map(\.rawValue)))
        for (name, count) in ClawdClipsTests.realFrameCounts {
            let sprite = try XCTUnwrap(sheet[name], name.rawValue)
            XCTAssertEqual(sprite.frameCount, count, name.rawValue)
            XCTAssertEqual(sprite.frames.allSatisfy { $0.count == sprite.width * sprite.height }, true, name.rawValue)
        }
        XCTAssertTrue(ClawdClips.standard.fit(sheet))
        let fitting = await ClawdSheetSource().sheet()
        XCTAssertNotNil(fitting)
        print("Decoded \(sheet.sprites.count) sprites of Claude \(sheet.version) in \(Int(seconds * 1000)) ms")

        // Standing is the game's standing pose: the body on its feet, centred on its anchor.
        let standing = try XCTUnwrap(sheet[.walking])
        XCTAssertEqual(standing.anchor.x, 12)
        let baker = ClawdBaker(sheet: sheet)
        let image = try XCTUnwrap(baker.image(ClawdPicture(frame: .standing), side: 20, scale: 2))
        XCTAssertEqual(image.width, 64)
    }
}
