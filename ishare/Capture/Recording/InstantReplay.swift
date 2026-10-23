import AVFoundation
import BezelNotification
import Defaults
import IOKit.ps
import ScreenCaptureKit

enum InstantReplayDuration: Int, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case seconds30 = 30
    case seconds60 = 60
    case seconds120 = 120

    var id: Self { self }

    var seconds: Double { Double(rawValue) }

    var title: String {
        switch self {
        case .seconds30: "30 seconds"
        case .seconds60: "1 minute"
        case .seconds120: "2 minutes"
        }
    }
}

struct ReplaySegment: Hashable, Sendable {
    var url: URL
    var start: Double
    var end: Double

    var duration: Double { max(0, end - start) }
}

struct ReplaySegmentRing: Sendable {
    let capacity: Double
    private(set) var segments: [ReplaySegment] = []

    init(capacity: Double) {
        self.capacity = capacity
    }

    var totalDuration: Double {
        segments.reduce(0) { $0 + $1.duration }
    }

    @discardableResult
    mutating func append(_ segment: ReplaySegment) -> [ReplaySegment] {
        guard segment.duration > 0 else { return [segment] }
        segments.append(segment)
        var evicted: [ReplaySegment] = []
        while let oldest = segments.first, segments.count > 1, totalDuration - oldest.duration >= capacity {
            evicted.append(segments.removeFirst())
        }
        return evicted
    }

    mutating func removeAll() -> [ReplaySegment] {
        defer { segments.removeAll() }
        return segments
    }

    func replayWindow() -> (segments: [ReplaySegment], trimStart: Double) {
        (segments, max(0, totalDuration - capacity))
    }

    static func shouldRotate(segmentStart: Double, now: Double, segmentLength: Double) -> Bool {
        now - segmentStart >= segmentLength
    }
}

struct InstantReplayConditions: Equatable, Sendable {
    static let minimumBatteryLevel = 0.2

    var isScreenLocked = false
    var isAsleep = false
    var isOnBattery = false
    var batteryLevel: Double?

    var shouldPause: Bool {
        if isScreenLocked || isAsleep { return true }
        guard isOnBattery, let batteryLevel else { return false }
        return batteryLevel < Self.minimumBatteryLevel
    }
}

enum PowerSourceReader {
    static func read(into conditions: inout InstantReplayConditions) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        conditions.isOnBattery = providing == kIOPMBatteryPowerKey
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Double,
                let maximum = description[kIOPSMaxCapacityKey] as? Double,
                maximum > 0
            else { continue }
            conditions.batteryLevel = current / maximum
            return
        }
        conditions.batteryLevel = nil
    }
}

final class ReplaySegmentWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let segmentLength: Double = 5

    let queue = DispatchQueue(label: "dev.adrian.ishare.InstantReplay")
    private let directory: URL
    private let videoSize: CGSize
    private let frameRate: Int
    private let recordsAudio: Bool
    private var ring: ReplaySegmentRing
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var segmentURL: URL?
    private var segmentStart: Double?
    private var lastVideoTime: CMTime = .invalid
    private var isStopped = false

    init(directory: URL, videoSize: CGSize, frameRate: Int, recordsAudio: Bool, capacity: Double) {
        self.directory = directory
        self.videoSize = videoSize
        self.frameRate = frameRate
        self.recordsAudio = recordsAudio
        ring = ReplaySegmentRing(capacity: capacity)
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isStopped, sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            appendVideo(sampleBuffer)
        case .audio:
            appendAudio(sampleBuffer)
        default:
            break
        }
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        Log.capture.error("Instant replay stream stopped: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in InstantReplay.shared.streamDidStop() }
    }

    func snapshot() async -> (segments: [ReplaySegment], trimStart: Double) {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                closeSegment { [self] in
                    continuation.resume(returning: ring.replayWindow())
                }
            }
        }
    }

    func discard() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                isStopped = true
                writer?.cancelWriting()
                writer = nil
                videoInput = nil
                audioInput = nil
                _ = ring.removeAll()
                try? FileManager.default.removeItem(at: directory)
                continuation.resume()
            }
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard Self.isCompleteFrame(sampleBuffer) else { return }
        let time = sampleBuffer.presentationTimeStamp
        if let segmentStart, ReplaySegmentRing.shouldRotate(segmentStart: segmentStart, now: time.seconds, segmentLength: Self.segmentLength) {
            closeSegment {}
        }
        if writer == nil {
            openSegment(at: time)
        }
        guard let videoInput, videoInput.isReadyForMoreMediaData, writer?.status == .writing else { return }
        if videoInput.append(sampleBuffer) {
            lastVideoTime = time
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput, let segmentStart, writer?.status == .writing,
            sampleBuffer.presentationTimeStamp.seconds >= segmentStart,
            audioInput.isReadyForMoreMediaData
        else { return }
        audioInput.append(sampleBuffer)
    }

    private func openSegment(at time: CMTime) {
        guard time.isNumeric else { return }
        let url = directory.appending(path: "segment-\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let video = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: InstantReplayEncoding.bitRate(for: videoSize, frameRate: frameRate),
                    AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                    AVVideoExpectedSourceFrameRateKey: frameRate,
                ],
            ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { return }
        writer.add(video)
        var audio: AVAssetWriterInput?
        if recordsAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audio = input
            }
        }
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        videoInput = video
        audioInput = audio
        segmentURL = url
        segmentStart = time.seconds
        lastVideoTime = .invalid
    }

    private func closeSegment(then completion: @escaping @Sendable () -> Void) {
        guard let writer, let videoInput, let segmentURL, let segmentStart, writer.status == .writing, lastVideoTime.isValid else {
            self.writer?.cancelWriting()
            resetSegment()
            completion()
            return
        }
        let end = lastVideoTime.seconds + 1 / Double(max(1, frameRate))
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
        resetSegment()
        let finishing = FinishingWriter(writer: writer)
        writer.finishWriting { [self] in
            queue.async { [self] in
                if finishing.writer.status == .completed, !isStopped {
                    let evicted = ring.append(ReplaySegment(url: segmentURL, start: segmentStart, end: end))
                    evicted.forEach { try? FileManager.default.removeItem(at: $0.url) }
                } else {
                    try? FileManager.default.removeItem(at: segmentURL)
                }
                completion()
            }
        }
    }

    private func resetSegment() {
        writer = nil
        videoInput = nil
        audioInput = nil
        segmentURL = nil
        segmentStart = nil
        lastVideoTime = .invalid
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[SCStreamFrameInfo.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete && sampleBuffer.imageBuffer != nil
    }
}

private struct FinishingWriter: @unchecked Sendable {
    let writer: AVAssetWriter
}

enum InstantReplayEncoding {
    static func bitRate(for size: CGSize, frameRate: Int) -> Int {
        let pixels = Double(max(1, size.width * size.height))
        return Int(min(40_000_000, max(1_500_000, pixels * Double(max(1, frameRate)) * 0.1)))
    }
}

enum InstantReplayExporter {
    static func export(_ segments: [ReplaySegment], trimStart: Double, to output: URL) async throws {
        let composition = AVMutableComposition()
        let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var audio: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                try video?.insertTimeRange(range, of: track, at: cursor)
            }
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                if audio == nil {
                    audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try audio?.insertTimeRange(range, of: track, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        guard cursor.seconds > 0,
            let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw RecordingError.notRecording }
        let start = CMTime(seconds: min(trimStart, cursor.seconds), preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: start, end: cursor)
        let fileType: AVFileType = output.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        try await session.export(to: output, as: fileType)
    }
}

@MainActor
final class InstantReplay: ObservableObject {
    static let shared = InstantReplay()

    static var isRunning: Bool { shared.isRunning }

    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var isSaving = false

    private var stream: SCStream?
    private var writer: ReplaySegmentWriter?
    private var settingsTask: Task<Void, Never>?
    private var powerTimer: Timer?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var conditions = InstantReplayConditions()
    private var isStarting = false

    func activate() {
        guard settingsTask == nil else { return }
        settingsTask = Task { @MainActor [weak self] in
            for await _ in Defaults.updates(
                [.instantReplayEnabled, .instantReplayDuration, .instantReplayResolution, .instantReplayFrameRate, .recordAudio, .recordPointer], initial: true)
            {
                await self?.reconfigure()
            }
        }
    }

    func save() async {
        guard isRunning, let writer, !isSaving else {
            BezelNotification.show(messageText: "Instant replay isn't running".localized(), icon: ToastIcon)
            return
        }
        isSaving = true
        defer { isSaving = false }
        let snapshot = await writer.snapshot()
        let pinned = Self.pin(snapshot.segments)
        defer { pinned.first.map { try? FileManager.default.removeItem(at: $0.url.deletingLastPathComponent()) } }
        guard !pinned.isEmpty else {
            BezelNotification.show(messageText: "Nothing to replay yet".localized(), icon: ToastIcon)
            return
        }
        let output = RecordingFlow.recordingURL()
        do {
            try await ProcessingHUDPresenter.run("Saving instant replay…".localized()) { _ in
                try await InstantReplayExporter.export(pinned, trimStart: snapshot.trimStart, to: output)
            }
        } catch {
            Log.capture.error("Saving the instant replay failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Saving the instant replay failed".localized(), icon: ToastIcon)
            return
        }
        await CaptureSession.finishInstantReplay(output)
    }

    func streamDidStop() {
        Task { await stop() }
    }

    private func reconfigure() async {
        await stop()
        if Defaults[.instantReplayEnabled] {
            startMonitoring()
            await startIfAllowed()
        } else {
            stopMonitoring()
        }
    }

    private func startIfAllowed() async {
        PowerSourceReader.read(into: &conditions)
        isPaused = conditions.shouldPause
        guard Defaults[.instantReplayEnabled], !conditions.shouldPause, !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            try await start()
        } catch {
            Log.capture.error("Instant replay couldn't start: \(error.localizedDescription, privacy: .public)")
            await stop()
        }
    }

    private func start() async throws {
        let content = try await ScreenshotEngine.shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingApplications: ScreenshotEngine.excludedApplications(in: content), exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let pixelSize = CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale)
        let size = Defaults[.instantReplayResolution].outputSize(for: pixelSize)
        let frameRate = Defaults[.instantReplayFrameRate]
        let recordsAudio = RecordingAudioSource.current != .none

        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = frameRate.minimumFrameInterval
        configuration.queueDepth = 5
        configuration.showsCursor = Defaults[.recordPointer]
        configuration.capturesAudio = recordsAudio
        configuration.excludesCurrentProcessAudio = true

        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-instant-replay-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let writer = ReplaySegmentWriter(
            directory: directory, videoSize: size, frameRate: frameRate.rawValue, recordsAudio: recordsAudio, capacity: Defaults[.instantReplayDuration].seconds)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: writer)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        if recordsAudio {
            try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue)
        }
        self.writer = writer
        self.stream = stream
        try await stream.startCapture()
        isRunning = true
        Log.capture.info("Instant replay started")
    }

    private func stop() async {
        let activeStream = stream
        let activeWriter = writer
        stream = nil
        writer = nil
        isRunning = false
        try? await activeStream?.stopCapture()
        await activeWriter?.discard()
    }

    private func startMonitoring() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(distributed, "com.apple.screenIsLocked") { $0.isScreenLocked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.isScreenLocked = false }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.isAsleep = false }
        powerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await InstantReplay.shared.conditionsChanged() }
        }
    }

    private func stopMonitoring() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        powerTimer?.invalidate()
        powerTimer = nil
        conditions = InstantReplayConditions()
        isPaused = false
    }

    private func observe(_ center: NotificationCenter, _ name: String, update: @escaping @MainActor (inout InstantReplayConditions) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                update(&InstantReplay.shared.conditions)
                Task { @MainActor in await InstantReplay.shared.conditionsChanged() }
            }
        }
        observers.append((center, token))
    }

    private func conditionsChanged() async {
        PowerSourceReader.read(into: &conditions)
        let shouldPause = conditions.shouldPause
        isPaused = shouldPause
        if shouldPause, isRunning {
            Log.capture.info("Instant replay paused")
            await stop()
        } else if !shouldPause, !isRunning {
            await startIfAllowed()
        }
    }

    private static func pin(_ segments: [ReplaySegment]) -> [ReplaySegment] {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-instant-replay-save-\(UUID().uuidString)", directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return [] }
        return segments.compactMap { segment in
            let copy = directory.appending(path: segment.url.lastPathComponent)
            do {
                try FileManager.default.linkItem(at: segment.url, to: copy)
            } catch {
                guard (try? FileManager.default.copyItem(at: segment.url, to: copy)) != nil else { return nil }
            }
            var pinned = segment
            pinned.url = copy
            return pinned
        }
    }
}
