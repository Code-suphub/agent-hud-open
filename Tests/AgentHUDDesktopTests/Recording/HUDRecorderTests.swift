import AppKit
import AVFoundation
import XCTest
@testable import AgentHUDCore
@testable import AgentHUDDesktop

final class HUDRecorderTests: XCTestCase {
    func testARegionIsFourNumbersInPoints() {
        XCTAssertEqual(HUDRecorder.Options.region("10, 20,300,200"), CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertNil(HUDRecorder.Options.region("10,20,300"))
        XCTAssertNil(HUDRecorder.Options.region("10,20,0,200"), "An empty region records nothing")
        XCTAssertNil(HUDRecorder.Options.region("left,top,300,200"))
    }

    func testTheRecordingOptionsAreReadFromTheCommandLine() {
        let options = DesktopLaunchOptions.parse(["app", "--record", "~/take.mov", "--record-seconds", "12.5", "--record-fps", "30",
                                                  "--record-region", "0,0,640,480"])
        XCTAssertEqual(options.recordPath, "~/take.mov")
        XCTAssertEqual(options.recordSeconds, 12.5)
        XCTAssertEqual(options.recordFPS, 30)
        XCTAssertEqual(options.recordRegion, "0,0,640,480")
        XCTAssertFalse(options.demo, "Recording does not need the demo")
    }

    /// Alpha of the pixel at a point given in global screen coordinates.
    private func alpha(of image: CGImage, at point: CGPoint, on screen: NSScreen) throws -> UInt8 {
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        let scale = screen.backingScaleFactor
        let x = Int((point.x - screen.frame.minX) * scale), y = Int((screen.frame.maxY - point.y) * scale)
        // Premultiplied alpha first in a little-endian word: blue, green, red, alpha.
        return data[min(image.height - 1, max(0, y)) * image.bytesPerRow + min(image.width - 1, max(0, x)) * 4 + 3]
    }

    @MainActor
    func testAFrameHoldsTheHUDWhereItIsAndIsClearEverywhereElse() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let key = ScreenIdentity.key(for: screen)
        let domain = "app.agenthud.tests.recorder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults, defaultAgents: DemoData.agents)
        settings.update { $0.screens[key] = ScreenPlacement(mode: .notch) }
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, accessAllowed: { false })
        store.replace(report: DemoUsageProvider.report(agents: settings.agents, historyHours: UsageStore.historyHours, now: Date()))
        let hud = ScreenHUD(key: key, screen: screen, store: store, settings: settings)
        defer { hud.close() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hud-frame-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try HUDRecorder(options: .init(url: url), screen: screen) {
            [.init(window: hud.glow.panel, bounds: hud.island.panel.frame.insetBy(dx: -120, dy: -120)),
             .init(window: hud.island.panel, bounds: nil)]
        }

        var image = try XCTUnwrap(recorder.snapshot())
        XCTAssertEqual(image.width, Int((screen.frame.width * screen.backingScaleFactor / 2).rounded(.up)) * 2)
        let island = hud.geometry.rect, centre = CGPoint(x: island.midX, y: island.midY)
        // The island's layers are drawn a moment after the window is shown, so the frame is taken again until they are.
        let deadline = Date().addingTimeInterval(2)
        while try alpha(of: image, at: centre, on: screen) != 255, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            image = try XCTUnwrap(recorder.snapshot())
        }
        // CI's runner, a virtual display with Reduce Motion on, never draws them: there is no picture to check there.
        try XCTSkipIf(try alpha(of: image, at: centre, on: screen) != 255 && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "this display did not draw the island within 2 s with Reduce Motion on")
        XCTAssertEqual(try alpha(of: image, at: centre, on: screen), 255, "The island is solid")
        XCTAssertEqual(try alpha(of: image, at: CGPoint(x: screen.frame.midX, y: screen.frame.minY + 40), on: screen), 0,
                       "Nothing else on the display is in the picture")
        XCTAssertEqual(try alpha(of: image, at: CGPoint(x: island.minX - 400, y: island.midY), on: screen), 0,
                       "The glow's window spans the display, its picture does not")
    }

    @MainActor
    func testARecordingIsAProRes4444MovieOfTheRegionAtTheDisplaysScale() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let window = NSWindow(contentRect: CGRect(x: screen.frame.minX + 40, y: screen.frame.maxY - 140, width: 120, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 60))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.close() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hud-take-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        var options = HUDRecorder.Options(url: url)
        options.region = CGRect(x: 0, y: 0, width: 300, height: 200)
        options.framesPerSecond = 30
        let recorder = try HUDRecorder(options: options, screen: screen) { [.init(window: window, bounds: nil)] }

        try recorder.start()
        try await Task.sleep(for: .milliseconds(600))
        await withCheckedContinuation { done in recorder.finish { done.resume() } }

        XCTAssertGreaterThan(recorder.frames, 5)
        let video = try await videoFormat(of: url)
        XCTAssertEqual(video.size, CGSize(width: 300 * screen.backingScaleFactor, height: 200 * screen.backingScaleFactor))
        XCTAssertEqual(video.codec, kCMVideoCodecType_AppleProRes4444, "The codec that keeps the alpha channel")
    }
}

/// A movie's picture size and codec. The macOS 15 SDK's tracks are not Sendable, so they are read here, off the main
/// actor the tests run on, and only the two values go back.
private func videoFormat(of url: URL) async throws -> (size: CGSize, codec: FourCharCode) {
    let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
    let video = try XCTUnwrap(track)
    let size = try await video.load(.naturalSize)
    let formats = try await video.load(.formatDescriptions)
    return (size, CMFormatDescriptionGetMediaSubType(try XCTUnwrap(formats.first)))
}
