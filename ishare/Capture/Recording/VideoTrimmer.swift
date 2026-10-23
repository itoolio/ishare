import AVFoundation
import Foundation

struct TrimSelection: Equatable, Sendable {
    static let minimumLength: Double = 0.2

    let duration: Double
    private(set) var start: Double
    private(set) var end: Double

    init(duration: Double) {
        self.duration = max(0, duration)
        start = 0
        end = self.duration
    }

    var length: Double { end - start }

    var isFullLength: Bool {
        start <= 0.001 && end >= duration - 0.001
    }

    var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }

    mutating func setStart(_ value: Double) {
        start = min(max(0, value), max(0, end - minimumGap))
    }

    mutating func setEnd(_ value: Double) {
        end = max(min(duration, value), min(duration, start + minimumGap))
    }

    func clampedPlayhead(_ time: Double) -> Double {
        min(max(time, start), end)
    }

    func fraction(of time: Double) -> Double {
        duration > 0 ? min(max(time / duration, 0), 1) : 0
    }

    func time(atFraction fraction: Double) -> Double {
        min(max(fraction, 0), 1) * duration
    }

    private var minimumGap: Double {
        min(Self.minimumLength, duration)
    }
}

enum VideoTrimError: LocalizedError {
    case exportUnavailable

    var errorDescription: String? {
        switch self {
        case .exportUnavailable: "The recording couldn't be trimmed"
        }
    }
}

enum VideoTrimmer {
    static func fileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "mp4": .mp4
        case "m4v": .m4v
        default: .mov
        }
    }

    static func export(_ url: URL, range: CMTimeRange, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoTrimError.exportUnavailable
        }
        session.timeRange = range
        try? FileManager.default.removeItem(at: outputURL)
        try await session.export(to: outputURL, as: fileType(for: outputURL))
    }

    static func trimInPlace(_ url: URL, range: CMTimeRange) async throws -> URL {
        let temporaryURL = url.deletingLastPathComponent()
            .appending(path: ".\(url.deletingPathExtension().lastPathComponent)-trim-\(UUID().uuidString).\(url.pathExtension)", directoryHint: .notDirectory)
        do {
            try await export(url, range: range, to: temporaryURL)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        return url
    }
}
