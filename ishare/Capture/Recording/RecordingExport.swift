@preconcurrency import AVFoundation
import CoreGraphics
import Defaults
import Foundation

enum RecordingExportFormat: String, CaseIterable, Identifiable, Sendable {
    case mp4H264
    case mp4HEVC
    case mov
    case gif
    case m4a

    var id: Self { self }

    var title: String {
        switch self {
        case .mp4H264: "MP4 (H.264)"
        case .mp4HEVC: "MP4 (HEVC)"
        case .mov: "MOV"
        case .gif: "GIF"
        case .m4a: "Audio only (M4A)"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: "mp4"
        case .mov: "mov"
        case .gif: "gif"
        case .m4a: "m4a"
        }
    }

    var fileType: AVFileType? {
        switch self {
        case .mp4H264, .mp4HEVC: .mp4
        case .mov: .mov
        case .m4a: .m4a
        case .gif: nil
        }
    }

    var videoCodec: AVVideoCodecType? {
        switch self {
        case .mp4H264: .h264
        case .mp4HEVC: .hevc
        case .mov: .h264
        case .gif, .m4a: nil
        }
    }

    var hasVideo: Bool { videoCodec != nil || self == .gif }
    var supportsAudio: Bool { self != .gif }
    var supportsChapters: Bool { fileType != nil }
}

enum RecordingExportSize: String, CaseIterable, Identifiable, Sendable {
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

    var gifMaxSize: GIFMaxSize {
        switch self {
        case .original: .original
        case .p1080: .p1080
        case .p720: .p720
        case .p480: .p480
        }
    }

    func outputSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let shortSide = min(size.width, size.height)
        let scale = min(1, (shortSideLimit ?? shortSide) / shortSide)
        return ScreenGeometry.evenPixelSize(CGSize(width: size.width * scale, height: size.height * scale))
    }
}

enum RecordingExportQuality: String, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case small

    var id: Self { self }

    var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .small: "Small"
        }
    }

    var bitsPerPixel: Double {
        switch self {
        case .high: 0.2
        case .medium: 0.1
        case .small: 0.05
        }
    }

    var audioBitRate: Int {
        switch self {
        case .high: 192_000
        case .medium: 128_000
        case .small: 96_000
        }
    }
}

struct RecordingExportSettings: Hashable, Sendable {
    var format: RecordingExportFormat = .mp4H264
    var size: RecordingExportSize = .original
    var quality: RecordingExportQuality = .high
    var removesAudio = false
    var gifFrameRate: GIFFrameRate = .fps20

    @MainActor static var current: RecordingExportSettings {
        RecordingExportSettings(
            format: Defaults[.recordMP4] ? (Defaults[.useHEVC] ? .mp4HEVC : .mp4H264) : .mov,
            size: RecordingExportSize(rawValue: Defaults[.gifMaxSize].rawValue) ?? .original,
            gifFrameRate: Defaults[.gifFrameRate]
        )
    }

    var includesAudio: Bool {
        format == .m4a || (format.supportsAudio && !removesAudio)
    }

    var gifPreset: GIFPreset {
        GIFPreset(frameRate: gifFrameRate, maxSize: size.gifMaxSize)
    }

    func videoBitRate(for size: CGSize, frameRate: Double, codec: AVVideoCodecType) -> Int {
        let rate = frameRate > 0 ? min(frameRate, 120) : 30
        let codecFactor = codec == .hevc ? 0.6 : 1
        let bitRate = Double(size.width * size.height) * rate * quality.bitsPerPixel * codecFactor
        return max(250_000, Int(bitRate.rounded()))
    }

    func videoOutputSettings(sourceSize: CGSize, frameRate: Double) -> [String: Any]? {
        guard let codec = format.videoCodec else { return nil }
        let output = size.outputSize(for: sourceSize)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: videoBitRate(for: output, frameRate: frameRate, codec: codec),
            AVVideoExpectedSourceFrameRateKey: frameRate > 0 ? Int(frameRate.rounded()) : 30,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(output.width),
            AVVideoHeightKey: Int(output.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    func audioOutputSettings(channelCount: Int, sampleRate: Double) -> [String: Any]? {
        guard includesAudio else { return nil }
        let channels = min(max(channelCount, 1), 2)
        let supportedRates: [Double] = [48000, 44100, 32000, 24000, 22050, 16000]
        let rate = supportedRates.first { $0 <= max(sampleRate, 16000) } ?? 44100
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: channels,
            AVSampleRateKey: rate,
            AVEncoderBitRateKey: min(quality.audioBitRate, channels == 1 ? 128_000 : 320_000),
        ]
    }
}

enum RecordingExportError: LocalizedError {
    case noVideoTrack
    case noAudioTrack
    case unsupported

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track found in the recording"
        case .noAudioTrack: "The recording has no audio to export"
        case .unsupported: "This export isn't supported"
        }
    }
}

enum RecordingTranscoder {
    static func export(
        _ url: URL,
        settings: RecordingExportSettings,
        range: CMTimeRange?,
        to outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let fileType = settings.format.fileType else { throw RecordingExportError.unsupported }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        let timeRange = range.map { $0.intersection(fullRange) } ?? fullRange

        try? FileManager.default.removeItem(at: outputURL)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = fileType == .mp4
        var lanes: [MediaPumpLane] = []

        if settings.format.videoCodec != nil {
            guard let lane = try await videoLane(asset: asset, settings: settings, reader: reader, writer: writer) else { throw RecordingExportError.noVideoTrack }
            lanes.append(lane)
        }
        if settings.includesAudio {
            if let lane = try await audioLane(asset: asset, settings: settings, reader: reader, writer: writer) {
                lanes.append(lane)
            } else if settings.format == .m4a {
                throw RecordingExportError.noAudioTrack
            }
        }
        do {
            try await MediaPump.run(reader: reader, writer: writer, lanes: lanes, timeRange: timeRange, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func videoLane(asset: AVAsset, settings: RecordingExportSettings, reader: AVAssetReader, writer: AVAssetWriter) async throws -> MediaPumpLane? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = Double(try await track.load(.nominalFrameRate))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings.videoOutputSettings(sourceSize: naturalSize, frameRate: frameRate))
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        return MediaPumpLane(output: output, input: input)
    }

    private static func audioLane(asset: AVAsset, settings: RecordingExportSettings, reader: AVAssetReader, writer: AVAssetWriter) async throws -> MediaPumpLane? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        var channelCount = 2
        var sampleRate = 48000.0
        if let description = try await tracks[0].load(.formatDescriptions).first,
           let basic = description.audioStreamBasicDescription {
            channelCount = Int(basic.mChannelsPerFrame)
            sampleRate = basic.mSampleRate
        }
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output),
              let audioSettings = settings.audioOutputSettings(channelCount: channelCount, sampleRate: sampleRate)
        else { return nil }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        return MediaPumpLane(output: output, input: input)
    }
}

extension RecordingConversions {
    static func export(
        _ url: URL,
        settings: RecordingExportSettings,
        range: CMTimeRange? = nil,
        deletingSource: Bool,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        if settings.format == .gif {
            return try await convertToGIF(url, range: range, preset: settings.gifPreset, deletingSource: deletingSource, progress: progress)
        }
        let replacesSource = url.pathExtension.lowercased() == settings.format.fileExtension
        let outputURL = replacesSource ? MediaFiles.siblingTemporaryURL(for: url, tag: "export") : MediaFiles.uniqueURL(for: url, extension: settings.format.fileExtension)
        try await RecordingTranscoder.export(url, settings: settings, range: range, to: outputURL, progress: progress)
        guard replacesSource else {
            if deletingSource { try? FileManager.default.removeItem(at: url) }
            return outputURL
        }
        if deletingSource {
            try MediaFiles.replace(url, with: outputURL)
            return url
        }
        let keptURL = MediaFiles.uniqueURL(for: url, extension: settings.format.fileExtension)
        try FileManager.default.moveItem(at: outputURL, to: keptURL)
        return keptURL
    }
}
