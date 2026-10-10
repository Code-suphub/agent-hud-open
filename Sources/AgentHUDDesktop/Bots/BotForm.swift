import AppKit
import AgentHUDCore
import CoreGraphics

/// Everything a bot needs from its mark's artwork, read once: the artwork in light ink, how far it reaches
/// from the body's centre in every direction, the body's own reach, and the mark's colours as a soft field.
///
/// The morph is the first outline relaxing into the second while the artwork fades into the field, which is
/// why both outlines are taken as reach per degree from one centre: any two can be blended angle by angle.
@MainActor
final class BotForm {
    /// Samples round the body, one per degree.
    static let samples = 360
    /// Side of the bitmap the artwork is read at.
    private static let grain = 256

    let vendor: String
    let spec: BotSpec
    let artwork: CGImage
    /// The artwork with its own eyes taken out, for a mark that keeps its artwork and animates them.
    let stripped: CGImage?
    let logoReach: [CGFloat]
    let bodyReach: [CGFloat]
    let field: CGImage?

    private static var cache: [String: BotForm?] = [:]

    static func form(for vendor: String) -> BotForm? {
        let key = AgentArtwork.markKey(vendor)
        if let hit = cache[key] { return hit }
        let form = BotSpec.spec(for: vendor).flatMap { BotForm(vendor: vendor, spec: $0) }
        cache[key] = form
        return form
    }

    private init?(vendor: String, spec: BotSpec) {
        guard let artwork = Self.lightArtwork(for: vendor), let pixels = Self.pixels(of: artwork) else { return nil }
        self.vendor = vendor
        self.spec = spec
        self.artwork = artwork
        logoReach = Self.reach(alphaOf: pixels, from: spec.center)
        bodyReach = Self.bodyReach(spec, logo: logoReach)
        field = Self.colorField(pixels, skipping: spec.unpainted)
        stripped = spec.ownEyes.flatMap { Self.strip($0, from: artwork) }
    }

    // MARK: Artwork

    /// The dark-surface artwork at a fixed size. A single-colour mark carries no colour of its own and is
    /// drawn as a white stencil, the way the logo queue draws it.
    private static func lightArtwork(for vendor: String) -> CGImage? {
        guard let image = AgentArtwork.original(for: vendor, light: false) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let mark = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = bitmap(grain) else { return nil }
        let box = CGRect(x: 0, y: 0, width: grain, height: grain)
        context.interpolationQuality = .high
        if AgentArtwork.isTemplate(vendor) {
            context.clip(to: box, mask: mark)
            context.setFillColor(.white)
            context.fill(box)
        } else {
            context.draw(mark, in: box)
        }
        return context.makeImage()
    }

    private static func strip(_ eyes: [CGRect], from artwork: CGImage) -> CGImage? {
        guard let context = bitmap(grain) else { return nil }
        let side = CGFloat(grain)
        context.draw(artwork, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Bitmap rows run bottom up; the boxes are measured from the top.
        for eye in eyes {
            context.clear(CGRect(x: eye.minX * side, y: (1 - eye.maxY) * side,
                                 width: eye.width * side, height: eye.height * side).insetBy(dx: -3, dy: -3))
        }
        return context.makeImage()
    }

    static func bitmap(_ side: Int) -> CGContext? {
        CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Premultiplied RGBA, top row first.
    private static func pixels(of image: CGImage) -> [UInt8]? {
        guard let context = bitmap(grain) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: grain, height: grain))
        guard let data = context.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: grain * grain * 4))
    }

    // MARK: Outlines

    /// How far the opaque pixels reach from `center`, per degree, as a share of the side.
    private static func reach(alphaOf pixels: [UInt8], from center: CGPoint) -> [CGFloat] {
        let side = CGFloat(grain)
        return (0..<samples).map { index in
            let angle = CGFloat(index) * 2 * .pi / CGFloat(samples), dx = cos(angle), dy = sin(angle)
            var last: CGFloat = 0, distance: CGFloat = 0
            while distance < side * 1.5 {
                let x = Int((center.x * side + dx * distance).rounded()), y = Int((center.y * side + dy * distance).rounded())
                if x < 0 || y < 0 || x >= grain || y >= grain { break }
                if pixels[(y * grain + x) * 4 + 3] > 127 { last = distance }
                distance += 0.5
            }
            return max(0.02, last / side)
        }
    }

    private static func smoothed(_ ring: [CGFloat], over width: Int) -> [CGFloat] {
        var current = ring
        let count = ring.count
        for _ in 0..<2 {
            current = (0..<count).map { index in
                var sum: CGFloat = 0
                for offset in -width...width { sum += current[(index + offset + count) % count] }
                return sum / CGFloat(2 * width + 1)
            }
        }
        return current
    }

    private static func bodyReach(_ spec: BotSpec, logo: [CGFloat]) -> [CGFloat] {
        let radius = spec.radius, center = spec.center
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: center.x + u * radius, y: center.y + v * radius) }
        switch spec.shape {
        case .circle:
            return Array(repeating: radius, count: samples)
        case .outline(let keep, let smooth):
            let soft = smoothed(logo, over: smooth), mean = soft.reduce(0, +) / CGFloat(soft.count)
            return soft.map { max(radius * 0.55, radius * (1 + keep * ($0 / mean - 1))) }
        case .star(let points, let depth, let puff):
            return (0..<samples).map { index in
                let turn = CGFloat(points) * CGFloat(index) * 2 * .pi / CGFloat(samples)
                // A smooth wave is a thin star. Broad round heads with a crease between them read as plump.
                let wave = puff < 1 ? 2 * pow(abs(cos(turn / 2)), puff) - 1 : cos(turn)
                return radius * (1 + depth * wave)
            }
        case .polygon(let sides, let rotation, let round):
            let corners = (0..<sides).map { index -> CGPoint in
                let angle = (rotation + CGFloat(index) * 360 / CGFloat(sides)) * .pi / 180
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
            return traced(from: center) { $0.addPath(rounded(corners, radius: round)); $0.fillPath() }
        case .rect(let width, let height, let round):
            let w = width / 2, h = height / 2
            let corners = [CGPoint(x: center.x - w, y: center.y - h), CGPoint(x: center.x + w, y: center.y - h),
                           CGPoint(x: center.x + w, y: center.y + h), CGPoint(x: center.x - w, y: center.y + h)]
            return traced(from: center) { $0.addPath(rounded(corners, radius: round)); $0.fillPath() }
        case .slant(let width, let height, let skew, let round):
            let w = width / 2, h = height / 2, lean = skew / 2
            let corners = [CGPoint(x: center.x - w + lean, y: center.y - h), CGPoint(x: center.x + w + lean, y: center.y - h),
                           CGPoint(x: center.x + w - lean, y: center.y + h), CGPoint(x: center.x - w - lean, y: center.y + h)]
            return traced(from: center) { $0.addPath(rounded(corners, radius: round)); $0.fillPath() }
        case .cat:
            return traced(from: center) { context in
                context.fillEllipse(in: CGRect(x: center.x - 1.02 * radius, y: center.y + (0.1 - 0.88) * radius,
                                               width: 2.04 * radius, height: 1.76 * radius))
                // A round join on a thick stroke is what softens the ear tips.
                context.setLineJoin(.round)
                context.setLineWidth(0.16 * radius)
                for side in [-1.0, 1.0] as [CGFloat] {
                    let ear = CGMutablePath()
                    ear.move(to: at(side * 0.94, -0.02))
                    ear.addLine(to: at(side * 0.78, -1.04))
                    ear.addLine(to: at(side * 0.16, -0.6))
                    ear.closeSubpath()
                    context.addPath(ear)
                    context.drawPath(using: .fillStroke)
                }
            }
        case .bob:
            return traced(from: center) { context in
                let path = CGMutablePath()
                path.move(to: at(-1.14, 0.98))
                path.addQuadCurve(to: at(-0.98, 0.3), control: at(-0.92, 0.72))
                // The dome: half an ellipse over the top, from the left temple to the right.
                for step in 0...48 {
                    let angle = CGFloat.pi + CGFloat(step) / 48 * .pi
                    path.addLine(to: at(0.98 * cos(angle), -0.08 + 0.96 * sin(angle)))
                }
                path.addLine(to: at(0.98, 0.3))
                path.addQuadCurve(to: at(1.14, 0.98), control: at(0.92, 0.72))
                path.addLine(to: at(0.62, 0.9))
                path.addQuadCurve(to: at(-0.62, 0.9), control: at(0, 1.06))
                path.closeSubpath()
                context.addPath(path)
                context.fillPath()
            }
        }
    }

    /// Draws a shape in shares of the side, top left origin, and reads its reach back.
    private static func traced(from center: CGPoint, _ draw: (CGContext) -> Void) -> [CGFloat] {
        guard let context = bitmap(grain) else { return Array(repeating: 0.3, count: samples) }
        context.translateBy(x: 0, y: CGFloat(grain))
        context.scaleBy(x: CGFloat(grain), y: -CGFloat(grain))
        context.setFillColor(.white)
        context.setStrokeColor(.white)
        draw(context)
        guard let data = context.data else { return Array(repeating: 0.3, count: samples) }
        let pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: grain * grain * 4))
        return reach(alphaOf: pixels, from: center)
    }

    private static func rounded(_ corners: [CGPoint], radius: CGFloat) -> CGPath {
        let path = CGMutablePath(), count = corners.count
        func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: middle(corners[count - 1], corners[0]))
        for index in 0..<count {
            let next = middle(corners[index], corners[(index + 1) % count])
            path.addArc(tangent1End: corners[index], tangent2End: next, radius: radius)
            path.addLine(to: next)
        }
        path.closeSubpath()
        return path
    }

    // MARK: Colour

    /// The mark's colours spread into a field a quarter-side wider than the mark, so a body cut from it
    /// carries each colour where the mark had it, with nothing transparent inside.
    private static func colorField(_ pixels: [UInt8], skipping holes: [CGRect]) -> CGImage? {
        let side = 60, margin = 10, inner = side - 2 * margin, count = side * side
        var known = [Bool](repeating: false, count: count)
        var colour = [Float](repeating: 0, count: count * 3)
        for y in 0..<inner {
            for x in 0..<inner {
                let row = Int((Double(y) + 0.5) * Double(grain) / Double(inner)), column = Int((Double(x) + 0.5) * Double(grain) / Double(inner))
                let source = (row * grain + column) * 4
                let alpha = Float(pixels[source + 3])
                let place = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(inner), y: (CGFloat(y) + 0.5) / CGFloat(inner))
                guard alpha > 200, !holes.contains(where: { $0.contains(place) }) else { continue }
                let index = (y + margin) * side + x + margin
                known[index] = true
                for channel in 0..<3 { colour[index * 3 + channel] = Float(pixels[source + channel]) / alpha * 255 }
            }
        }
        guard known.contains(true) else { return nil }
        func around(_ index: Int, _ visit: (Int) -> Void) {
            let x = index % side, y = index / side
            for dy in -1...1 {
                for dx in -1...1 where x + dx >= 0 && y + dy >= 0 && x + dx < side && y + dy < side {
                    visit((y + dy) * side + x + dx)
                }
            }
        }
        // Colour grows outwards a ring at a time, each ring the average of what it touches.
        for _ in 0..<(side * 2) {
            var ring: [(Int, Float, Float, Float)] = []
            for index in 0..<count where !known[index] {
                var red: Float = 0, green: Float = 0, blue: Float = 0, hits: Float = 0
                around(index) { other in
                    guard known[other] else { return }
                    red += colour[other * 3]; green += colour[other * 3 + 1]; blue += colour[other * 3 + 2]; hits += 1
                }
                if hits > 0 { ring.append((index, red / hits, green / hits, blue / hits)) }
            }
            if ring.isEmpty { break }
            for (index, red, green, blue) in ring {
                colour[index * 3] = red; colour[index * 3 + 1] = green; colour[index * 3 + 2] = blue
                known[index] = true
            }
        }
        for _ in 0..<2 {
            var next = colour
            for index in 0..<count {
                var red: Float = 0, green: Float = 0, blue: Float = 0, hits: Float = 0
                around(index) { other in
                    red += colour[other * 3]; green += colour[other * 3 + 1]; blue += colour[other * 3 + 2]; hits += 1
                }
                next[index * 3] = red / hits; next[index * 3 + 1] = green / hits; next[index * 3 + 2] = blue / hits
            }
            colour = next
        }
        guard let context = bitmap(side), let data = context.data else { return nil }
        let out = data.assumingMemoryBound(to: UInt8.self)
        for index in 0..<count {
            for channel in 0..<3 { out[index * 4 + channel] = UInt8(max(0, min(255, colour[index * 3 + channel]))) }
            out[index * 4 + 3] = 255
        }
        return context.makeImage()
    }
}
