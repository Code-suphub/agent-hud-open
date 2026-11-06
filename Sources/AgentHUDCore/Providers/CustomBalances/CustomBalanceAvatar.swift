import Foundation

/// A small local avatar, shared by cards, menu marks and the existing bot-motion engine.
public struct CustomBalanceAvatar: Hashable, Codable, Sendable {
    public let revision: String
    public let emoji: String?
    public let imagePNG: Data?
    public var animated: Bool

    public init(emoji: String, animated: Bool = true) throws {
        guard !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, emoji.count <= 4, emoji.utf8.count <= 128 else { throw Self.invalid() }
        revision = UUID().uuidString; self.emoji = emoji; imagePNG = nil; self.animated = animated
    }
    public init(imagePNG: Data, animated: Bool = true) throws {
        guard imagePNG.count <= 524_288, imagePNG.starts(with: [137,80,78,71,13,10,26,10]) else { throw Self.invalid() }
        revision = UUID().uuidString; emoji = nil; self.imagePNG = imagePNG; self.animated = animated
    }
    private static func invalid() -> UsageProviderError {
        UsageProviderError(L10n.text("请选择有效图片或最多四个字符的 Emoji", "Choose a valid image or an emoji of up to four characters"))
    }
}
