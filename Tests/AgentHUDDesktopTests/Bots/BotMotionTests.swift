import CoreGraphics
import XCTest
@testable import AgentHUDDesktop

final class BotMotionTests: XCTestCase {
    /// Steps a motion at 30 frames a second from `start` for `seconds`.
    private func run(_ motion: inout BotMotion, from start: TimeInterval, for seconds: TimeInterval, aim: CGPoint = .zero) {
        var now = start
        while now <= start + seconds {
            motion.step(to: now, aim: aim)
            now += 1.0 / 30
        }
    }

    func testAnIdleMarkStaysItsLogoAndAtRest() {
        var motion = BotMotion(seed: 1)
        run(&motion, from: 0, for: 2)
        XCTAssertEqual(motion.morph, 0)
        XCTAssertEqual(motion.pose, BotPose())
        XCTAssertTrue(motion.isAtRest)
    }

    func testWorkTurnsTheLogoIntoItsBotInHalfASecond() {
        var motion = BotMotion(seed: 1)
        motion.set(.working, at: 0)
        run(&motion, from: 0, for: 0.3)
        XCTAssertGreaterThan(motion.morph, 0)
        XCTAssertLessThan(motion.morph, 1)
        run(&motion, from: 0.3, for: 0.4)
        XCTAssertEqual(motion.morph, 1)
        XCTAssertFalse(motion.isAtRest)
    }

    func testAFinishedTurnSmilesThenSettlesBackIntoTheLogo() {
        var motion = BotMotion(seed: 1)
        motion.set(.working, at: 0)
        run(&motion, from: 0, for: 1)
        motion.set(.done, at: 1)
        run(&motion, from: 1, for: 0.8)
        XCTAssertGreaterThan(motion.face.happy, 0.9)
        XCTAssertEqual(motion.morph, 1)
        run(&motion, from: 1.8, for: 2)
        XCTAssertEqual(motion.morph, 0)
        XCTAssertTrue(motion.isAtRest)
    }

    func testAnAlertKeepsItsBotAfterTheSmile() {
        var motion = BotMotion(seed: 1)
        motion.staysBot = true
        motion.set(.done, at: 0)
        run(&motion, from: 0, for: 4)
        XCTAssertEqual(motion.morph, 1)
        XCTAssertLessThan(motion.face.happy, 0.05)
        XCTAssertFalse(motion.isAtRest)
    }

    func testAskingFacesTheUserWithWideEyesWhateverItWasLookingAt() {
        var motion = BotMotion(seed: 1)
        motion.set(.working, at: 0)
        run(&motion, from: 0, for: 2, aim: CGPoint(x: 0.8, y: 0.3))
        XCTAssertGreaterThan(motion.face.look, 0.3)
        motion.set(.asking, at: 2)
        run(&motion, from: 2, for: 1, aim: CGPoint(x: 0.8, y: 0.3))
        XCTAssertEqual(motion.face.look, 0, accuracy: 0.02)
        XCTAssertEqual(motion.face.lookY, 0, accuracy: 0.02)
        XCTAssertGreaterThan(motion.face.wide, 1.15)
        XCTAssertGreaterThan(motion.pose.scaleX, 1.05)
    }

    func testTheSameSeedReplaysTheSameActs() {
        var first = BotMotion(seed: 42), second = BotMotion(seed: 42), other = BotMotion(seed: 7)
        first.set(.working, at: 0); second.set(.working, at: 0); other.set(.working, at: 0)
        var differed = false
        var now: TimeInterval = 0
        while now < 20 {
            first.step(to: now); second.step(to: now); other.step(to: now)
            XCTAssertEqual(first.face, second.face)
            XCTAssertEqual(first.pose, second.pose)
            if first.face != other.face || first.pose != other.pose { differed = true }
            now += 1.0 / 30
        }
        XCTAssertTrue(differed)
    }

    func testAimTurnsLessTowardsSomethingClose() {
        let near = BotMotion.aim(from: .zero, to: CGPoint(x: 30, y: 0))
        let far = BotMotion.aim(from: .zero, to: CGPoint(x: 900, y: 0))
        XCTAssertGreaterThan(far.x, near.x)
        XCTAssertLessThan(far.x, 1)
        XCTAssertEqual(BotMotion.aim(from: .zero, to: .zero), .zero)
        // Down on screen is down for the eyes.
        XCTAssertGreaterThan(BotMotion.aim(from: .zero, to: CGPoint(x: 0, y: 200)).y, 0)
    }

    func testAPoseLiftsAndTurnsTheSameWayWhicheverWayUpTheLayerIs() {
        var pose = BotPose()
        pose.y = -0.2
        pose.rotation = 10
        let down = BotActor.transform(pose, side: 20, yRunsDown: true)
        let up = BotActor.transform(pose, side: 20, yRunsDown: false)
        // A hop moves up the screen: less y where y runs down, more where it runs up.
        XCTAssertEqual(down.ty, -4, accuracy: 0.001)
        XCTAssertEqual(up.ty, 4, accuracy: 0.001)
        XCTAssertEqual(down.b, -up.b, accuracy: 0.001)
    }
}
