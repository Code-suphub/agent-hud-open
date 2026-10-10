#if DEBUG
import SwiftUI

/// Every bundled mark as its bot at one moment of one phase, large and at logo-queue size, for snapshots.
///
/// The frames are still pictures from the renderer, not the animating layers, which bitmap caching cannot
/// see. Each bot is stepped with a fixed seed, so the sheet is the same on every run.
struct BotSheetScene: View {
    let phase: BotPhase
    /// How long the phase has been running when the picture is taken.
    var seconds: TimeInterval = 1.2

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(108), spacing: 10), count: 7)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AgentArtwork.allVendors, id: \.self) { vendor in
                VStack(spacing: 6) {
                    HStack(alignment: .bottom, spacing: 8) {
                        frame(vendor, side: 44)
                        frame(vendor, side: 20)
                    }
                    .frame(width: 108, height: 78)
                    .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 10))
                    Text(vendor).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.10))
    }

    @ViewBuilder
    private func frame(_ vendor: String, side: CGFloat) -> some View {
        if let form = BotForm.form(for: vendor), let image = picture(form, side: side) {
            Image(decorative: image, scale: 2)
        } else {
            AgentLogo(vendor: vendor, size: side)
        }
    }

    private func picture(_ form: BotForm, side: CGFloat) -> CGImage? {
        var motion = BotMotion(seed: 11)
        motion.staysBot = phase == .idle
        motion.spin = form.spec.spin
        motion.set(phase, at: 0)
        var now: TimeInterval = 0
        // Looking a little down and aside, as at a pointer below the queue.
        while now <= seconds {
            motion.step(to: now, aim: CGPoint(x: 0.35, y: 0.45))
            now += 1.0 / 30
        }
        return BotRenderer.image(form, motion: motion, side: side * 2)
    }
}
#endif
