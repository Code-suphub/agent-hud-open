import Foundation

/// What the agent says between its calls when the Claude desktop app asks its session for updates
/// (`thinkingDisplay: "updates"`): Claude Code writes it as a thinking block, and the block's signature names it a
/// narration. The app shows it as the agent's own words, beside its text blocks, and counts the two apart.
///
/// A block is told the way the app tells it (Claude desktop 2.42304): its signature, base64, holds a message whose field
/// 2 holds a message whose field 1 holds a message whose field 8 is the text `narration`. Any other thinking block,
/// and a signature that does not read that way, is the agent's reasoning.
public enum ClaudeNarration {
    public static func isNarration(signature: String) -> Bool { kind(ofSignature: signature) == "narration" }

    /// The kind a thinking block's signature names, such as `narration` or `thinking`; nil when it names none.
    public static func kind(ofSignature signature: String) -> String? {
        let padded = signature + String(repeating: "=", count: (4 - signature.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { return nil }
        let bytes = [UInt8](data)
        guard let outer = field(2, in: bytes[...]), let inner = field(1, in: outer), let kind = field(8, in: inner) else { return nil }
        return String(decoding: kind, as: UTF8.self)
    }

    /// The bytes of the last length-delimited field `number` of a protobuf message; nil when it has none, or when the
    /// message does not read to its end.
    static func field(_ number: UInt64, in message: ArraySlice<UInt8>) -> ArraySlice<UInt8>? {
        var index = message.startIndex, found: ArraySlice<UInt8>?
        func varint() -> UInt64? {
            var value: UInt64 = 0, shift: UInt64 = 0
            while index < message.endIndex, shift < 64 {
                let byte = message[index]
                index += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while index < message.endIndex {
            guard let key = varint() else { return nil }
            switch key & 7 {
            case 0:
                guard varint() != nil else { return nil }
            case 1, 5:
                let width = key & 7 == 1 ? 8 : 4
                guard message.endIndex - index >= width else { return nil }
                index += width
            case 2:
                guard let length = varint(), length <= UInt64(message.endIndex - index) else { return nil }
                let end = index + Int(length)
                if key >> 3 == number { found = message[index..<end] }
                index = end
            default:
                return nil
            }
        }
        return found
    }
}
