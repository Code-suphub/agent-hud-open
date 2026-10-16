import CoreGraphics
import Foundation

/// What the agent behind a mark is doing, as far as its bot acts it out.
enum BotPhase: Sendable, Equatable {
    /// Nothing in flight: the mark rests as its logo, with a brief bot visit now and then.
    case idle
    /// A turn is running: the bot stays awake and acts in place.
    case working
    /// A turn is blocked on the user: the bot hops, stays raised and turns to face them.
    case asking
    /// A turn just ended: the bot smiles.
    case done
    /// The agent's own card is open, from a hover or a click: the bot is up and watches the pointer for as long as
    /// the card stays open.
    case opened

    /// The mark stays where its logo is, with no hop and nothing raised.
    var staysInPlace: Bool { self == .working || self == .idle || self == .opened }
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

/// Where a sprite is, for a bot drawn as pixel art with limbs (`BotSpec.Limbs`): its arms and legs, where the whole
/// body has stepped or hopped to, and the sign over its head, all in whole steps of the art. Other bots keep it at rest.
struct BotLimbs: Hashable, Sendable {
    /// How far each arm is raised: 0 at its side, 1 a step up, 2 up and out.
    var left = 0, right = 0
    /// The legs lifted: 0 none, 1 the first and third, 2 the second and fourth, 3 all four, tucked up for a jump.
    var lifted = 0
    /// How far the whole body has stepped aside or hopped, right and down positive.
    var x = 0, y = 0
    /// Over its head while its agent works: Claude Code's spinner, a frame of its star from 1 (a dot) to 6
    /// (the fullest); 0 for none.
    var spinner = 0
    /// Over its head while a request waits: an exclamation mark.
    var exclaims = false
}

/// How long a bot can go without a frame. Every frame it is drawn costs a picture or at least a move of its
/// layer, so it asks for no more of them than its motion can show.
enum BotPace {
    /// A morph, an act, a blink or a hop.
    static let lively: TimeInterval = 1.0 / 30
    /// Eyes following the pointer.
    static let following: TimeInterval = 1.0 / 15
    /// Nothing but a breath and a slow turn, which move a fraction of a pixel in this long.
    static let calm: TimeInterval = 1.0 / 10
}

/// One bot's state over time: how far the logo has turned into the bot, what its eyes are doing and how it
/// sits. It is stepped with a clock and nothing else, so the same seed and the same times give the same bot.
struct BotMotion: Sendable {
    private static let morphSeconds: TimeInterval = 0.5
    /// The most time one step moves the bot by.
    private static let longestStep: TimeInterval = 0.1
    /// How long after a turn ended its mark rests as the logo again.
    private static let doneSeconds: TimeInterval = 2.4
    /// An alert shows its bot for as long as the alert is up; a logo queue lets it settle back into the logo.
    var staysBot = false
    /// Seconds a staying bot keeps its logo after it is first given a phase. A reminder's card is still opening
    /// then, so the mark is read as the agent's logo before it turns into the bot. The phase begins on arrival.
    var arrivesAfter: TimeInterval = 0
    /// Seconds for one breath of the body.
    var period: TimeInterval = 3
    /// Degrees per second the body turns under the face while awake.
    var spin: CGFloat = 0
    /// The body has arms and legs to move, and is moved as pixel art: in whole steps, with no breathing.
    var limbed = false
    /// One step of a limbed body's art, as a share of the mark's side: how far it moves the whole body at a time.
    var stepShare: CGFloat = 0

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
    private(set) var limbs = BotLimbs()
    /// Seconds from the last step until the bot next needs a frame: a frame's length while it moves, the time to
    /// its next visit while it waits as its logo, and nothing once it rests as the logo for good.
    private(set) var wait: TimeInterval? = BotPace.lively

    private var last: TimeInterval?
    private var leaving: BotPose?
    private var act: Act?
    private var nextAct: TimeInterval = 0
    private var blinks: [TimeInterval] = [-1, -1]
    private var nextBlink: TimeInterval = 2
    /// The eyes are still on their way to where they should look, or a lid is still moving.
    private var following = false, blinking = false
    /// The next brief bot visit while idle, between longer stretches as the original logo.
    private var botInterval: Range<TimeInterval>?
    /// The next act is a wave at whoever just opened the agent's card.
    private var greets = false
    private var random: SplitMix

    private struct Act {
        enum Kind: CaseIterable {
            case glance, blinkTwice, squint, widen, smile, inspect, tilt, stretch, wiggle, turn
            /// For a body with limbs: one arm up and waving; a few steps aside and back; a jump.
            case wave, scuttle, hop
        }
        var kind: Kind
        var start: TimeInterval
        var length: TimeInterval
        var side: CGFloat
        var gaze: CGPoint
        var from: CGFloat
    }

    init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) { random = SplitMix(state: seed) }

    /// Takes on what a body's spec says about how it moves.
    mutating func fit(_ spec: BotSpec) {
        spin = spec.spin
        limbed = spec.limbs != nil
        stepShare = spec.limbs.map { $0.pixel / 2 * spec.radius } ?? 0
    }

    /// Nothing left to draw or wait for: the logo is back and at rest.
    var isAtRest: Bool {
        guard morph == 0, !staysBot else { return false }
        switch phase {
        case .idle: return botInterval == nil && pose == BotPose()
        case .done: return (last ?? 0) - since > Self.doneSeconds
        case .working, .asking, .opened: return false
        }
    }

    mutating func set(_ next: BotPhase, at now: TimeInterval) {
        guard next != phase else {
            if next == .idle, !staysBot, botInterval == nil { scheduleBot(after: now) }
            return
        }
        leaving = pose
        phase = next
        since = now + (staysBot && morph == 0 ? max(0, arrivesAfter) : 0)
        if next == .working {
            nextAct = now + 0.9 + random.unit() * 1.2
        } else if next == .opened {
            nextAct = now + 0.9 + random.unit() * 1.2
        }
        // A body with arms greets whoever opened its card: a wave as soon as it has turned into its bot.
        greets = limbed && next == .opened
        if greets {
            act = nil
            nextAct = now
        }
        botInterval = nil
        if next == .idle, !staysBot { scheduleBot(after: now + Double(morph) * Self.morphSeconds) }
    }

    /// Advances to `now`. `aim` is where the bot should look, as returned by `BotMotion.aim(from:to:)`.
    mutating func step(to now: TimeInterval, aim: CGPoint = .zero, hasFace: Bool = true) {
        // Time the clock slept through moves nothing: a bot woken for its visit starts from where it stopped.
        let gap = max(0, now - (last ?? now))
        let dt = gap > 2 * Self.longestStep ? 0 : min(Self.longestStep, gap)
        last = now
        let age = now - since
        if phase == .idle, !staysBot, let interval = botInterval, now >= interval.upperBound {
            scheduleBot(after: now + Self.morphSeconds)
        }
        let idleVisit = phase == .idle && botInterval?.contains(now) == true
        // Before a staying bot arrives it is the logo at rest: no morph, no pose, no face.
        let arrived = age >= 0
        let awake = arrived && (phase == .working || idleVisit || phase == .asking || phase == .opened
                                || (phase == .done && age < 1.5))

        let wanted: CGFloat = arrived && (awake || staysBot) && hasFace ? 1 : 0
        let stride = CGFloat(dt / Self.morphSeconds)
        morph = abs(wanted - morph) <= stride ? wanted : morph + (wanted > morph ? stride : -stride)

        // Random life while awake: one small act, a pause, another.
        if let running = act, now - running.start >= running.length {
            if running.kind == .turn { turn = running.from + 60 * running.side }
            act = nil
        }
        let actsInPlace = phase.staysInPlace
        if actsInPlace {
            if awake || staysBot, morph > 0.9 || !hasFace, act == nil, now >= nextAct {
                var chosen = pick(at: now)
                // A wave is made with the arm on the pointer's side.
                if chosen.kind == .wave, aim.x != 0 { chosen.side = aim.x > 0 ? 1 : -1 }
                act = chosen
                nextAct = now + chosen.length + 0.5 + random.unit() * 1.9
                if chosen.kind == .blinkTwice { blinks = [now, now + 0.24] }
            }
        } else {
            act = nil
        }
        let progress = act.map { CGFloat((now - $0.start) / $0.length) } ?? 0
        let swell = act == nil ? 0 : Self.easeInOut(min(1, min(progress / 0.22, (1 - progress) / 0.22)))
        if actsInPlace, morph > 0.5, spin != 0 {
            if let act, act.kind == .turn { turn = act.from + 60 * act.side * Self.easeInOut(progress) }
            else { turn += spin * CGFloat(dt) }
        }

        pose = arrived ? sitting(age: age, progress: progress, swell: swell) : BotPose()
        if let leaving, arrived, age < 0.3 { pose = leaving.mixed(with: pose, Self.easeOut(CGFloat(age / 0.3))) }
        if actsInPlace {
            // Keep the centre fixed, even when returning from an alert's raised pose. The original logo
            // is still while it is shown; breathing and turns arrive with the bot again.
            pose = BotPose().mixed(with: pose, morph)
            pose.x = 0
            pose.y = 0
            pose.footing = 0
        } else if morph > 0.5 {
            pose.x += 0.025 * face.look
        }
        limbs = limbed && arrived ? stance(age: age, now: now) : BotLimbs()
        // A sprite's steps and hops move the whole picture, a step of its art at a time.
        pose.x += CGFloat(limbs.x) * stepShare * morph
        pose.y += CGFloat(limbs.y) * stepShare * morph

        if arrived, !actsInPlace || morph > 0 { look(age: age, now: now, dt: dt, aim: aim, swell: swell) }
        else { (following, blinking) = (false, false) }
        if arrived { keep(age: age, now: now, dt: dt) }
        wait = nextFrame(now: now, age: age, wanted: wanted)
    }

    private func nextFrame(now: TimeInterval, age: TimeInterval, wanted: CGFloat) -> TimeInterval? {
        if isAtRest { return nil }
        // A logo waiting to arrive shows nothing new until it does.
        if age < 0 { return max(BotPace.lively, -age) }
        if morph == 0, wanted == 0 {
            // The logo is showing: nothing moves before an idle mark's next visit, or a finished turn's rest.
            if phase == .idle, let visit = botInterval { return max(BotPace.lively, visit.lowerBound - now) }
            if phase == .done { return max(BotPace.lively, since + Self.doneSeconds - now + 0.01) }
            return BotPace.lively
        }
        if morph != wanted || act != nil || blinking || age < 0.3 { return BotPace.lively }
        switch phase {
        case .asking:
            // The hop, then a knock every few seconds; between knocks only the kept piece pulses.
            let knock = (age - 1.2).truncatingRemainder(dividingBy: 2.6)
            return age < 1.2 || knock < 0.55 ? BotPace.lively : BotPace.following
        case .done:
            if age < 1.5 { return BotPace.lively }
        case .working, .idle, .opened:
            break
        }
        return following ? BotPace.following : BotPace.calm
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

    private mutating func scheduleBot(after now: TimeInterval) {
        let start = now + 20 + random.unit() * 15
        // Fade-in is part of this interval; fade-out follows it. Together the visit lasts 3–5 seconds.
        botInterval = start..<(start + 3 + random.unit() * 2 - Self.morphSeconds)
        nextAct = start + Self.morphSeconds
    }

    private func sitting(age: TimeInterval, progress: CGFloat, swell: CGFloat) -> BotPose {
        var pose = BotPose()
        let t = CGFloat(age)
        switch phase {
        case .working, .idle, .opened:
            // Breathing changes the body's shape around its fixed centre. Pixel art keeps its shape.
            guard !limbed else { break }
            let breath = 2 * CGFloat.pi * CGFloat(age / period)
            pose.scaleX = 1 + 0.03 * sin(2 * breath)
            pose.scaleY = 1 - 0.03 * sin(2 * breath)
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
            // A body with limbs jumps for its knock instead (`stance`).
            if t > 1.2, cycle < 0.55, !limbed {
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
        }
        // A sprite's acts move it in steps (`stance`), never by turning or stretching the picture.
        guard let act, !limbed else { return pose }
        switch act.kind {
        case .tilt: pose.rotation += act.side * 9 * swell
        case .stretch:
            let arc = sin(.pi * progress)
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
        case .working, .idle, .opened:
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
                case .stretch where limbed: target.open = 1 - 0.9 * swell
                case .hop: target.wide = 1 + 0.2 * swell
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
        // Finer than the steps a picture is drawn in, so the last frame of a move is the settled one.
        blinking = abs(lid - face.open) > 0.01 || blinks.contains { now >= $0 && now - $0 < 0.17 }
        following = abs(target.look - face.look) > 0.004 || abs(target.lookY - face.lookY) > 0.004
            || abs(target.wide - face.wide) > 0.004 || abs(target.happy - face.happy) > 0.01
            || abs(target.lean - face.lean) > 0.01
    }

    private mutating func keep(age: TimeInterval, now: TimeInterval, dt: TimeInterval) {
        guard !phase.staysInPlace else {
            kept = (lift: 0, scale: 1)
            return
        }
        var lift: CGFloat = 0, scale: CGFloat = 1
        switch phase {
        case .working, .idle, .opened:
            break
        case .asking:
            lift = 0.03
            scale = 1.22 + 0.08 * CGFloat(sin(2 * .pi * now / 0.8))
        case .done:
            if age < 0.6 { lift = 0.22 * CGFloat(sin(.pi * age / 0.6)) }
        }
        let ease = CGFloat(1 - exp(-dt * 22))
        kept.lift += (lift - kept.lift) * ease
        kept.scale += (scale - kept.scale) * ease
    }

    /// Where the sprite is now, in whole steps of its art. While its agent works, Claude Code's spinner turns over its
    /// head and the sprite types, a hand at a time, in bursts of three seconds with a pause between. While a request waits an exclamation mark stands there; the sprite waves both arms in turn through the hop
    /// and jumps through each knock, and keeps a hand up between knocks. A reply gets a dance: arms up in turn and a
    /// jump on every other beat. Then whatever the act in hand moves.
    private func stance(age: TimeInterval, now: TimeInterval) -> BotLimbs {
        var limbs = BotLimbs()
        func beat(_ seconds: TimeInterval, _ every: TimeInterval) -> Int { Int(max(0, seconds) / every) }
        switch phase {
        case .working:
            // Its six shapes out and back.
            let frame = beat(now, 0.12) % 10
            limbs.spinner = frame < 6 ? frame + 1 : 11 - frame
            if age.truncatingRemainder(dividingBy: 4.5) < 3 {
                let tap = beat(age, 0.13)
                limbs.left = tap % 2
                limbs.right = 1 - limbs.left
                // Leaning into the keys every other pair of taps.
                limbs.y = tap / 2 % 2
            }
        case .asking:
            limbs.exclaims = true
            let knock = (age - 1.2).truncatingRemainder(dividingBy: 2.6)
            if age < 1.2 || knock < 0.55 {
                limbs.left = 1 + beat(age, 0.15) % 2
                limbs.right = 3 - limbs.left
                if age >= 1.2, beat(knock, 0.14) % 2 == 0 {
                    limbs.y = -2
                    limbs.lifted = 3
                }
            } else {
                limbs.right = 2
            }
        case .done:
            if age < 1.6 {
                let step = beat(age, 0.2)
                limbs.left = step % 2 == 0 ? 2 : 0
                limbs.right = 2 - limbs.left
                if step % 2 == 1 {
                    limbs.y = -2
                    limbs.lifted = 3
                }
            }
        case .idle, .opened:
            break
        }
        guard let act, phase.staysInPlace else { return limbs }
        let since = now - act.start, ending = since > act.length - 0.15
        func frame(_ count: Int) -> Int { min(count - 1, beat(since, act.length / Double(count))) }
        // An act of the body's takes its arms and legs from whatever they were doing; the face's acts leave them.
        if [.wave, .scuttle, .hop, .stretch].contains(act.kind) { (limbs.left, limbs.right, limbs.y) = (0, 0, 0) }
        switch act.kind {
        case .wave:
            // A small jump to say hello, then the arm on the pointer's side up and waving.
            if since < 0.24 { limbs.y = -1 }
            let arm = since < 0.12 || ending ? 1 : 2 - beat(since - 0.12, 0.16) % 2
            if act.side < 0 { limbs.left = arm } else { limbs.right = arm }
        case .scuttle:
            // Sideways, as crabs go: two steps out, back past where it stood, and home, a pair of legs up on each step.
            let path = [0, 1, 2, 1, 0, -1, -2, -1, 0], step = frame(path.count)
            limbs.x = path[step] * (act.side < 0 ? -1 : 1)
            limbs.lifted = step == 0 || step == path.count - 1 ? 0 : 1 + step % 2
        case .hop:
            // Down onto bent legs, up three steps with the arms flung up, and down onto bent legs again.
            let path: [(y: Int, lifted: Int, arms: Int)] = [(1, 3, 0), (-2, 0, 1), (-3, 0, 2), (-3, 0, 2), (-2, 0, 1),
                                                          (0, 0, 0), (1, 3, 0), (0, 0, 0)]
            let at = path[frame(path.count)]
            (limbs.y, limbs.lifted, limbs.left, limbs.right) = (at.y, at.lifted, at.arms, at.arms)
        case .stretch:
            // Arms up and out and a step taller, eyes shut, as at a yawn.
            if since > 0.15, !ending { (limbs.left, limbs.right, limbs.y) = (2, 2, -1) }
        default:
            break
        }
        return limbs
    }

    // MARK: Acts

    private mutating func pick(at now: TimeInterval) -> Act {
        var pool: [(Act.Kind, Double)] = [(.glance, 5), (.blinkTwice, 2), (.squint, 2), (.widen, 2), (.smile, 2),
                                          (.inspect, 2), (.tilt, 3), (.stretch, 2), (.wiggle, 2)]
        if spin != 0 { pool.append((.turn, 3)) }
        if limbed {
            // A sprite does not tilt or wobble; its stretch reaches up. Now and then it steps aside, jumps or waves
            // between bursts of typing; a wave and a jump for whoever looks; and a short visit is always one of its
            // own moves.
            pool.removeAll { $0.0 == .tilt || $0.0 == .wiggle }
            switch phase {
            case .working: pool += [(.scuttle, 4), (.hop, 3), (.wave, 1)]
            case .opened: pool += [(.wave, 4), (.hop, 2), (.scuttle, 2)]
            case .idle: pool = [(.scuttle, 3), (.hop, 3), (.stretch, 3), (.wave, 2)]
            case .asking, .done: break
            }
        }
        var roll = random.unit() * pool.reduce(0) { $0 + $1.1 }
        var kind = pool[0].0
        for (candidate, weight) in pool {
            roll -= weight
            if roll < 0 { kind = candidate; break }
        }
        if greets {
            greets = false
            kind = .wave
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
        case .stretch: length = 0.55
        case .wiggle: length = 0.6
        case .turn: length = 0.7
        case .wave: length = 1.4
        case .scuttle: length = 1.1
        case .hop: length = 0.8
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
