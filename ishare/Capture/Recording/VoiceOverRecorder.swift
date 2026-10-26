import AVFoundation
import Defaults
import Foundation
import ishareCore

enum VoiceOverPhase: Equatable {
    case inactive
    case countdown(Int)
    case recording
    case paused
}

@MainActor
final class VoiceOverRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var clips: [VoiceOverClip] = []

    private let directory: URL
    private var recorder: AVAudioRecorder?
    private var clipStart: Double = 0
    private var meterTask: Task<Void, Never>?

    init() {
        directory = FileManager.default.temporaryDirectory.appending(path: "ishare-voiceover-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    func beginClip(at videoTime: Double) throws {
        endClip()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "take-\(UUID().uuidString).m4a", directoryHint: .notDirectory)
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw VoiceOverError.recordingFailed }
        self.recorder = recorder
        clipStart = videoTime
        startMetering()
    }

    func endClip() {
        guard let recorder else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        stopMetering()
        if duration > 0.05 {
            clips.append(VoiceOverClip(url: recorder.url, videoTime: clipStart, duration: duration))
        } else {
            try? FileManager.default.removeItem(at: recorder.url)
        }
    }

    func discardAll() {
        recorder?.stop()
        recorder = nil
        stopMetering()
        for clip in clips { try? FileManager.default.removeItem(at: clip.url) }
        clips = []
    }

    func tearDown() {
        discardAll()
        try? FileManager.default.removeItem(at: directory)
    }

    static func levels(for clips: [VoiceOverClip]) async -> LevelSeries? {
        var series: [LevelSeries] = []
        for clip in clips {
            guard var levels = try? await MediaLevelAnalyzer.audioLevels(of: clip.url) else { continue }
            levels.start = clip.videoTime
            series.append(levels)
        }
        return LevelSeries.loudest(series)
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder else { return }
                recorder.updateMeters()
                level = Self.normalized(decibels: recorder.averagePower(forChannel: 0))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        level = 0
    }

    nonisolated static func normalized(decibels: Float) -> Float {
        min(1, max(0, (decibels + 60) / 60))
    }
}

enum VoiceOverError: LocalizedError {
    case recordingFailed
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .recordingFailed: "The microphone couldn't be recorded.".localized()
        case .microphoneDenied: "ishare needs microphone access to record a voice-over. Allow it in System Settings › Privacy & Security › Microphone.".localized()
        }
    }
}
