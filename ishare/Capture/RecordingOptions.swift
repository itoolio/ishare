import AVFoundation
import CoreGraphics
import Defaults
import ishareCore

enum RecordingResolution: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case native
    case p2160
    case p1440
    case p1080
    case p720
    case half

    var id: Self { self }

    var title: String {
        switch self {
        case .native: "Native"
        case .p2160: "4K (2160p)"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .half: "50%"
        }
    }

    var shortSideLimit: CGFloat? {
        switch self {
        case .p2160: 2160
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .native, .half: nil
        }
    }

    func outputSize(for pixelSize: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return ScreenGeometry.evenPixelSize(pixelSize) }
        let scale: CGFloat
        switch self {
        case .native:
            scale = 1
        case .half:
            scale = 0.5
        default:
            let shortSide = min(pixelSize.width, pixelSize.height)
            scale = min(1, (shortSideLimit ?? shortSide) / shortSide)
        }
        return ScreenGeometry.evenPixelSize(CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale))
    }
}

enum RecordingFrameRate: Int, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Self { self }

    var minimumFrameInterval: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(rawValue))
    }
}

enum GIFFrameRate: Int, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case fps10 = 10
    case fps15 = 15
    case fps20 = 20
    case fps30 = 30

    var id: Self { self }
}

enum CompressionPreset: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case p1080
    case p720
    case p540
    case medium

    var id: Self { self }

    var title: String {
        switch self {
        case .p1080: "1080p"
        case .p720: "720p"
        case .p540: "540p"
        case .medium: "Medium quality"
        }
    }

    func exportPreset(hevc: Bool) -> String {
        switch self {
        case .p1080: hevc ? AVAssetExportPresetHEVC1920x1080 : AVAssetExportPreset1920x1080
        case .p720: AVAssetExportPreset1280x720
        case .p540: AVAssetExportPreset960x540
        case .medium: AVAssetExportPresetMediumQuality
        }
    }
}

enum GIFTiming {
    static func frameTimes(duration: Double, frameRate: Int) -> [CMTime] {
        guard duration > 0, frameRate > 0 else { return [] }
        let count = max(1, Int((duration * Double(frameRate)).rounded(.down)))
        return (0 ..< count).map { index in
            CMTime(seconds: Double(index) / Double(frameRate), preferredTimescale: 600)
        }
    }

    static func delay(frameRate: Int) -> Double {
        1.0 / Double(max(1, frameRate))
    }
}

enum VideoCompressor {
    static func needsCompression(fileSize: Int64, thresholdMB: Int) -> Bool {
        fileSize > Int64(thresholdMB) * 1024 * 1024
    }

    static func compress(_ url: URL, preset: CompressionPreset, hevc: Bool) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset.exportPreset(hevc: hevc)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = FileManager.default.temporaryDirectory
            .appending(path: url.deletingPathExtension().lastPathComponent + "-compressed.mp4")
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
        return output
    }
}
