import AppKit
import AVFoundation
import CoreVideo

/// Records the HUD's own windows on one display, and nothing else that is on screen, to a movie whose background is
/// transparent, so a take can be laid over any desktop in an editor.
///
/// Frames are drawn in this process from the windows' layers as they are being shown, animations in flight included.
/// Nothing is read back from the screen, so no screen recording permission is involved and no other window can end
/// up in the picture.
@MainActor
final class HUDRecorder {
    struct Options: Equatable {
        var url: URL
        /// Stop, finish the file and quit after this long; without it the recording ends when the app quits.
        var seconds: TimeInterval?
        var framesPerSecond = 60
        /// The part of the display to record, in points from its top left; nil is the whole display.
        var region: CGRect?

        /// `x,y,width,height` in points from the display's top left.
        static func region(_ text: String) -> CGRect? {
            let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
            return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
    }

    enum Failure: Error { case noDisplay, cannotWrite(String) }

    /// One window to draw. A window much larger than what it shows, as the glow's is, says where its picture can
    /// be, in global screen coordinates: drawing a whole display of mostly nothing costs most of a frame's time.
    struct Source {
        var window: NSWindow
        var bounds: CGRect?
    }

    private let options: Options
    /// The windows to draw, back to front, asked for at every frame: a HUD's windows move and are replaced.
    private let sources: @MainActor () -> [Source]
    /// The recorded area in global screen coordinates, which run up from the bottom left of the main display.
    private let area: CGRect
    private let scale: CGFloat
    private let size: (width: Int, height: Int)
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var timer: Timer?
    private var startedAt: CFTimeInterval = 0
    private(set) var frames = 0
    /// Frames the encoder was not ready for, and the seconds spent drawing the ones it took.
    private(set) var skipped = 0
    private var drawing: CFTimeInterval = 0
    private var finished = false
    /// Called once the file is complete after `seconds` have passed.
    var onFinish: (@MainActor () -> Void)?

    init(options: Options, screen: NSScreen, sources: @escaping @MainActor () -> [Source]) throws {
        self.options = options
        self.sources = sources
        let scale = screen.backingScaleFactor
        self.scale = scale
        let frame = screen.frame
        let region = (options.region ?? CGRect(origin: .zero, size: frame.size))
            .intersection(CGRect(origin: .zero, size: frame.size))
        guard !region.isEmpty else { throw Failure.noDisplay }
        area = CGRect(x: frame.minX + region.minX, y: frame.maxY - region.maxY, width: region.width, height: region.height)
        // Video codecs want even dimensions.
        let even = { (points: CGFloat) in Int((points * scale / 2).rounded(.up)) * 2 }
        let size = (width: even(region.width), height: even(region.height))
        self.size = size

        try? FileManager.default.removeItem(at: options.url)
        try FileManager.default.createDirectory(at: options.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        writer = try AVAssetWriter(outputURL: options.url, fileType: .mov)
        // ProRes 4444 keeps the alpha channel, and editors read it without conversion.
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(input) else { throw Failure.cannotWrite("The movie cannot hold this picture size") }
        writer.add(input)
    }

    func start() throws {
        guard writer.startWriting() else { throw Failure.cannotWrite(writer.error?.localizedDescription ?? "unknown") }
        writer.startSession(atSourceTime: .zero)
        startedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / Double(max(1, options.framesPerSecond)), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common modes, so frames keep coming while the HUD is dragged or a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - startedAt
        if let seconds = options.seconds, elapsed >= seconds {
            finish { [weak self] in self?.onFinish?() }
            return
        }
        capture(at: elapsed)
    }

    /// Draws the windows as they look now into one frame. A frame the encoder is not ready for is skipped; the next
    /// one carries its own time, so the movie keeps real speed.
    private func capture(at elapsed: CFTimeInterval) {
        guard !finished, let pool = adaptor.pixelBufferPool else { return }
        guard input.isReadyForMoreMediaData else { return skipped += 1 }
        let began = CACurrentMediaTime()
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        draw(in: context)
        drawing += CACurrentMediaTime() - began
        if adaptor.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 600)) { frames += 1 }
    }

    /// One frame as a picture, for looking at what a recording would hold.
    func snapshot() -> CGImage? {
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        draw(in: context)
        return context.makeImage()
    }

    private func draw(in context: CGContext) {
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.scaleBy(x: scale, y: scale)
        for source in sources() where source.window.isVisible && source.window.alphaValue > 0 {
            let window = source.window
            let visible = (source.bounds ?? window.frame).intersection(window.frame).intersection(area)
            guard let view = window.contentView, let layer = view.layer, !visible.isEmpty else { continue }
            context.saveGState()
            context.clip(to: visible.offsetBy(dx: -area.minX, dy: -area.minY))
            context.translateBy(x: window.frame.minX - area.minX, y: window.frame.minY - area.minY)
            context.setAlpha(window.alphaValue)
            // A layer draws itself in its own coordinates. Those of a flipped view run down from its top.
            if layer.isGeometryFlipped {
                context.translateBy(x: 0, y: window.frame.height)
                context.scaleBy(x: 1, y: -1)
            }
            // The presentation copy carries the values of animations in flight, such as the glow's breath.
            (layer.presentation() ?? layer).render(in: context)
            context.restoreGState()
        }
    }

    private func report() {
        let each = frames > 0 ? drawing / Double(frames) * 1000 : 0
        NSLog("[AgentHUD] Recorded %d frames to %@ (%d skipped while the encoder was busy, %.1f ms to draw each)",
              frames, options.url.path, skipped, each)
    }

    /// Ends the recording and completes the file.
    func finish(_ completion: (@MainActor () -> Void)? = nil) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        timer = nil
        input.markAsFinished()
        report()
        writer.finishWriting { Task { @MainActor in completion?() } }
    }

    /// The same, waiting for the file to be complete: for the moment the app quits.
    func finishAndWait(upTo seconds: TimeInterval = 10) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        timer = nil
        input.markAsFinished()
        report()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + seconds)
    }
}
