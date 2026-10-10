import AppKit
import AgentHUDCore
import QuartzCore
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
        XCTAssertFalse(clock.moving)
        XCTAssertEqual(view.marks[0].opacity, 1)
        XCTAssertTrue(claude.layer.isHidden)
    }

    func testWithBotsOffAWorkingMarkBobsAsBefore() {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", true)], bots: false), light: false, scale: 2, animates: true)
        XCTAssertNil(view.actors[0])
        XCTAssertNotNil(view.marks[0].animation(forKey: "bob"))
        XCTAssertFalse(view.stepBots(to: CACurrentMediaTime()))
    }

    func testReduceMotionLeavesEveryMarkItsLogo() {
        let (view, window) = hosted()
        defer { BotClock.shared.drop(view); window.close() }
        view.apply(config: queue([("Claude", true)]), light: false, scale: 2, animates: false)
        let clock = run(view, from: CACurrentMediaTime(), frames: 10)
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
