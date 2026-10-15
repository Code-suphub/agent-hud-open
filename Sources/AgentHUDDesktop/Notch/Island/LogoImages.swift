import AppKit
import CoreGraphics

/// One agent's mark, baked at the size it will be drawn with its outline already in the pixels.
///
/// The outline has to follow the artwork's own silhouette, which no border or single shadow can do for an
/// arbitrary mark. Stacking live shadows does it but costs an offscreen pass per direction per frame, and
/// the queue animates — so the ring is drawn once here instead, from the artwork's alpha, and the animating
/// layer ends up with nothing but a flat image to composite.
@MainActor
enum LogoImages {
    struct Key: Hashable {
        var vendor: String
        /// Side of the mark in device pixels, excluding the outline.
        var side: Int
        /// Outline thickness in device pixels. A hairline: one pixel reads as an edge, more as a border.
        var outline: Int
        /// Whether the mark is drawn for a light ground, the surface of a light HUD it stands on: the artwork
        /// variant made for a light background, for the vendors that ship one per background, and a single-colour
        /// mark in dark ink with a light outline. Otherwise a single-colour mark is drawn light with a dark outline,
        /// which reads on the island's black and on any wallpaper; the system's appearance says nothing about the
        /// contrast there, so only the HUD's own look, and whether a surface is behind the mark, choose this.
        var light: Bool
    }

    private struct Baked {
        let image: CGImage
        let visibleBounds: CGRect
    }

    private static var cache: [Key: Baked] = [:]

    static func image(_ key: Key) -> CGImage? { baked(key)?.image }

    /// The nontransparent pixels of the final bitmap, including the outline. Coordinates run down from
    /// its top-left corner and are normalized to the entire bitmap, including its outline canvas.
    /// A pixel occupies its full cell: the last visible pixel's outer edge is the rect's maximum.
    static func visibleBounds(_ key: Key) -> CGRect { baked(key)?.visibleBounds ?? .zero }

    private static func baked(_ key: Key) -> Baked? {
        if let hit = cache[key] { return hit }
        guard let image = render(key) else { return nil }
        let baked = Baked(image: image, visibleBounds: visibleBounds(in: image))
        if cache.count > 96 { cache.removeAll(keepingCapacity: true) }
        cache[key] = baked
        return baked
    }

    static func invalidate() { cache.removeAll(keepingCapacity: true) }

    private static func render(_ key: Key) -> CGImage? {
        guard key.side > 0,
              let artwork = AgentArtwork.original(for: key.vendor, light: key.light),
              let mark = cgImage(artwork)
        else { return nil }
        let outline = CGFloat(max(0, key.outline))
        let side = CGFloat(key.side)
        let canvas = Int((side + outline * 2).rounded())
        guard let context = CGContext(
            data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: outline, y: outline, width: side, height: side)

        // The ring is built opaque in its own bitmap and composited once. Drawing the eight offsets straight
        // into this context would let them accumulate where they overlap, which is most of the ring, and the
        // outline would come out near black however low each pass was set.
        if outline > 0, let ring = ring(mark: mark, rect: rect, thickness: outline, canvas: canvas, light: key.light) {
            context.saveGState()
            context.setAlpha(Self.outlineOpacity)
            context.draw(ring, in: CGRect(x: 0, y: 0, width: CGFloat(canvas), height: CGFloat(canvas)))
            context.restoreGState()
        }

        if AgentArtwork.isTemplate(key.vendor) {
            // A single-colour mark carries no colour of its own; it is drawn as a stencil in the ground's ink, white
            // or dark, with the outline above doing the work on a wallpaper of the same lightness.
            context.saveGState()
            context.clip(to: rect, mask: mark)
            context.setFillColor(key.light ? BotForm.ink(on: .light) : NSColor.white.cgColor)
            context.fill(rect)
            context.restoreGState()
        } else {
            context.draw(mark, in: rect)
        }
        return context.makeImage()
    }

    private static func visibleBounds(in image: CGImage) -> CGRect {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return .zero }
        let width = image.width, height = image.height, stride = image.bytesPerRow
        var minX = width, minY = height, maxX = -1, maxY = -1
        // render makes RGBA pixels. Read the CGImage's raster rows, whose first row is the visual top;
        // these are image coordinates, rather than the bitmap context's upward-running drawing space.
        for y in 0..<height {
            for x in 0..<width where bytes[y * stride + x * 4 + 3] > 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return .zero }
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width),
                      height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }

    /// How strong the finished outline is. Enough to separate a white mark from a pale wallpaper, or a dark one
    /// from a dark wallpaper, not enough to read as a border drawn around it.
    static let outlineOpacity: CGFloat = 0.5
    /// Passes over the ring. Smearing an anti-aliased silhouette leaves a soft edge however thin the offset
    /// is; drawing it again drives the half-covered pixels to opaque, which is what makes the line crisp
    /// rather than a haze around the mark.
    private static let outlinePasses = 3

    /// The eight neighbouring pixels. Offsets taken around a circle instead put the diagonals at 0.707 of a
    /// pixel, which lands off the grid and is resampled into a grey fringe — the thing that makes a hairline
    /// look thick and soft however thin it is asked to be.
    private static let neighbours: [(x: CGFloat, y: CGFloat)] = [
        (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1),
    ]

    /// The mark's silhouette spread one pixel in every direction, with the mark itself knocked back out of
    /// it. Without that the ring survives under the mark's own half-transparent edge and shows through it,
    /// which reads as a thick muddy border rather than an edge. It is black round a mark for a dark ground and
    /// white round one for a light ground.
    private static func ring(mark: CGImage, rect: CGRect, thickness: CGFloat, canvas: Int, light: Bool) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setFillColor(light ? NSColor.white.cgColor : NSColor.black.cgColor)
        for _ in 0..<outlinePasses {
            for offset in neighbours {
                let shifted = rect.offsetBy(dx: offset.x * thickness, dy: offset.y * thickness)
                context.saveGState()
                context.clip(to: shifted, mask: mark)
                context.fill(shifted)
                context.restoreGState()
            }
        }
        context.setBlendMode(.destinationOut)
        context.draw(mark, in: rect)
        return context.makeImage()
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
