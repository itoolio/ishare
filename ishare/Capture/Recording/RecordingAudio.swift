import AVFoundation
import Defaults
import ishareCore
import ScreenCaptureKit

enum RecordingAudioSource: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case allSystemAudio
    case selectedApps
    case none

    var id: Self { self }

    var title: String {
        switch self {
        case .allSystemAudio: "All system audio"
        case .selectedApps: "Only selected apps"
        case .none: "None"
        }
    }

    static func resolved(recordAudio: Bool, source: RecordingAudioSource) -> RecordingAudioSource {
        recordAudio ? source : .none
    }

    static var current: RecordingAudioSource {
        resolved(recordAudio: RecordingDefaults[.recordAudio], source: RecordingDefaults[.recordingAudioSource])
    }

    static func store(_ source: RecordingAudioSource) {
        Defaults[.recordAudio] = source != .none
        if source != .none {
            Defaults[.recordingAudioSource] = source
        }
    }
}

enum RecordingContentStyle: Sendable {
    case display
    case window
    case application

    init(_ style: SCShareableContentStyle) {
        switch style {
        case .window: self = .window
        case .application: self = .application
        default: self = .display
        }
    }
}

enum RecordingAudioPlan: Equatable, Sendable {
    case silent
    case contentAudio
    case applications(Set<String>)

    var capturesContentAudio: Bool { self == .contentAudio }

    var recordsAudio: Bool { self != .silent }

    static func make(source: RecordingAudioSource, selectedBundleIDs: [String], style: RecordingContentStyle) -> RecordingAudioPlan {
        switch source {
        case .none:
            return .silent
        case .allSystemAudio:
            return .contentAudio
        case .selectedApps:
            guard style == .display else { return .contentAudio }
            let ids = Set(selectedBundleIDs.filter { !$0.isEmpty })
            return ids.isEmpty ? .silent : .applications(ids)
        }
    }

    static var current: (RecordingContentStyle) -> RecordingAudioPlan {
        { style in make(source: .current, selectedBundleIDs: RecordingDefaults[.recordingAudioBundleIDs], style: style) }
    }
}

protocol BundleIdentified {
    var bundleIdentifier: String { get }
}

extension SCRunningApplication: BundleIdentified {}

enum RecordingAudioFilter {
    static func applications<App: BundleIdentified>(_ apps: [App], matching bundleIDs: Set<String>, ownBundleID: String? = Bundle.main.bundleIdentifier) -> [App] {
        apps.filter { bundleIDs.contains($0.bundleIdentifier) && $0.bundleIdentifier != ownBundleID }
    }

    static func filter(display: SCDisplay, bundleIDs: Set<String>, in content: SCShareableContent) -> SCContentFilter? {
        let apps = applications(content.applications, matching: bundleIDs)
        guard !apps.isEmpty else { return nil }
        return SCContentFilter(display: display, including: apps, exceptingWindows: [])
    }

    static func audioOnlyConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        return configuration
    }

    static func apply(_ plan: RecordingAudioPlan, to configuration: SCStreamConfiguration) {
        configuration.capturesAudio = plan.capturesContentAudio
        configuration.excludesCurrentProcessAudio = true
    }
}

struct AppAudioClip: Sendable {
    var url: URL
    var startTime: Double
}

struct AppAudioPlacement: Equatable, Sendable {
    var sourceStart: Double
    var destinationStart: Double
    var length: Double

    static func make(audioStart: Double, recordingStart: Double, audioDuration: Double, videoDuration: Double) -> AppAudioPlacement? {
        let offset = audioStart - recordingStart
        let sourceStart = max(0, -offset)
        let destinationStart = max(0, offset)
        let length = min(audioDuration - sourceStart, videoDuration - destinationStart)
        guard length > 0 else { return nil }
        return AppAudioPlacement(sourceStart: sourceStart, destinationStart: destinationStart, length: length)
    }
}

final class AppAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.adrian.ishare.AppAudioRecorder")
    private let url = FileManager.default.temporaryDirectory.appending(path: "ishare-app-audio-\(UUID().uuidString).m4a")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startTime: Double?
    private var lastTime: CMTime = .invalid
    private var isStopped = false
    var onSamples: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(filter: SCContentFilter) async -> Bool {
        let stream = SCStream(filter: filter, configuration: RecordingAudioFilter.audioOnlyConfiguration(), delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            return true
        } catch {
            Log.capture.error("Couldn't capture the selected apps' audio: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func stop() async -> AppAudioClip? {
        try? await stream?.stopCapture()
        stream = nil
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                isStopped = true
                guard let writer, let input, let startTime, writer.status == .writing else {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: nil)
                    return
                }
                input.markAsFinished()
                if lastTime.isValid { writer.endSession(atSourceTime: lastTime) }
                writer.finishWriting { [self] in
                    continuation.resume(returning: self.writer?.status == .completed ? AppAudioClip(url: url, startTime: startTime) : nil)
                }
            }
        }
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, !isStopped, sampleBuffer.isValid else { return }
        if writer == nil {
            prepareWriter(at: sampleBuffer.presentationTimeStamp)
        }
        guard let input, input.isReadyForMoreMediaData, writer?.status == .writing else { return }
        if input.append(sampleBuffer) {
            lastTime = CMTimeAdd(sampleBuffer.presentationTimeStamp, sampleBuffer.duration.isValid ? sampleBuffer.duration : .zero)
        }
        if let onSamples, let samples = PCMBufferConverter.pcmBuffer(from: sampleBuffer) {
            onSamples(samples)
        }
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        Log.capture.error("App audio capture stopped: \(error.localizedDescription, privacy: .public)")
    }

    private func prepareWriter(at time: CMTime) {
        guard time.isNumeric, let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000,
            ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return }
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: time)
        startTime = time.seconds
        self.writer = writer
        self.input = input
    }
}

enum AppAudioMuxer {
    static func merge(_ clip: AppAudioClip, into url: URL, recordingStart: Double, pauses: RecordingPauseTimeline = RecordingPauseTimeline()) async throws {
        let recording = AVURLAsset(url: url)
        let audio = AVURLAsset(url: clip.url)
        let videoDuration = try await recording.load(.duration).seconds
        let audioDuration = try await audio.load(.duration).seconds
        let segments = pauses.segments(sourceStart: clip.startTime, sourceDuration: audioDuration, recordingStart: recordingStart, outputDuration: videoDuration)
        guard let audioTrack = try await audio.loadTracks(withMediaType: .audio).first, !segments.isEmpty else { return }

        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: try await recording.load(.duration))
        for track in try await recording.load(.tracks) {
            let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            try copy?.insertTimeRange(fullRange, of: track, at: .zero)
            if track.mediaType == .video {
                copy?.preferredTransform = try await track.load(.preferredTransform)
            }
        }
        let appTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        for segment in segments {
            try appTrack?.insertTimeRange(
                CMTimeRange(start: CMTime(seconds: segment.sourceStart, preferredTimescale: 48000), duration: CMTime(seconds: segment.duration, preferredTimescale: 48000)),
                of: audioTrack,
                at: CMTime(seconds: segment.outputStart, preferredTimescale: 48000)
            )
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let fileType: AVFileType = url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        let output = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).\(url.pathExtension)")
        try await session.export(to: output, as: fileType)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: output)
    }
}
