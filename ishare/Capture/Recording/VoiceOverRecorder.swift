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
protocol VoiceOverTake: AnyObject {
    var url: URL { get }
    var duration: Double { get }
    var level: Float { get }
    func stop() async
}

@MainActor
final class SystemMicrophoneTake: VoiceOverTake {
    let url: URL
    private let recorder: AVAudioRecorder

    init(url: URL) throws {
        self.url = url
        recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw VoiceOverError.recordingFailed }
    }

    var duration: Double { recorder.currentTime }

    var level: Float {
        recorder.updateMeters()
        return VoiceOverRecorder.normalized(decibels: recorder.averagePower(forChannel: 0))
    }

    func stop() async {
        recorder.stop()
    }
}

@MainActor
final class CaptureDeviceTake: NSObject, VoiceOverTake, AVCaptureFileOutputRecordingDelegate {
    let url: URL
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private var finished: CheckedContinuation<Void, Never>?
    private var isFinished = false

    init(url: URL, device: AVCaptureDevice) throws {
        self.url = url
        super.init()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw VoiceOverError.recordingFailed }
        session.addInput(input)
        session.addOutput(output)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
        ]
        session.startRunning()
        output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
    }

    var duration: Double {
        let seconds = output.recordedDuration.seconds
        return seconds.isFinite ? seconds : 0
    }

    var level: Float {
        let channels = output.connections.flatMap(\.audioChannels)
        guard let loudest = channels.map(\.averagePowerLevel).max() else { return 0 }
        return VoiceOverRecorder.normalized(decibels: loudest)
    }

    func stop() async {
        if !isFinished {
            await withCheckedContinuation { continuation in
                finished = continuation
                output.stopRecording()
            }
        }
        session.stopRunning()
    }

    nonisolated func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo _: URL, from _: [AVCaptureConnection], error _: Error?) {
        Task { @MainActor in
            isFinished = true
            finished?.resume()
            finished = nil
        }
    }
}

@MainActor
final class VoiceOverRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var clips: [VoiceOverClip] = []
    @Published private(set) var usesFallbackMicrophone = false

    private let directory: URL
    private var take: VoiceOverTake?
    private var clipStart: Double = 0
    private var meterTask: Task<Void, Never>?
    private var pendingStops: [Task<Void, Never>] = []

    init() {
        directory = FileManager.default.temporaryDirectory.appending(path: "ishare-voiceover-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    var isRecording: Bool { take != nil }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    static func microphoneSelection() -> MicrophoneSelection {
        MicrophoneSelection.resolve(
            configuredID: Defaults[.microphoneDeviceID], connectedIDs: CaptureDevices.microphones().filter(\.isConnected).map(\.uniqueID))
    }

    func beginClip(at videoTime: Double) throws {
        endClip()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "take-\(UUID().uuidString).m4a", directoryHint: .notDirectory)
        let selection = Self.microphoneSelection()
        usesFallbackMicrophone = selection.fellBackToDefault
        if let id = selection.deviceID, let device = AVCaptureDevice(uniqueID: id) {
            take = try CaptureDeviceTake(url: url, device: device)
        } else {
            take = try SystemMicrophoneTake(url: url)
        }
        clipStart = videoTime
        startMetering()
    }

    func endClip() {
        guard let take else { return }
        self.take = nil
        stopMetering()
        let duration = take.duration
        let start = clipStart
        let stopping = Task { @MainActor [weak self] in
            await take.stop()
            guard let self else { return }
            if duration > 0.05 {
                clips.append(VoiceOverClip(url: take.url, videoTime: start, duration: duration))
            } else {
                try? FileManager.default.removeItem(at: take.url)
            }
        }
        pendingStops.append(stopping)
    }

    func finishPendingClips() async {
        let stops = pendingStops
        pendingStops = []
        for stop in stops { await stop.value }
    }

    func discardAll() {
        let take = take
        self.take = nil
        stopMetering()
        let stops = pendingStops
        pendingStops = []
        let existing = clips
        clips = []
        Task { @MainActor in
            await take?.stop()
            for stop in stops { await stop.value }
            for url in existing.map(\.url) + [take?.url].compactMap(\.self) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func tearDown() {
        discardAll()
        let directory = directory
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            try? FileManager.default.removeItem(at: directory)
        }
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
                guard let self, let take else { return }
                level = take.level
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
