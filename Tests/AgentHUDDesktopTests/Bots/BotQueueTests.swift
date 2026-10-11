import AppKit
import AgentHUDCore
import QuartzCore
import SwiftUI
import XCTest
@testable import AgentHUDDesktop

@MainActor
final class BotQueueTests: XCTestCase {
    private func queue(_ rows: [(String, Bool)], bots: Bool = true) -> LogoQueueConfig {
        var settings = Settings()
        settings.botLogos = bots
        return LogoQueueConfig(items: rows.map { LogoQueueItem(vendor: $0.0, isWorking: $0.1) },
                               placement: ScreenPlacement(mode: .logos), settings: settings)
    }

    /// A queue in a window that is never shown, so its bots have a screen position to look from.
    private func hosted() -> (LogoQueueLayerView, NSWindow) {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 48)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        // A window made in code releases itself when closed unless told otherwise, and ARC then releases it again.
        window.isReleasedWhenClosed = false
        let view = LogoQueueLayerView(frame: frame)
        window.contentView?.addSubview(view)
        return (view, window)
    }

    private func run(_ view: LogoQueueLayerView, from start: TimeInterval, frames: Int) -> (now: TimeInterval, moving: Bool) {
        var now = start, moving = false
        for _ in 0..<frames {
            now += 1.0 / 30
            moving = view.stepBots(to: now)
        }
        return (now, moving)
    }

    func testAWorkingMarkGivesWayToItsBotAndComesBackWhenWorkEnds() throws {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", true), ("Cursor", false)]), light: false, scale: 2, animates: true)
        var clock = run(view, from: CACurrentMediaTime(), frames: 30)
        XCTAssertTrue(clock.moving)
        let claude = try XCTUnwrap(view.actors[0]), cursor = try XCTUnwrap(view.actors[1])
        XCTAssertEqual(view.marks[0].opacity, 0)
        XCTAssertFalse(claude.layer.isHidden)
        XCTAssertNotNil(claude.layer.contents)
        XCTAssertEqual(view.marks[1].opacity, 1)
        XCTAssertTrue(cursor.layer.isHidden)
        // The bot sits on its mark, with room round it for what overflows.
        XCTAssertEqual(claude.layer.position.x, view.marks[0].frame.midX, accuracy: 0.01)
        XCTAssertEqual(claude.layer.position.y, view.marks[0].frame.midY, accuracy: 0.01)
        XCTAssertGreaterThan(claude.layer.bounds.width, view.marks[0].bounds.width * 1.5)

        view.apply(config: queue([("Claude", false), ("Cursor", false)]), light: false, scale: 2, animates: true)
        clock = run(view, from: clock.now, frames: 45)
        XCTAssertTrue(clock.moving, "Idle logos keep the clock for their occasional bot appearance")
        XCTAssertEqual(view.marks[0].opacity, 1)
        XCTAssertTrue(claude.layer.isHidden)
    }

    func testWithBotsOffAWorkingMarkStaysStill() {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", true)], bots: false), light: false, scale: 2, animates: true)
        XCTAssertNil(view.actors[0])
        XCTAssertNil(view.marks[0].animationKeys())
        XCTAssertFalse(view.stepBots(to: CACurrentMediaTime()))
    }

    func testAWorkingQueueKeepsItsBotThroughoutTheTurn() throws {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", true)]), light: false, scale: 2, animates: true)
        let actor = try XCTUnwrap(view.actors[0])
        let start = CACurrentMediaTime()
        for frame in 1...1500 {
            XCTAssertTrue(view.stepBots(to: start + Double(frame) / 30))
            XCTAssertEqual(actor.phase, .working)
            XCTAssertFalse(actor.layer.isHidden)
            XCTAssertEqual(view.marks[0].opacity, 0)
            XCTAssertEqual(actor.layer.affineTransform().tx, 0, accuracy: 0.0001)
            XCTAssertEqual(actor.layer.affineTransform().ty, 0, accuracy: 0.0001)
        }
        XCTAssertNil(view.marks[0].animationKeys())
    }

    func testAnIdleQueueOccasionallyShowsItsBotThenReturnsToTheLogo() throws {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", false)]), light: false, scale: 2, animates: true)
        let actor = try XCTUnwrap(view.actors[0])
        let start = CACurrentMediaTime()
        var sawBot = false, returnedToLogo = false, returnedToBot = false
        for frame in 1...2700 {
            XCTAssertTrue(view.stepBots(to: start + Double(frame) / 30),
                          "The idle interval keeps the clock for the next bot appearance")
            XCTAssertEqual(actor.phase, .idle)
            if actor.layer.isHidden {
                XCTAssertEqual(view.marks[0].opacity, 1)
                if sawBot { returnedToLogo = true }
            } else {
                XCTAssertEqual(view.marks[0].opacity, 0)
                sawBot = true
                if returnedToLogo { returnedToBot = true }
            }
            if frame < 600 { XCTAssertTrue(actor.layer.isHidden, "Idle starts with a longer logo interval") }
            XCTAssertEqual(actor.layer.affineTransform().tx, 0, accuracy: 0.0001)
            XCTAssertEqual(actor.layer.affineTransform().ty, 0, accuracy: 0.0001)
        }
        XCTAssertTrue(sawBot)
        XCTAssertTrue(returnedToLogo)
        XCTAssertTrue(returnedToBot)
    }

    func testReduceMotionLeavesEveryMarkItsLogo() {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", true)]), light: false, scale: 2, animates: false)
        let clock = run(view, from: CACurrentMediaTime(), frames: 2700)
        XCTAssertFalse(clock.moving)
        XCTAssertEqual(view.marks[0].opacity, 1)
        XCTAssertNil(view.marks[0].animation(forKey: "bob"))
    }

    /// Not a benchmark: a guard against a frame becoming expensive enough to show up in the HUD's own cost.
    func testDrawingAQueueBotIsCheap() throws {
        let form = try XCTUnwrap(BotForm.form(for: "Claude"))
        var motion = BotMotion(seed: 2)
        motion.spin = form.spec.spin
        motion.set(.working, at: 0)
        var now: TimeInterval = 0
        while now < 1 { motion.step(to: now); now += 1.0 / 30 }
        let frames = 200, start = CACurrentMediaTime()
        var drawing: TimeInterval = 0
        for _ in 0..<frames {
            let began = CACurrentMediaTime()
            XCTAssertNotNil(BotRenderer.image(form, motion: motion, side: 40))
            drawing += CACurrentMediaTime() - began
            XCTAssertNotNil(BotRenderer.image(form, motion: motion, side: 40, outline: 1))
        }
        let each = (CACurrentMediaTime() - start) / Double(frames)
        let plain = drawing / Double(frames), outlined = each - plain
        print(String(format: "bot frame at 20 pt @2x: %.3f ms plain, %.3f ms with its hairline", plain * 1000, outlined * 1000))
        XCTAssertLessThan(outlined, 0.004)
    }
}

@MainActor
final class BotFormTimingTests: XCTestCase {
    /// Reading a mark is paid once per vendor, on the main thread, the first time its bot is needed.
    func testReadingAMarkIsQuick() throws {
        var slowest: (String, TimeInterval) = ("", 0), total: TimeInterval = 0
        for vendor in AgentArtwork.allVendors {
            let began = CACurrentMediaTime()
            XCTAssertNotNil(BotForm.read(vendor))
            let took = CACurrentMediaTime() - began
            total += took
            if took > slowest.1 { slowest = (vendor, took) }
        }
        print(String(format: "reading a mark: %.1f ms on average, %.1f ms at worst (%@)",
                     total / Double(AgentArtwork.allVendors.count) * 1000, slowest.1 * 1000, slowest.0))
        XCTAssertLessThan(slowest.1, 0.25)
    }
}

@MainActor
final class BotMarkTests: XCTestCase {
    private func stage(in view: NSView) -> BotStageView? {
        if let found = view as? BotStageView { return found }
        for child in view.subviews { if let found = stage(in: child) { return found } }
        return nil
    }

    private func hosted<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
        let frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        host.frame = frame
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    /// The reminder cards' mark, through SwiftUI and the shared clock, the way the island shows it.
    func testAReminderMarkTurnsIntoItsBotOnceItIsShown() throws {
        // With Reduce Motion on, as on the build machines, the mark is rightly left a logo.
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion keeps the logo")
        let (host, window) = hosted(BotMark(vendor: "Claude", size: 17, phase: .asking).frame(width: 60, height: 60))
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let stage = try XCTUnwrap(stage(in: host), "the bot's layer view was never made")
        let bot = try XCTUnwrap(stage.layer?.sublayers?.first)
        XCTAssertFalse(bot.isHidden)
        XCTAssertNotNil(bot.contents)
        // Asking stays raised: the layer is scaled up from its resting size.
        XCTAssertGreaterThan(bot.affineTransform().a, 1.05)
        BotClock.shared.drop(stage)
    }

    func testWithBotsOffAReminderShowsThePlainLogo() {
        let (host, window) = hosted(BotMark(vendor: "Claude", size: 17, phase: .asking).environment(\.botLogos, false))
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(stage(in: host))
    }
}
