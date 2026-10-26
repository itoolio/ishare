import AVFoundation
import CoreImage
import Defaults
import Foundation
import ishareCore
import Vision

extension BlurRegionStyle: Defaults.Serializable {
    var title: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }
}

enum BlurRegionRenderer {
    static func pixelRect(for normalized: CGRect, videoSize: CGSize) -> CGRect {
        let flipped = RegionGeometry.flippedVertically(normalized)
        return CGRect(x: flipped.minX * videoSize.width, y: flipped.minY * videoSize.height, width: flipped.width * videoSize.width, height: flipped.height * videoSize.height)
            .integral
            .intersection(CGRect(origin: .zero, size: videoSize))
    }

    static func apply(_ regions: [BlurRegion], to image: CIImage, time: Double, videoSize: CGSize) -> CIImage {
        regions.reduce(image) { result, region in
            guard let normalized = region.rect(at: time) else { return result }
            let frame = pixelRect(for: normalized, videoSize: videoSize)
            guard !frame.isNull, frame.width >= 1, frame.height >= 1 else { return result }
            return obscured(result, in: frame, style: region.style).cropped(to: frame).composited(over: result)
        }
    }

    private static func obscured(_ image: CIImage, in frame: CGRect, style: BlurRegionStyle) -> CIImage {
        let source = image.clampedToExtent()
        let shortSide = min(frame.width, frame.height)
        switch style {
        case .blur:
            return source.applyingGaussianBlur(sigma: Double(max(6, shortSide * 0.3)))
        case .pixelate:
            return source.applyingFilter(
                "CIPixellate",
                parameters: [
                    kCIInputScaleKey: max(6, shortSide / 6),
                    kCIInputCenterKey: CIVector(x: frame.minX, y: frame.minY),
                ])
        }
    }
}

enum RegionTrackingError: LocalizedError {
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track found in the recording"
        }
    }
}

enum RegionTracker {
    static let maximumFrameRate = 15.0
    static let analysisWidth = 960
    static let minimumConfidence: Float = 0.3
    static let backwardChunk = 2.0

    static func track(_ url: URL, rect: CGRect, at time: Double, within range: ClosedRange<Double>, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [RegionKeyframe]
    {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RegionTrackingError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let start = max(range.lowerBound, 0)
        let end = range.upperBound
        let forward = try await trackForward(asset: asset, track: track, naturalSize: naturalSize, rect: rect, from: time, to: end) { value in
            progress?(value * (end - time) / max(0.001, end - start))
        }
        let backward = try await trackBackward(asset: asset, track: track, naturalSize: naturalSize, rect: rect, from: time, to: start)
        progress?(1)
        let samples = backward.reversed() + [RegionKeyframe(time: time, rect: rect)] + forward
        return TrackSmoothing.keyframes(fromTracked: samples)
    }

    private static func trackForward(
        asset: AVAsset, track: AVAssetTrack, naturalSize: CGSize, rect: CGRect, from time: Double, to end: Double, progress: (Double) -> Void
    ) async throws -> [RegionKeyframe] {
        guard end > time else { return [] }
        let frames = try frameReader(asset: asset, track: track, naturalSize: naturalSize, range: time ... end)
        var session = TrackingSession(rect: rect)
        var samples: [RegionKeyframe] = []
        try frames.forEach { sampleTime, buffer in
            guard sampleTime > time + 0.0001 else { return true }
            progress((sampleTime - time) / max(0.001, end - time))
            guard let tracked = try session.advance(on: buffer) else { return false }
            samples.append(RegionKeyframe(time: sampleTime, rect: tracked))
            return true
        }
        return samples
    }

    private static func trackBackward(asset: AVAsset, track: AVAssetTrack, naturalSize: CGSize, rect: CGRect, from time: Double, to start: Double) async throws
        -> [RegionKeyframe]
    {
        var session = TrackingSession(rect: rect)
        var samples: [RegionKeyframe] = []
        var chunkEnd = time
        while chunkEnd > start + 0.0001 {
            try Task.checkCancellation()
            let chunkStart = max(start, chunkEnd - backwardChunk)
            var frames: [(Double, CVPixelBuffer)] = []
            try frameReader(asset: asset, track: track, naturalSize: naturalSize, range: chunkStart ... chunkEnd).forEach { sampleTime, buffer in
                if sampleTime < chunkEnd - 0.0001 { frames.append((sampleTime, buffer)) }
                return true
            }
            for (sampleTime, buffer) in frames.reversed() {
                guard let tracked = try session.advance(on: buffer) else { return samples }
                samples.append(RegionKeyframe(time: sampleTime, rect: tracked))
            }
            chunkEnd = chunkStart
        }
        return samples
    }

    private static func frameReader(asset: AVAsset, track: AVAssetTrack, naturalSize: CGSize, range: ClosedRange<Double>) throws -> SampledFrames {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: RecordingEditor.time(range.lowerBound), end: RecordingEditor.time(range.upperBound))
        let scale = min(1, CGFloat(analysisWidth) / max(1, naturalSize.width))
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int((naturalSize.width * scale).rounded()),
                kCVPixelBufferHeightKey as String: Int((naturalSize.height * scale).rounded()),
            ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw MediaPumpError.readerFailed(reader.error?.localizedDescription) }
        return SampledFrames(reader: reader, output: output, interval: 1 / maximumFrameRate)
    }
}

private struct SampledFrames {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let interval: Double

    func forEach(_ body: (Double, CVPixelBuffer) throws -> Bool) throws {
        defer { reader.cancelReading() }
        var lastTime = -Double.infinity
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = sample.presentationTimeStamp.seconds
            guard time - lastTime >= interval - 0.001 else { continue }
            lastTime = time
            guard try body(time, buffer) else { return }
        }
    }
}

private struct TrackingSession {
    private let handler = VNSequenceRequestHandler()
    private var observation: VNDetectedObjectObservation

    init(rect: CGRect) {
        observation = VNDetectedObjectObservation(boundingBox: RegionGeometry.flippedVertically(RegionGeometry.clampedToUnit(rect)))
    }

    mutating func advance(on buffer: CVPixelBuffer) throws -> CGRect? {
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate
        try handler.perform([request], on: buffer)
        guard let result = request.results?.first as? VNDetectedObjectObservation, result.confidence >= RegionTracker.minimumConfidence else { return nil }
        observation = result
        return RegionGeometry.clampedToUnit(RegionGeometry.flippedVertically(result.boundingBox))
    }
}

enum SensitiveRegionDetector {
    static func detect(
        in url: URL, interval: Double, categories: Set<RedactionCategory>, style: BlurRegionStyle, range: ClosedRange<Double>? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [BlurRegion] {
        guard !categories.isEmpty, interval > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let bounds = range ?? 0 ... duration
        let times = stride(from: bounds.lowerBound, through: bounds.upperBound, by: interval).map { CMTime(seconds: $0, preferredTimescale: 600) }
        guard !times.isEmpty else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var detections: [RegionDetection] = []
        var processed = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            processed += 1
            progress?(Double(processed) / Double(times.count))
            guard let image = try? result.image else { continue }
            let size = CGSize(width: image.width, height: image.height)
            let lines = try await TextRecognition.lines(in: image)
            let rects = RedactionGeometry.rects(for: lines, categories: categories, imageSize: size).map { rect in
                CGRect(x: rect.minX / size.width, y: rect.minY / size.height, width: rect.width / size.width, height: rect.height / size.height)
            }
            detections.append(RegionDetection(time: result.requestedTime.seconds, rects: rects))
        }
        return RegionLinker.regions(from: detections, interval: interval, duration: duration, style: style)
    }
}
