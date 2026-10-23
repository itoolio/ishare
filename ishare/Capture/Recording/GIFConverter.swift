import AVFoundation
import CoreGraphics
import Defaults
import Foundation
import ImageIO
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

enum GIFConverter {
    static func destinationURL(for videoURL: URL, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let directory = videoURL.deletingLastPathComponent()
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appending(path: "\(baseName).gif", directoryHint: .notDirectory)
        var index = 2
        while fileExists(candidate) {
            candidate = directory.appending(path: "\(baseName)-\(index).gif", directoryHint: .notDirectory)
            index += 1
        }
        return candidate
    }

    static func convert(
        _ videoURL: URL,
        range: CMTimeRange? = nil,
        preset: GIFPreset,
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
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
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw GIFExportError.destinationUnavailable
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delays = GIFTiming.centisecondDelays(frameCount: times.count, frameRate: frameRate)

        var lastImage: CGImage?
        var frameIndex = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            guard let image = (try? result.image) ?? lastImage else { continue }
            let delay = Double(delays[min(frameIndex, delays.count - 1)]) / 100
            let frameProperties = [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ]] as CFDictionary
            CGImageDestinationAddImage(destination, image, frameProperties)
            lastImage = image
            frameIndex += 1
            progress?(Double(frameIndex) / Double(times.count))
        }
        guard frameIndex > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw GIFExportError.finalizeFailed
        }
        return outputURL
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
}
