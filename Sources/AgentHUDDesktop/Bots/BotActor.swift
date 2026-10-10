import AppKit
import QuartzCore
import SwiftUI

extension EnvironmentValues {
    /// Whether marks turn into bots while their agents are in flight. Off, every mark stays a logo.
    @Entry var botLogos: Bool = true
}

/// One bot on screen: a layer whose picture follows the bot's look and whose transform follows how it sits.
///
/// The two are kept apart on purpose. A breathing body changes its pose every frame and its picture almost
/// never, so the picture is only drawn again when the eyes or the outline have visibly moved.
@MainActor
final class BotActor {
    let layer = CALayer()
    let form: BotForm
    private var motion: BotMotion
    private var shown: BotRenderer.Look?
    /// Side of the mark in points, the display's pixel scale, and the hairline outline in pixels.
    private var side: CGFloat = 0
    private var scale: CGFloat = 2
    private var outline = 0

    init(form: BotForm, staysBot: Bool, period: TimeInterval) {
        self.form = form
        motion = BotMotion()
        motion.staysBot = staysBot
        motion.period = max(0.5, period)
        motion.spin = form.spec.spin
        layer.contentsGravity = .resize
        layer.isHidden = true
        // Every change here is already one frame of an animation; an implicit one on top would smear it.
        layer.actions = ["contents": NSNull(), "transform": NSNull(), "hidden": NSNull(), "bounds": NSNull(),
                         "position": NSNull()]
    }

    var phase: BotPhase { motion.phase }

    /// How big the layer has to be to hold a mark `side` points wide, with its room for overflow and outline.
    static func extent(side: CGFloat, scale: CGFloat, outline: Int) -> CGFloat {
        ((side * scale * (1 + 2 * BotRenderer.margin)).rounded(.up) + CGFloat(outline) * 2) / max(1, scale)
    }

    func resize(side: CGFloat, scale: CGFloat, outline: Int) {
        guard side != self.side || scale != self.scale || outline != self.outline else { return }
        self.side = side
        self.scale = scale
        self.outline = outline
        let extent = Self.extent(side: side, scale: scale, outline: outline)
        layer.bounds = CGRect(x: 0, y: 0, width: extent, height: extent)
        layer.contentsScale = scale
        shown = nil
    }

    func set(_ phase: BotPhase, at now: TimeInterval) { motion.set(phase, at: now) }

    /// Advances to `now` and redraws if the bot looks different. Returns false once it has settled back into
    /// its logo, when the layer hides and there is nothing left to step.
    ///
    /// - aim: where to look, from `BotMotion.aim(from:to:)`.
    /// - yRunsDown: whether y grows downwards in the space this layer is laid out in.
    func step(to now: TimeInterval, aim: CGPoint, yRunsDown: Bool) -> Bool {
        motion.step(to: now, aim: aim)
        guard !motion.isAtRest else {
            layer.isHidden = true
            return false
        }
        layer.isHidden = false
        let look = BotRenderer.look(of: motion)
        if look != shown, side > 0 {
            shown = look
            layer.contents = BotRenderer.image(form, motion: motion, side: side * scale, outline: outline)
        }
        layer.setAffineTransform(Self.transform(motion.pose, side: side, yRunsDown: yRunsDown))
        return true
    }

    /// A pose is written with y running down and turns clockwise; the layer may be laid out either way up.
    nonisolated static func transform(_ pose: BotPose, side: CGFloat, yRunsDown: Bool) -> CGAffineTransform {
        let up: CGFloat = yRunsDown ? 1 : -1
        let foot = CGPoint(x: 0, y: pose.footing * side * up)
        return CGAffineTransform(translationX: pose.x * side + foot.x, y: pose.y * side * up + foot.y)
            .rotated(by: pose.rotation * .pi / 180 * up)
            .scaledBy(x: pose.scaleX, y: pose.scaleY)
            .translatedBy(x: -foot.x, y: -foot.y)
    }
}

/// One timer for every bot on screen. It runs only while some bot has something to act out.
@MainActor
final class BotClock {
    static let shared = BotClock()
    static let framesPerSecond: Double = 30

    private var timer: Timer?
    private var followers: [ObjectIdentifier: (TimeInterval) -> Bool] = [:]

    /// Calls `step` every frame until it returns false or `owner` is dropped.
    func follow(_ owner: AnyObject, _ step: @escaping (TimeInterval) -> Bool) {
        followers[ObjectIdentifier(owner)] = step
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { _ in
            MainActor.assumeIsolated { BotClock.shared.tick() }
        }
        timer.tolerance = 0.004
        // Common modes, so bots keep moving while a menu is open or a window is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func drop(_ owner: AnyObject) {
        followers[ObjectIdentifier(owner)] = nil
        stopIfIdle()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (owner, step) in followers where !step(now) { followers[owner] = nil }
        CATransaction.commit()
        stopIfIdle()
    }

    private func stopIfIdle() {
        guard followers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }
}

/// An agent's mark that is its bot for as long as it is shown: asking on a request, smiling on a reply.
///
/// With bots switched off, or motion reduced, it is the plain logo.
struct BotMark: View {
    let vendor: String
    var size: CGFloat = 17
    let phase: BotPhase
    @Environment(\.botLogos) private var botLogos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if botLogos, !reduceMotion, BotForm.form(for: vendor) != nil {
            BotStage(vendor: vendor, size: size, phase: phase)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            AgentLogo(vendor: vendor, size: size)
        }
    }
}

private struct BotStage: NSViewRepresentable {
    let vendor: String
    let size: CGFloat
    let phase: BotPhase
    @Environment(\.displayScale) private var displayScale

    func makeNSView(context: Context) -> BotStageView { BotStageView() }

    func updateNSView(_ view: BotStageView, context: Context) {
        view.show(vendor: vendor, size: size, scale: displayScale, phase: phase)
    }

    static func dismantleNSView(_ view: BotStageView, coordinator: ()) { BotClock.shared.drop(view) }
}

/// Hosts one bot's layer, centred, with room round it for a hop.
final class BotStageView: NSView {
    private var actor: BotActor?
    private var vendor = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(vendor: String, size: CGFloat, scale: CGFloat, phase: BotPhase) {
        if vendor != self.vendor || actor == nil {
            self.vendor = vendor
            actor?.layer.removeFromSuperlayer()
            actor = BotForm.form(for: vendor).map { BotActor(form: $0, staysBot: true, period: 3) }
            if let actor { layer?.addSublayer(actor.layer) }
        }
        guard let actor else { return }
        actor.resize(side: size, scale: scale, outline: 0)
        actor.set(phase, at: CACurrentMediaTime())
        needsLayout = true
        follow()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        actor?.layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { BotClock.shared.drop(self) } else { follow() }
    }

    private func follow() {
        guard window != nil, actor != nil else { return }
        BotClock.shared.follow(self) { [weak self] now in self?.step(to: now) ?? false }
    }

    private func step(to now: TimeInterval) -> Bool {
        guard let actor, let window else { return false }
        let center = window.convertPoint(toScreen: convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil))
        let pointer = NSEvent.mouseLocation
        // Screen coordinates run up; a bot's gaze is measured with y running down.
        let aim = BotMotion.aim(from: CGPoint(x: center.x, y: -center.y), to: CGPoint(x: pointer.x, y: -pointer.y))
        return actor.step(to: now, aim: aim, yRunsDown: layer?.isGeometryFlipped ?? false)
    }
}
