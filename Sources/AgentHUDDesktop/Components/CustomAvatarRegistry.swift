import AppKit
import ImageIO
import Observation
import AgentHUDCore

@MainActor @Observable
final class CustomAvatarRegistry {
    static let shared = CustomAvatarRegistry()
    private(set) var avatars: [String: CustomBalanceAvatar] = [:]
    private(set) var revision = 0
    @ObservationIgnored private var images: [String: NSImage] = [:]

    func sync(_ profiles: [CustomBalanceProfile]) {
        let next = Dictionary(profiles.compactMap { profile -> (String, CustomBalanceAvatar)? in
            guard let avatar = profile.avatar, AgentArtwork.fileNames[AgentArtwork.markKey(profile.name)] == nil else { return nil }
            return (profile.name, avatar)
        }, uniquingKeysWith: { first, _ in first })
        guard next != avatars else { return }
        avatars = next; images = [:]; revision &+= 1
        LogoImages.invalidate()
        BotForm.invalidate()
        AgentArtwork.invalidateAccents()
    }

    func image(for vendor: String) -> NSImage? {
        guard let avatar = avatars[vendor] else { return nil }
        if let image = images[vendor] { return image }
        let image = Self.render(avatar)
        if let image { image.isTemplate = false; images[vendor] = image }
        return image
    }

    static func render(_ avatar: CustomBalanceAvatar) -> NSImage? {
        let image: NSImage?
        if let png = avatar.imagePNG { image = Self.image(png) }
        else if let emoji = avatar.emoji {
            image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
                let initial = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 190)])
                let fontSize = 190 * min(1, 236 / max(1, initial.size().width))
                let string = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
                let size = string.size()
                string.draw(at: NSPoint(x: (256 - size.width) / 2, y: (256 - size.height) / 2))
                return true
            }
        } else { image = nil }
        return image
    }

    static func image(_ data: Data) -> NSImage? {
        guard data.count <= 10_485_760, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func normalizedPNG(_ data: Data) throws -> Data {
        guard let image = image(data), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw UsageProviderError(L10n.text("无法读取这张图片，请选择 PNG、JPEG 或 WebP", "Cannot read this image; choose PNG, JPEG or WebP"))
        }
        return png
    }
}
