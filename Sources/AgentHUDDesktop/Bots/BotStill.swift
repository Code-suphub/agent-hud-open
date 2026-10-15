import CoreGraphics
import Foundation

/// The still part of a bot's frame, kept as the bitmap's own bytes: the body, its paint and what it wears, which
/// only the morph and the turn change. A bot that does not spin draws them once it has turned into its bot and,
/// for every blink and glance after that, starts its frame from a copy. Copied bytes are the bytes drawing them
/// would have made, so the frame comes out the same.
@MainActor
struct BotStill {
    let form: BotForm
    let morph: CGFloat
    let turn: CGFloat
    /// The cleared bitmap the frame is drawn in. Its size, colours and transform are part of what is kept.
    let context: CGContext

    init(form: BotForm, morph: CGFloat, turn: CGFloat, on context: CGContext) {
        self.form = form
        self.morph = morph
        self.turn = turn
        self.context = context
    }

    /// One bot's still part on one kind of bitmap. Two queues showing the same bot at the same size share it.
    @MainActor
    private final class Slot {
        let form: BotForm
        let width: Int
        let space: CGColorSpace?
        let transform: CGAffineTransform
        var morph: CGFloat
        var turn: CGFloat
        var bytes: [UInt8]

        init(_ still: BotStill, bytes: [UInt8]) {
            form = still.form
            width = still.context.width
            space = still.context.colorSpace
            transform = still.context.ctm
            morph = still.morph
            turn = still.turn
            self.bytes = bytes
        }
    }

    private static var slots: [Slot] = []
    /// Two queues of every bot there is; more than that and the marks are being resized.
    private static let most = 24

    private var slot: Slot? {
        Self.slots.first {
            $0.form === form && $0.width == context.width && $0.space == context.colorSpace && $0.transform == context.ctm
        }
    }

    private var size: Int { context.bytesPerRow * context.height }

    /// Copies the kept part into the bitmap, when one was kept for this moment of the morph and the turn.
    func restore() -> Bool {
        guard let slot, slot.morph == morph, slot.turn == turn, slot.bytes.count == size, let data = context.data
        else { return false }
        slot.bytes.withUnsafeBytes { _ = memcpy(data, $0.baseAddress!, $0.count) }
        return true
    }

    /// Keeps what the bitmap holds now as the still part for this moment.
    func keep() {
        guard let data = context.data else { return }
        if let slot, slot.bytes.count == size {
            slot.morph = morph
            slot.turn = turn
            slot.bytes.withUnsafeMutableBytes { _ = memcpy($0.baseAddress!, data, $0.count) }
            return
        }
        if Self.slots.count >= Self.most { Self.slots.removeFirst() }
        Self.slots.append(Slot(self, bytes: [UInt8](UnsafeRawBufferPointer(start: data, count: size))))
    }

    /// Lets every kept part go, so the next frame of every bot is drawn whole.
    static func forget() { slots = [] }
}
