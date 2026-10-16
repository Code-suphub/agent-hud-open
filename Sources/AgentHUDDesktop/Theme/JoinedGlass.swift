import SwiftUI

/// Liquid Glass in several pieces that join into one where they meet: the Simple panel and the line that grows out of
/// it. Two pieces of glass drawn side by side each light a rim, and the panel's lights a bright band down the line's end
/// where the two meet; drawn in one `GlassEffectContainer` they are one piece of glass with a smooth fillet between
/// them, which follows the line as it grows and shrinks. The container holds the pieces (`hudGlassPiece(in:shown:)`)
/// and nothing else: what else it held it would blur as if it were the desktop. The dimming beneath the glass is the
/// caller's, outside it. Where glass is not Liquid Glass it draws nothing; its callers draw `HUDSurface` there.
struct JoinedGlass<Content: View>: View {
    let look: HUDLook
    /// How near two pieces come before they flow together.
    var spacing: CGFloat = JoinedGlassMetrics.spacing
    @ViewBuilder let content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
                .environment(\.colorScheme, look.colorScheme)
        }
        #endif
    }
}

enum JoinedGlassMetrics {
    /// Enough for the line, which tucks under the panel, to flow into it with a soft fillet. A full card, 6 points off
    /// its dock, would flow into the panel at this spacing as well, so none is ever put in the container: it stays a
    /// piece of its own (`HUDSurface`).
    static let spacing: CGFloat = 10
}

extension View {
    /// One piece of a `JoinedGlass`: the clear glass in `shape`, as `HUDSurface` draws it, or no glass at all while not
    /// `shown`, which keeps the piece in its place so that it can come back.
    @ViewBuilder
    func hudGlassPiece<S: Shape>(in shape: S, shown: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(shown ? .clear : .identity, in: shape)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
