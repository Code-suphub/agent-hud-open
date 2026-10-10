import CoreGraphics
import Foundation

/// What the agent behind a mark is doing, as far as its bot acts it out.
enum BotPhase: Sendable, Equatable {
    /// Nothing in flight: the mark is its logo, and still.
    case idle
    /// A turn is running: the bot is awake and does one small thing at random every second or three.
    case working
    /// A turn is blocked on the user: the bot hops, stays raised and turns to face them.
    case asking
    /// A turn just ended: the bot smiles.
    case done
}

/// The bot's eyes. `look` and `lookY` are shares of a full turn of the head, right and down positive.
struct BotFace: Equatable, Sendable {
    var open: CGFloat = 1
    var look: CGFloat = 0
    var lookY: CGFloat = 0
    var wide: CGFloat = 1
    var happy: CGFloat = 0
    /// Positive grows the right eye and narrows the left, as when peering at something.
    var lean: CGFloat = 0
}

/// How the whole bot sits: offsets are shares of the mark's side, rotation is in degrees.
struct BotPose: Equatable, Sendable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    /// Where it squashes from: 0 is the centre, 0.5 the bottom edge.
    var footing: CGFloat = 0

    func mixed(with other: BotPose, _ share: CGFloat) -> BotPose {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * share }
        return BotPose(x: mix(x, other.x), y: mix(y, other.y), rotation: mix(rotation, other.rotation),
                       scaleX: mix(scaleX, other.scaleX), scaleY: mix(scaleY, other.scaleY),
                       footing: mix(footing, other.footing))
    }
}

/// One bot's state over time: how far the logo has turned into the bot, what its eyes are doing and how it
/// sits. It is stepped with a clock and nothing else, so the same seed and the same times give the same bot.
struct BotMotion: Sendable {
    /// An alert shows its bot for as long as the alert is up; a logo queue lets it settle back into the logo.
    var staysBot = false
    /// Seconds for one breath of the working body.
    var period: TimeInterval = 3
    /// Degrees per second the body turns under the face while working.
    var spin: CGFloat = 0

    private(set) var phase: BotPhase = .idle
    private(set) var since: TimeInterval = -10
    /// 0 is the logo, 1 the bot.
    private(set) var morph: CGFloat = 0
    private(set) var face = BotFace()
    private(set) var pose = BotPose()
    /// Degrees the body has turned.
    private(set) var turn: CGFloat = 0
    /// The piece a mark keeps above its body: how far it has hopped, and how big it is.
    private(set) var kept = (lift: CGFloat(0), scale: CGFloat(1))

    private var last: TimeInterval?
    private var leaving: BotPose?
    private var act: Act?
    private var nextAct: TimeInterval = 0
    private var blinks: [TimeInterval] = [-1, -1]
    private var nextBlink: TimeInterval = 2
    private var random: SplitMix

    private struct Act {
        enum Kind: CaseIterable { case glance, blinkTwice, squint, widen, smile, inspect, tilt, hop, wiggle, turn }
        var kind: Kind
        var start: TimeInterval
        var length: TimeInterval
        var side: CGFloat
        var gaze: CGPoint
        var from: CGFloat
    }

    init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) { random = SplitMix(state: seed) }

    /// Nothing left to draw: the logo is back and at rest.
    var isAtRest: Bool {
        guard morph == 0, !staysBot else { return false }
        switch phase {
        case .idle: return pose == BotPose()
        case .done: return (last ?? 0) - since > 2.4
        case .working, .asking: return false
        }
    }

    mutating func set(_ next: BotPhase, at now: TimeInterval) {
        guard next != phase else { return }
        leaving = pose
        phase = next
        since = now
        if next == .working { nextAct = now + 0.9 + random.unit() * 1.2 }
    }

    /// Advances to `now`. `aim` is where the bot should look, as returned by `BotMotion.aim(from:to:)`.
    mutating func step(to now: TimeInterval, aim: CGPoint = .zero, hasFace: Bool = true) {
        let dt = min(0.1, max(0, now - (last ?? now)))
        last = now
        let age = now - since
        let awake = phase == .working || phase == .asking || (phase == .done && age < 1.5)

        let wanted: CGFloat = (awake || staysBot) && hasFace ? 1 : 0
        let stride = CGFloat(dt / 0.5)
        morph = abs(wanted - morph) <= stride ? wanted : morph + (wanted > morph ? stride : -stride)

        // Random life while working: one small act, a pause, another.
        if let running = act, now - running.start >= running.length {
            if running.kind == .turn { turn = running.from + 60 * running.side }
            act = nil
        }
        if phase == .working, morph > 0.9 || !hasFace {
            if act == nil, now >= nextAct {
                let chosen = pick(at: now)
                act = chosen
                nextAct = now + chosen.length + 0.5 + random.unit() * 1.9
                if chosen.kind == .blinkTwice { blinks = [now, now + 0.24] }
            }
        } else {
            act = nil
        }
        let progress = act.map { CGFloat((now - $0.start) / $0.length) } ?? 0
        let swell = act == nil ? 0 : Self.easeInOut(min(1, min(progress / 0.22, (1 - progress) / 0.22)))
        if phase == .working, morph > 0.5, spin != 0 {
            if let act, act.kind == .turn { turn = act.from + 60 * act.side * Self.easeInOut(progress) }
            else { turn += spin * CGFloat(dt) }
        }

        pose = sitting(age: age, progress: progress, swell: swell)
        if let leaving, age < 0.3 { pose = leaving.mixed(with: pose, Self.easeOut(CGFloat(age / 0.3))) }
        if morph > 0.5 { pose.x += 0.025 * face.look }

        look(age: age, now: now, dt: dt, aim: aim, swell: swell)
        keep(age: age, now: now, dt: dt)
    }

    /// Where a bot centred at `center` should look to face `target`, both in the same y-down coordinates.
    /// Something close by turns the head less than something far away.
    static func aim(from center: CGPoint, to target: CGPoint) -> CGPoint {
        let dx = target.x - center.x, dy = target.y - center.y, distance = hypot(dx, dy)
        guard distance >= 1 else { return .zero }
        let share = distance / (distance + 120)
        return CGPoint(x: dx / distance * share, y: dy / distance * share)
    }

    // MARK: Body

    private func sitting(age: TimeInterval, progress: CGFloat, swell: CGFloat) -> BotPose {
        var pose = BotPose()
        let t = CGFloat(age)
        switch phase {
        case .working:
            // Breathing: a slow bob with the body filling out and settling twice per breath.
            let breath = 2 * CGFloat.pi * CGFloat(age / period)
            pose.y = 0.035 * sin(breath)
            pose.scaleX = 1 + 0.03 * sin(2 * breath)
            pose.scaleY = 1 - 0.03 * sin(2 * breath)
            pose.footing = 0.5
        case .asking:
            if t < 0.45 {
                let x = t / 0.45, arc = sin(.pi * x)
                pose.y = -0.26 * 4 * x * (1 - x)
                pose.scaleY = 1 + 0.08 * arc
                pose.scaleX = 1 - 0.05 * arc
            }
            let raised = 1 + 0.12 * Self.easeOutBack(min(1, t / 0.35))
            pose.scaleX *= raised
            pose.scaleY *= raised
            // A knock every few seconds, until it is answered.
            let cycle = (t - 1.2).truncatingRemainder(dividingBy: 2.6)
            if t > 1.2, cycle < 0.55 {
                let x = cycle / 0.55
                pose.rotation = 8 * sin(2 * .pi * 2.5 * x) * (1 - x)
            }
        case .done:
            if t < 0.6 {
                let pop = sin(.pi * t / 0.6)
                pose.scaleX = 1 + 0.2 * pop
                pose.scaleY = 1 + 0.2 * pop
                pose.y = -0.1 * pop
            }
        case .idle:
            break
        }
        guard let act else { return pose }
        switch act.kind {
        case .tilt: pose.rotation += act.side * 9 * swell
        case .hop:
            let arc = sin(.pi * progress)
            pose.y -= 0.17 * 4 * progress * (1 - progress)
            pose.scaleY *= 1 + 0.06 * arc
            pose.scaleX *= 1 - 0.04 * arc
        case .wiggle: pose.rotation += 8 * sin(2 * .pi * 3 * progress) * (1 - progress)
        default: break
        }
        return pose
    }

    // MARK: Face

    private mutating func look(age: TimeInterval, now: TimeInterval, dt: TimeInterval, aim: CGPoint, swell: CGFloat) {
        var target = BotFace()
        var every: ClosedRange<TimeInterval>? = 3.2...6.5
        switch phase {
        case .working:
            target.look = aim.x
            target.lookY = aim.y
            every = 2.2...4.5
            if let act {
                switch act.kind {
                case .glance:
                    // A glance looks away and comes back.
                    target.look += (act.gaze.x * 0.8 - target.look) * swell
                    target.lookY += (act.gaze.y - target.lookY) * swell
                case .squint: target.open = 1 - 0.55 * swell
                case .widen: target.wide = 1 + 0.2 * swell
                case .smile: target.happy = swell > 0.4 ? 1 : 0
                case .inspect:
                    target.lean = act.side * swell
                    target.look += (act.side * 0.6 - target.look) * swell
                    target.lookY -= target.lookY * swell
                default: break
                }
            }
        case .asking:
            // Straight at the user, wide open, and no blinking until the stare has landed.
            target.wide = 1.22
            every = age < 1.5 ? nil : 4...7
        case .done:
            if age < 1.25 {
                target.happy = 1
                every = nil
            } else {
                target.look = aim.x
                target.lookY = aim.y
            }
        case .idle:
            target.look = aim.x
            target.lookY = aim.y
        }

        let eyes = CGFloat(1 - exp(-dt * 18)), head = CGFloat(1 - exp(-dt * 9))
        face.look += (target.look - face.look) * head
        face.lookY += (target.lookY - face.lookY) * head
        face.wide += (target.wide - face.wide) * eyes
        face.happy += (target.happy - face.happy) * eyes
        face.lean += (target.lean - face.lean) * eyes

        var lid = target.open
        if let every {
            if now >= nextBlink {
                blinks = [now, -1]
                nextBlink = now + every.lowerBound + random.unit() * (every.upperBound - every.lowerBound)
            }
        } else if nextBlink < now {
            nextBlink = now + 1.2
        }
        for start in blinks {
            let blink = (now - start) / 0.17
            if blink >= 0, blink < 1 { lid *= 1 - CGFloat(sin(.pi * blink)) }
        }
        face.open += (lid - face.open) * CGFloat(1 - exp(-dt * 60))
    }

    private mutating func keep(age: TimeInterval, now: TimeInterval, dt: TimeInterval) {
        var lift: CGFloat = 0, scale: CGFloat = 1
        switch phase {
        case .working:
            let bounce = CGFloat((now / (period / 2)).truncatingRemainder(dividingBy: 1))
            lift = 0.13 * 4 * bounce * (1 - bounce)
        case .asking:
            lift = 0.03
            scale = 1.22 + 0.08 * CGFloat(sin(2 * .pi * now / 0.8))
        case .done:
            if age < 0.6 { lift = 0.22 * CGFloat(sin(.pi * age / 0.6)) }
        case .idle:
            break
        }
        let ease = CGFloat(1 - exp(-dt * 22))
        kept.lift += (lift - kept.lift) * ease
        kept.scale += (scale - kept.scale) * ease
    }

    // MARK: Acts

    private mutating func pick(at now: TimeInterval) -> Act {
        var pool: [(Act.Kind, Double)] = [(.glance, 5), (.blinkTwice, 2), (.squint, 2), (.widen, 2), (.smile, 2),
                                          (.inspect, 2), (.tilt, 3), (.hop, 2), (.wiggle, 2)]
        if spin != 0 { pool.append((.turn, 3)) }
        var roll = random.unit() * pool.reduce(0) { $0 + $1.1 }
        var kind = pool[0].0
        for (candidate, weight) in pool {
            roll -= weight
            if roll < 0 { kind = candidate; break }
        }
        let length: TimeInterval
        switch kind {
        case .glance: length = 1.1 + random.unit() * 0.7
        case .blinkTwice: length = 0.5
        case .squint: length = 1.2
        case .widen: length = 0.9
        case .smile: length = 1.1
        case .inspect: length = 1.5
        case .tilt: length = 1.1
        case .hop: length = 0.55
        case .wiggle: length = 0.6
        case .turn: length = 0.7
        }
        let angle = random.unit() * 2 * .pi
        return Act(kind: kind, start: now, length: length, side: random.unit() < 0.5 ? -1 : 1,
                   gaze: CGPoint(x: cos(angle), y: sin(angle) * 0.7), from: turn)
    }

    // MARK: Curves

    static func easeInOut(_ x: CGFloat) -> CGFloat { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    static func easeOut(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }
    static func easeOutBack(_ x: CGFloat) -> CGFloat {
        let c: CGFloat = 1.70158
        return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
    }
}

/// A small seeded generator, so a bot's random acts can be replayed in a test.
struct SplitMix: Sendable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// 0 up to, not including, 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
