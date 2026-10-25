import AVFoundation
import CoreGraphics
import Defaults
import Foundation
import ImageIO
import ishareCore
import UniformTypeIdentifiers

enum GIFMaxSize: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case original
    case p1080
    case p720
    case p480

    var id: Self { self }

    var title: String {
        switch self {
        case .original: "Original"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }

    var shortSideLimit: CGFloat? {
        switch self {
        case .original: nil
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }
}

struct GIFPreset: Hashable, Sendable {
    var frameRate: GIFFrameRate
    var maxSize: GIFMaxSize

    static var current: GIFPreset {
        GIFPreset(frameRate: Defaults[.gifFrameRate], maxSize: Defaults[.gifMaxSize])
    }
}

enum GIFExportError: LocalizedError {
    case noVideoTrack
    case emptyRange
    case destinationUnavailable
    case finalizeFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track found in the recording"
        case .emptyRange: "The selected range is too short for a GIF"
        case .destinationUnavailable: "Couldn't create the GIF file"
        case .finalizeFailed: "GIF export failed"
        }
    }
}

extension GIFTiming {
    static func frameTimes(in range: CMTimeRange, frameRate: Int) -> [CMTime] {
        let start = range.start.seconds
        return frameTimes(duration: range.duration.seconds, frameRate: frameRate).map { offset in
            CMTime(seconds: start + offset.seconds, preferredTimescale: 600)
        }
    }

    static func centisecondDelays(frameCount: Int, frameRate: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        let rate = Double(max(1, frameRate))
        func elapsedCentiseconds(afterFrames frames: Int) -> Int {
            Int((Double(frames) * 100 / rate).rounded())
        }
        return (0 ..< frameCount).map { index in
            max(2, elapsedCentiseconds(afterFrames: index + 1) - elapsedCentiseconds(afterFrames: index))
        }
    }
}

enum GIFGeometry {
    static func displaySize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    static func outputSize(for size: CGSize, maxSize: GIFMaxSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let shortSide = min(size.width, size.height)
        let scale = min(1, (maxSize.shortSideLimit ?? shortSide) / shortSide)
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }
}

enum AnimatedImageFormat: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case gif
    case apng
    case webp

    static let webPTypeIdentifier = "org.webmproject.webp"

    var id: Self { self }

    var title: String {
        switch self {
        case .gif: "GIF"
        case .apng: "APNG"
        case .webp: "WebP"
        }
    }

    var fileExtension: String {
        switch self {
        case .gif: "gif"
        case .apng: "png"
        case .webp: "webp"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .gif: UTType.gif.identifier
        case .apng: UTType.png.identifier
        case .webp: Self.webPTypeIdentifier
        }
    }

    var isAvailable: Bool {
        Self.encodableTypeIdentifiers.contains(typeIdentifier)
    }

    static var encodableTypeIdentifiers: Set<String> {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }

    static var unavailableMessage: String {
        "WebP isn't available because this Mac can't encode WebP images.".localized()
    }

    var containerKey: CFString {
        switch self {
        case .gif: kCGImagePropertyGIFDictionary
        case .apng: kCGImagePropertyPNGDictionary
        case .webp: kCGImagePropertyWebPDictionary
        }
    }

    var fileProperties: [CFString: Any] {
        switch self {
        case .gif: [containerKey: [kCGImagePropertyGIFLoopCount: 0]]
        case .apng: [containerKey: [kCGImagePropertyAPNGLoopCount: 0]]
        case .webp: [containerKey: [kCGImagePropertyWebPLoopCount: 0]]
        }
    }

    func frameProperties(delay: Double) -> [CFString: Any] {
        switch self {
        case .gif: [containerKey: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]]
        case .apng: [containerKey: [kCGImagePropertyAPNGDelayTime: delay, kCGImagePropertyAPNGUnclampedDelayTime: delay]]
        case .webp: [containerKey: [kCGImagePropertyWebPDelayTime: delay, kCGImagePropertyWebPUnclampedDelayTime: delay]]
        }
    }

    func frameDelays(frameCount: Int, frameRate: Int) -> [Double] {
        switch self {
        case .gif: GIFTiming.centisecondDelays(frameCount: frameCount, frameRate: frameRate).map { Double($0) / 100 }
        case .apng, .webp: Array(repeating: GIFTiming.delay(frameRate: frameRate), count: frameCount)
        }
    }
}

enum AnimatedImageError: LocalizedError {
    case formatUnavailable(AnimatedImageFormat)

    var errorDescription: String? {
        switch self {
        case .formatUnavailable: AnimatedImageFormat.unavailableMessage
        }
    }
}

enum FrameFingerprint {
    static let side = 32
    static let duplicateThreshold = 0.002

    static func grayscale(_ image: CGImage, side: Int = side) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : []
    }

    static func isDuplicate(_ fingerprint: [UInt8], of previous: [UInt8]?) -> Bool {
        guard let previous, !fingerprint.isEmpty else { return false }
        return FrameDifference.meanAbsoluteDifference(fingerprint, previous) < duplicateThreshold
    }
}

private struct PendingAnimatedFrame {
    var image: CGImage
    var fingerprint: [UInt8]
    var delay: Double
}

enum AnimatedImageConverter {
    static func destinationURL(for videoURL: URL, format: AnimatedImageFormat, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        MediaFiles.uniqueURL(for: videoURL, extension: format.fileExtension, fileExists: fileExists)
    }

    static func convert(
        _ videoURL: URL,
        range: CMTimeRange? = nil,
        preset: GIFPreset,
        format: AnimatedImageFormat,
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard format.isAvailable else { throw AnimatedImageError.formatUnavailable(format) }
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw GIFExportError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

        let fullRange = CMTimeRange(start: .zero, duration: duration)
        let selectedRange = range.map { $0.intersection(fullRange) } ?? fullRange
        let frameRate = preset.frameRate.rawValue
        let times = GIFTiming.frameTimes(in: selectedRange, frameRate: frameRate)
        guard !times.isEmpty else { throw GIFExportError.emptyRange }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: GIFTiming.delay(frameRate: frameRate) / 2, preferredTimescale: 600)
        generator.appliesPreferredTrackTransform = true
        if preset.maxSize != .original {
            let displaySize = GIFGeometry.displaySize(naturalSize: naturalSize, transform: transform)
            generator.maximumSize = GIFGeometry.outputSize(for: displaySize, maxSize: preset.maxSize)
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, format.typeIdentifier as CFString, times.count, nil) else {
            throw GIFExportError.destinationUnavailable
        }
        CGImageDestinationSetProperties(destination, format.fileProperties as CFDictionary)
        let delays = format.frameDelays(frameCount: times.count, frameRate: frameRate)

        var pending: PendingAnimatedFrame?
        var frameIndex = 0
        var written = 0
        func write(_ frame: PendingAnimatedFrame) {
            CGImageDestinationAddImage(destination, frame.image, format.frameProperties(delay: frame.delay) as CFDictionary)
            written += 1
        }
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            let delay = delays[min(frameIndex, delays.count - 1)]
            frameIndex += 1
            progress?(Double(frameIndex) / Double(times.count))
            guard let image = try? result.image else {
                pending?.delay += delay
                continue
            }
            let fingerprint = FrameFingerprint.grayscale(image)
            if var current = pending, FrameFingerprint.isDuplicate(fingerprint, of: current.fingerprint) {
                current.delay += delay
                pending = current
                continue
            }
            if let pending { write(pending) }
            pending = PendingAnimatedFrame(image: image, fingerprint: fingerprint, delay: delay)
        }
        if let pending { write(pending) }
        guard written > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw GIFExportError.finalizeFailed
        }
        return outputURL
    }
}

enum GIFConverter {
    static func destinationURL(for videoURL: URL, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        AnimatedImageConverter.destinationURL(for: videoURL, format: .gif, fileExists: fileExists)
    }

    static func convert(
        _ videoURL: URL,
        range: CMTimeRange? = nil,
        preset: GIFPreset,
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await AnimatedImageConverter.convert(videoURL, range: range, preset: preset, format: .gif, to: outputURL, progress: progress)
    }
}

enum RecordingConversions {
    static func convertToGIF(_ url: URL, preset: GIFPreset) async throws -> URL {
        try await GIFConverter.convert(url, preset: preset, to: GIFConverter.destinationURL(for: url))
    }

    static func convertToGIF(_ url: URL, range: CMTimeRange?, preset: GIFPreset, deletingSource: Bool, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let output = try await GIFConverter.convert(url, range: range, preset: preset, to: GIFConverter.destinationURL(for: url), progress: progress)
        if deletingSource {
            try? FileManager.default.removeItem(at: url)
        }
        return output
    }

    static func convertToAnimation(
        _ url: URL, format: AnimatedImageFormat, range: CMTimeRange?, preset: GIFPreset, deletingSource: Bool, progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let destination = AnimatedImageConverter.destinationURL(for: url, format: format)
        let output = try await AnimatedImageConverter.convert(url, range: range, preset: preset, format: format, to: destination, progress: progress)
        if deletingSource {
            try? FileManager.default.removeItem(at: url)
        }
        return output
    }
}
