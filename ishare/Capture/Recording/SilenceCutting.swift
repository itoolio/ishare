import AVFoundation
import BezelNotification
import CoreGraphics
import Defaults
import Foundation
import ishareCore

enum MediaLevelAnalyzer {
    static let audioStep = 0.05
    static let analysisSampleRate = 16000.0
    static let motionFrameRate = 4.0
    static let motionSide = 48

    static func audioLevels(of asset: AVAsset, step: Double = audioStep) async throws -> LevelSeries? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let reader = try AVAssetReader(asset: asset)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: analysisSampleRate,
                AVChannelLayoutKey: layoutData,
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { throw MediaPumpError.readerFailed(reader.error?.localizedDescription) }
        var meter = WindowedRMS(windowLength: max(1, Int(analysisSampleRate * step)))
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            meter.add(samples(in: buffer))
        }
        guard reader.status == .completed else { throw MediaPumpError.readerFailed(reader.error?.localizedDescription) }
        return LevelSeries(step: step, values: meter.finish())
    }

    static func audioLevels(of url: URL, step: Double = audioStep) async throws -> LevelSeries? {
        try await audioLevels(of: AVURLAsset(url: url), step: step)
    }

    static func motionLevels(of asset: AVAsset, frameRate: Double = motionFrameRate) async throws -> LevelSeries? {
        let duration = try await asset.load(.duration).seconds
        guard duration > 0, !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { return nil }
        let step = 1 / frameRate
        let count = max(1, Int((duration / step).rounded(.up)))
        let times = (0 ... count).map { CMTime(seconds: min(duration, Double($0) * step), preferredTimescale: 600) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.requestedTimeToleranceBefore = CMTime(seconds: step / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)
        var fingerprints: [[UInt8]] = []
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            if let image = try? result.image {
                fingerprints.append(FrameFingerprint.grayscale(image, side: motionSide))
            } else {
                fingerprints.append(fingerprints.last ?? [])
            }
        }
        let differences = zip(fingerprints, fingerprints.dropFirst()).map { FrameDifference.meanAbsoluteDifference($0, $1) }
        return LevelSeries(step: step, values: differences.isEmpty ? [0] : differences)
    }

    private static func samples(in buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = samples.withUnsafeMutableBytes { pointer in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: pointer.count, destination: pointer.baseAddress!)
        }
        return status == kCMBlockBufferNoErr ? samples : []
    }
}

struct WindowedRMS {
    let windowLength: Int
    private var sum = 0.0
    private var count = 0
    private var values: [Double] = []

    init(windowLength: Int) {
        self.windowLength = windowLength
    }

    mutating func add(_ samples: [Float]) {
        for sample in samples {
            sum += Double(sample) * Double(sample)
            count += 1
            if count == windowLength { flush() }
        }
    }

    mutating func finish() -> [Double] {
        if count > 0 { flush() }
        return values
    }

    private mutating func flush() {
        values.append(FrameDifference.decibels(rms: (sum / Double(max(1, count))).squareRoot()))
        sum = 0
        count = 0
    }
}

struct SilenceAnalysis: Hashable, Sendable {
    var audio: LevelSeries?
    var motion: LevelSeries?
    var duration: Double

    func plan(settings: SilenceDetectionSettings, extraAudio: LevelSeries? = nil) -> RetimingPlan {
        let combined = LevelSeries.loudest([audio, extraAudio].compactMap(\.self))
        return SilencePlanner.plan(audio: combined, motion: motion, duration: duration, settings: settings)
    }
}

enum SilenceCutter {
    static func analyze(_ url: URL) async throws -> SilenceAnalysis {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        async let audio = MediaLevelAnalyzer.audioLevels(of: asset)
        async let motion = MediaLevelAnalyzer.motionLevels(of: asset)
        return SilenceAnalysis(audio: try await audio, motion: try await motion, duration: duration)
    }
}

extension SilenceDetectionSettings {
    @MainActor static var current: SilenceDetectionSettings {
        SilenceDetectionSettings(
            audioThreshold: Defaults[.cutSilenceAudioThreshold],
            motionThreshold: Defaults[.cutSilenceMotionThreshold],
            minimumDuration: Defaults[.cutSilenceMinimumDuration],
            padding: Defaults[.cutSilencePadding],
            speed: Defaults[.cutSilenceSpeed]
        )
    }
}

extension SilenceSpeed: Defaults.Serializable {
    var title: String {
        switch self {
        case .remove: "Remove"
        case .double: "Speed up 2×"
        case .quadruple: "Speed up 4×"
        case .octuple: "Speed up 8×"
        }
    }
}

extension RecordingPostProcessor {
    private static let editableExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func cutSilenceIfEnabled(_ url: URL, markers: [RecordingMarker]) async -> [RecordingMarker] {
        guard Defaults[.cutSilenceEnabled], editableExtensions.contains(url.pathExtension.lowercased()) else { return markers }
        let settings = SilenceDetectionSettings.current
        let hevc = Defaults[.useHEVC]
        do {
            return try await ProcessingHUDPresenter.run("Cutting silence…".localized()) { progress in
                let analysis = try await SilenceCutter.analyze(url)
                let plan = analysis.plan(settings: settings)
                guard !plan.isIdentity else { return markers }
                _ = try await RecordingEditor.renderInPlace(url, edit: RecordingEdit(plan: plan), hevc: hevc, progress: progress)
                return RecordingChapters.retimed(markers, through: plan)
            }
        } catch {
            Log.capture.error("Cutting silence failed, keeping the original: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Cutting silence failed".localized(), icon: ToastIcon)
            return markers
        }
    }

    static func convertIfRequested(_ url: URL, recordsGIF: Bool) async -> URL? {
        guard editableExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        guard let format = recordsGIF ? AnimatedImageFormat.gif : Defaults[.recordingConvertTo].animatedFormat else { return nil }
        do {
            return try await ProcessingHUDPresenter.run(String(format: "Converting to %@…".localized(), format.title)) { progress in
                try await RecordingConversions.convertToAnimation(url, format: format, range: nil, preset: .current, deletingSource: true, progress: progress)
            }
        } catch {
            Log.capture.error("\(format.title, privacy: .public) export failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: String(format: "%@ export failed".localized(), format.title), icon: ToastIcon)
            return nil
        }
    }

    static func uploadCopy(of url: URL) async -> URL {
        guard editableExtensions.contains(url.pathExtension.lowercased()), let format = Defaults[.recordingUploadFormat].animatedFormat else {
            return await PostCapture.compressedIfNeeded(url)
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-upload-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: url.deletingPathExtension().lastPathComponent + "." + format.fileExtension, directoryHint: .notDirectory)
            return try await AnimatedImageConverter.convert(url, preset: .current, format: format, to: destination)
        } catch {
            Log.capture.error("Converting the upload failed, uploading the video: \(error.localizedDescription, privacy: .public)")
            return await PostCapture.compressedIfNeeded(url)
        }
    }
}

enum RecordingConversion: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case none
    case gif
    case apng
    case webp

    var id: Self { self }

    var animatedFormat: AnimatedImageFormat? {
        switch self {
        case .none: nil
        case .gif: .gif
        case .apng: .apng
        case .webp: .webp
        }
    }

    var isAvailable: Bool { animatedFormat?.isAvailable ?? true }
}
