@preconcurrency import AppKit
@preconcurrency import AVFoundation
import CoreImage

final class OverlayCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let screenTrackID: CMPersistentTrackID
    let webcamTrackID: CMPersistentTrackID?
    let timeline: OverlayTimeline
    let layout: OverlayCompositionLayout

    init(timeRange: CMTimeRange, screenTrackID: CMPersistentTrackID, webcamTrackID: CMPersistentTrackID?, timeline: OverlayTimeline, layout: OverlayCompositionLayout) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.webcamTrackID = webcamTrackID
        self.timeline = timeline
        self.layout = layout
        requiredSourceTrackIDs = ([screenTrackID] + [webcamTrackID].compactMap(\.self)).map { NSNumber(value: $0) }
    }
}

final class OverlayVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]

    private let queue = DispatchQueue(label: "dev.adrian.ishare.OverlayVideoCompositor")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let renderer = OverlayImageRenderer()

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            guard let instruction = request.videoCompositionInstruction as? OverlayCompositionInstruction,
                  let screen = request.sourceFrame(byTrackID: instruction.screenTrackID),
                  let output = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: VideoTrimError.exportUnavailable)
                return
            }
            let webcam = instruction.webcamTrackID.flatMap { request.sourceFrame(byTrackID: $0) }
            let image = renderer.compose(
                screen: CIImage(cvPixelBuffer: screen),
                webcam: webcam.map { CIImage(cvPixelBuffer: $0) },
                time: request.compositionTime.seconds,
                timeline: instruction.timeline,
                layout: instruction.layout
            )
            context.render(image, to: output, bounds: CGRect(origin: .zero, size: instruction.layout.videoSize), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            request.finish(withComposedVideoFrame: output)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

final class OverlayImageRenderer: @unchecked Sendable {
    private var badgeCache: [String: CIImage] = [:]
    private var ringCache: [CGFloat: CIImage] = [:]

    func compose(screen: CIImage, webcam: CIImage?, time: Double, timeline: OverlayTimeline, layout: OverlayCompositionLayout) -> CIImage {
        var image = screen
        if let webcam, let frame = layout.webcamFrame {
            image = bubble(from: webcam, in: frame).composited(over: image)
            image = ring(diameter: frame.width, scale: layout.pixelsPerPoint).transformed(by: CGAffineTransform(translationX: frame.minX, y: frame.minY)).composited(over: image)
        }
        for ripple in timeline.ripples(at: time) {
            let point = OverlayCoordinateMapper.flipped(ripple.point, videoHeight: layout.videoSize.height)
            image = rippleImage(progress: ripple.progress, at: point, scale: layout.pixelsPerPoint).composited(over: image)
        }
        if let text = timeline.keystroke(at: time) {
            let badge = badgeImage(text, scale: layout.pixelsPerPoint)
            let center = layout.keystrokeCenter()
            let origin = CGPoint(x: center.x - badge.extent.width / 2, y: center.y - badge.extent.height / 2)
            image = badge.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y)).composited(over: image)
        }
        return image.cropped(to: CGRect(origin: .zero, size: layout.videoSize))
    }

    private func bubble(from webcam: CIImage, in frame: CGRect) -> CIImage {
        let extent = webcam.extent
        guard extent.width > 0, extent.height > 0 else { return CIImage.empty() }
        let side = frame.width
        let scale = max(side / extent.width, side / extent.height)
        let mirrored = webcam
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: -scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: extent.width * scale, y: 0))
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let cropped = mirrored
            .cropped(to: CGRect(x: (scaledWidth - side) / 2, y: (scaledHeight - side) / 2, width: side, height: side))
            .transformed(by: CGAffineTransform(translationX: -(scaledWidth - side) / 2 + frame.minX, y: -(scaledHeight - side) / 2 + frame.minY))
        let radius = side / 2
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: frame.midX, y: frame.midY),
            "inputRadius0": max(0, radius - 1),
            "inputRadius1": radius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.clear,
        ])?.outputImage?.cropped(to: frame) ?? CIImage.empty()
        let background = CIImage(color: .black).cropped(to: frame)
        return cropped.composited(over: background).applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
    }

    private func ring(diameter: CGFloat, scale: CGFloat) -> CIImage {
        if let cached = ringCache[diameter] { return cached }
        let lineWidth = 3 * scale
        let image = Self.draw(size: CGSize(width: diameter, height: diameter)) { context in
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter).insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
        ringCache[diameter] = image
        return image
    }

    private func rippleImage(progress: Double, at point: CGPoint, scale: CGFloat) -> CIImage {
        let eased = 1 - pow(1 - progress, 3)
        let diameter = 46 * scale * CGFloat(0.45 + 1.05 * eased)
        let alpha = CGFloat(1 - eased)
        let lineWidth = 3 * scale
        let canvas = ceil(diameter + lineWidth * 2)
        let image = Self.draw(size: CGSize(width: canvas, height: canvas)) { context in
            let circle = CGRect(x: (canvas - diameter) / 2, y: (canvas - diameter) / 2, width: diameter, height: diameter)
            context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.28 * alpha).cgColor)
            context.fillEllipse(in: circle)
            context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: circle.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
        return image.transformed(by: CGAffineTransform(translationX: point.x - canvas / 2, y: point.y - canvas / 2))
    }

    private func badgeImage(_ text: String, scale: CGFloat) -> CIImage {
        if let cached = badgeCache[text] { return cached }
        let font = NSFont.systemFont(ofSize: 30 * scale, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
        let attributed = NSAttributedString(string: text, attributes: [.font: rounded, .foregroundColor: NSColor.white])
        let textSize = attributed.size()
        let size = CGSize(width: ceil(textSize.width + 36 * scale), height: ceil(textSize.height + 20 * scale))
        let image = Self.draw(size: size) { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = CGPath(roundedRect: rect.insetBy(dx: 0.5 * scale, dy: 0.5 * scale), cornerWidth: 14 * scale, cornerHeight: 14 * scale, transform: nil)
            context.addPath(path)
            context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(scale)
            context.strokePath()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            attributed.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
        if badgeCache.count > 64 { badgeCache.removeAll() }
        badgeCache[text] = image
        return image
    }

    private static func draw(size: CGSize, _ body: (CGContext) -> Void) -> CIImage {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return CIImage.empty() }
        body(context)
        guard let image = context.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: image)
    }
}

enum OverlayCompositor {
    static func composite(_ url: URL, capture: OverlayCapture, recordingStart: Double, hevc: Bool, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: url)
        guard let screenTrack = try await asset.loadTracks(withMediaType: .video).first else { throw RecordingExportError.noVideoTrack }
        let duration = try await asset.load(.duration)
        let videoSize = try await screenTrack.load(.naturalSize)
        let webcamClip = capture.webcam.map { OverlayWebcamClip(url: $0.url, offset: $0.startTime - recordingStart) }
        let timeline = capture.log.timeline(recordingStart: recordingStart, videoSize: videoSize, webcam: webcamClip, duration: duration.seconds)
        guard !timeline.isEmpty else { return }
        let layout = OverlayCompositionLayout.make(
            videoSize: videoSize,
            sourceSize: capture.contentSize,
            webcamDiameter: webcamClip == nil ? nil : capture.webcamDiameter,
            corner: capture.webcamCorner
        )
        try await composite(asset, screenTrack: screenTrack, duration: duration, timeline: timeline, layout: layout, replacing: url, hevc: hevc, progress: progress)
    }

    static func composite(_ asset: AVAsset, screenTrack: AVAssetTrack, duration: CMTime, timeline: OverlayTimeline, layout: OverlayCompositionLayout, replacing url: URL, hevc: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        guard let screen = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoTrimError.exportUnavailable }
        try screen.insertTimeRange(fullRange, of: screenTrack, at: .zero)
        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try audio?.insertTimeRange(fullRange, of: audioTrack, at: .zero)
        }
        let webcamTrackID = try await insertWebcam(timeline.webcam, into: composition, duration: duration)

        let frameRate = try await screenTrack.load(.nominalFrameRate)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = OverlayVideoCompositor.self
        videoComposition.renderSize = layout.videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 1 ? frameRate.rounded() : 60))
        videoComposition.instructions = [OverlayCompositionInstruction(
            timeRange: fullRange,
            screenTrackID: screen.trackID,
            webcamTrackID: webcamTrackID,
            timeline: timeline,
            layout: layout
        )]
        try await VideoCompositionExporter.export(composition, videoComposition: videoComposition, replacing: url, hevc: hevc, progress: progress)
    }

    private static func insertWebcam(_ clip: OverlayWebcamClip?, into composition: AVMutableComposition, duration: CMTime) async throws -> CMPersistentTrackID? {
        guard let clip else { return nil }
        let webcamAsset = AVURLAsset(url: clip.url)
        guard let webcamTrack = try await webcamAsset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let webcamDuration = try await webcamAsset.load(.duration).seconds
        let sourceStart = max(0, -clip.offset)
        let destinationStart = max(0, clip.offset)
        let length = min(webcamDuration - sourceStart, duration.seconds - destinationStart)
        guard length > 0 else {
            composition.removeTrack(track)
            return nil
        }
        let range = CMTimeRange(start: CMTime(seconds: sourceStart, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600))
        try track.insertTimeRange(range, of: webcamTrack, at: CMTime(seconds: destinationStart, preferredTimescale: 600))
        return track.trackID
    }
}
