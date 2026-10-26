@preconcurrency import AVFAudio
import Combine
import Defaults
import Foundation
import ScreenCaptureKit
import Synchronization

struct CapturedFrame: Sendable {
    static let invalid = CapturedFrame(surface: nil, contentRect: .zero, contentScale: 0, scaleFactor: 0)

    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

final class RecordingStartClock: Sendable {
    private let firstFrameTime = Mutex<Double?>(nil)

    var time: Double? {
        firstFrameTime.withLock { $0 }
    }

    func reset() {
        firstFrameTime.withLock { $0 = nil }
    }

    func mark(_ time: CMTime) {
        guard time.isNumeric else { return }
        firstFrameTime.withLock { first in
            if first == nil { first = time.seconds }
        }
    }
}

enum RecordingError: LocalizedError {
    case notRecording
    case finalizeTimedOut

    var errorDescription: String? {
        switch self {
        case .notRecording: "No recording is in progress"
        case .finalizeTimedOut: "The recording could not be finalized"
        }
    }
}

final class CaptureEngine: NSObject, @unchecked Sendable, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var fileURL: URL?
    private var recordingOutput: SCRecordingOutput?
    private var segmentURLs: [URL] = []
    private var finishedSegmentsSize: Int64 = 0
    private var outputFileType: AVFileType = .mp4
    private var videoCodec: AVVideoCodecType = .h264

    var recordedFileSize: Int64 {
        if let recordingOutput, recordingOutput.recordedFileSize > 0 {
            return finishedSegmentsSize + Int64(recordingOutput.recordedFileSize)
        }
        guard recordingOutput != nil, let url = segmentURLs.last, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return finishedSegmentsSize }
        return finishedSegmentsSize + Int64(size)
    }

    var isPaused: Bool {
        stream != nil && recordingOutput == nil
    }
    private let videoSampleBufferQueue = DispatchQueue(label: "dev.adrian.ishare.VideoSampleBufferQueue")
    private let audioSampleBufferQueue = DispatchQueue(label: "dev.adrian.ishare.AudioSampleBufferQueue")
    private let micAudioSampleBufferQueue = DispatchQueue(label: "dev.adrian.ishare.MicAudioSampleBufferQueue")

    private let systemAudioMeter = PowerMeter()
    private let microphoneMeter = PowerMeter()
    var audioLevels: RecordingAudioLevels {
        RecordingAudioLevels(system: systemAudioMeter.levels, microphone: microphoneMeter.levels)
    }

    private var streamOutput: CaptureEngineStreamOutput?
    let startClock = RecordingStartClock()
    private let finishLock = NSLock()
    private var finishContinuation: CheckedContinuation<Void, any Error>?
    private var didFinishRecording = false
    private var recordingError: (any Error)?

    @MainActor func startCapture(
        configuration: SCStreamConfiguration, filter: SCContentFilter, fileURL: URL, showsNativeClicks: Bool, showsCursor: Bool, audioPlan: RecordingAudioPlan
    ) -> AsyncThrowingStream<CapturedFrame, any Error> {
        let recordMP4 = Defaults[.recordMP4]
        let useHEVC = RecordingDefaults[.useHEVC]
        let recordMic = RecordingDefaults[.recordMic]
        let microphoneID = recordMic ? CaptureDevices.connectedMicrophoneID(Defaults[.microphoneDeviceID]) : nil
        resetFinishState()
        startClock.reset()
        segmentURLs = [fileURL]
        finishedSegmentsSize = 0
        outputFileType = recordMP4 ? .mp4 : .mov
        videoCodec = useHEVC ? .hevc : .h264

        return AsyncThrowingStream<CapturedFrame, any Error> { continuation in
            let output = CaptureEngineStreamOutput(continuation: continuation, startClock: startClock)
            streamOutput = output
            output.capturedFrameHandler = { continuation.yield($0) }
            output.systemAudioHandler = { [weak self] in self?.systemAudioMeter.process(buffer: $0) }
            output.microphoneHandler = { [weak self] in self?.microphoneMeter.process(buffer: $0) }

            do {
                RecordingAudioFilter.apply(audioPlan, to: configuration)
                configuration.captureMicrophone = recordMic
                configuration.microphoneCaptureDeviceID = microphoneID
                configuration.showsCursor = showsCursor
                configuration.showMouseClicks = showsNativeClicks

                let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
                self.stream = stream
                self.fileURL = fileURL

                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioSampleBufferQueue)
                try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: micAudioSampleBufferQueue)

                let recordingOutput = makeRecordingOutput(to: fileURL)
                try stream.addRecordingOutput(recordingOutput)
                self.recordingOutput = recordingOutput
                stream.startCapture()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func makeRecordingOutput(to url: URL) -> SCRecordingOutput {
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = url
        configuration.outputFileType = outputFileType
        configuration.videoCodecType = videoCodec
        return SCRecordingOutput(configuration: configuration, delegate: self)
    }

    private func resetFinishState() {
        finishLock.withLock {
            didFinishRecording = false
            recordingError = nil
            finishContinuation = nil
        }
    }

    func pauseRecording() async -> Bool {
        guard let stream, let output = recordingOutput else { return false }
        resetFinishState()
        do {
            try stream.removeRecordingOutput(output)
        } catch {
            Log.capture.error("Pausing the recording failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        recordingOutput = nil
        try? await waitForRecordingToFinish(timeout: .seconds(8))
        finishedSegmentsSize += segmentURLs.last.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init) ?? 0
        return true
    }

    func resumeRecording() -> Bool {
        guard let stream, recordingOutput == nil, let fileURL else { return false }
        let url = RecordingSegments.segmentURL(for: fileURL, index: segmentURLs.count)
        try? FileManager.default.removeItem(at: url)
        let output = makeRecordingOutput(to: url)
        resetFinishState()
        do {
            try stream.addRecordingOutput(output)
        } catch {
            Log.capture.error("Resuming the recording failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        segmentURLs.append(url)
        recordingOutput = output
        return true
    }

    func stopCapture() async -> Result<URL, any Error> {
        guard let url = fileURL else { return .failure(RecordingError.notRecording) }
        let activeStream = stream
        let wasPaused = recordingOutput == nil
        let segments = segmentURLs
        stream = nil
        fileURL = nil
        recordingOutput = nil
        segmentURLs = []
        finishedSegmentsSize = 0
        try? await activeStream?.stopCapture()
        if !wasPaused {
            do {
                try await waitForRecordingToFinish(timeout: .seconds(8))
            } catch {
                guard FileManager.default.fileExists(atPath: segments.last?.path ?? url.path) else { return .failure(error) }
            }
        }
        guard segments.count > 1 else {
            return FileManager.default.fileExists(atPath: url.path) ? .success(url) : .failure(RecordingError.notRecording)
        }
        do {
            try await RecordingSegments.concatenate(segments, into: url, fileType: outputFileType)
            return .success(url)
        } catch {
            Log.capture.error("Joining the paused recording failed: \(error.localizedDescription, privacy: .public)")
            return FileManager.default.fileExists(atPath: url.path) ? .success(url) : .failure(error)
        }
    }

    private func waitForRecordingToFinish(timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    let state: (Bool, (any Error)?) = finishLock.withLock {
                        if didFinishRecording || recordingError != nil {
                            return (true, recordingError)
                        }
                        finishContinuation = continuation
                        return (false, nil)
                    }
                    if state.0 {
                        if let error = state.1 {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RecordingError.finalizeTimedOut
            }
            try await group.next()
            group.cancelAll()
            finishLock.withLock {
                finishContinuation = nil
            }
        }
    }

    private func completeFinish(error: (any Error)?) {
        let continuation = finishLock.withLock { () -> CheckedContinuation<Void, any Error>? in
            didFinishRecording = error == nil
            recordingError = error
            let pending = finishContinuation
            finishContinuation = nil
            return pending
        }
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        completeFinish(error: nil)
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
        completeFinish(error: error)
    }

    func meterSystemAudio(_ buffer: AVAudioPCMBuffer) {
        systemAudioMeter.process(buffer: buffer)
    }

    func update(configuration: SCStreamConfiguration, filter: SCContentFilter) async {
        try? await stream?.updateConfiguration(configuration)
        try? await stream?.updateContentFilter(filter)
    }
}

@MainActor
private class CaptureEngineStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var systemAudioHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var microphoneHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var capturedFrameHandler: (@Sendable (CapturedFrame) -> Void)?
    private var continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation?
    private nonisolated let startClock: RecordingStartClock

    init(continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation?, startClock: RecordingStartClock) {
        self.continuation = continuation
        self.startClock = startClock
    }

    nonisolated func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch outputType {
        case .screen:
            guard let frame = createFrame(for: sampleBuffer) else { return }
            startClock.mark(sampleBuffer.presentationTimeStamp)
            Task { @MainActor [self] in
                capturedFrameHandler?(frame)
            }
        case .audio:
            guard let samples = PCMBufferConverter.pcmBuffer(from: sampleBuffer) else { return }
            Task { @MainActor [self] in
                systemAudioHandler?(samples)
            }
        case .microphone:
            guard let samples = PCMBufferConverter.pcmBuffer(from: sampleBuffer) else { return }
            Task { @MainActor [self] in
                microphoneHandler?(samples)
            }
        @unknown default:
            break
        }
    }

    nonisolated func stream(_: SCStream, didStopWithError error: any Error) {
        let code = (error as NSError).code
        Task { @MainActor [self] in
            if code == -3817 {
                ContentSharingPickerManager.shared.deactivatePicker()
                CaptureSession.stopRecording()
            } else {
                NSLog("Stream stopped with error: %@", error.localizedDescription)
            }
            continuation?.finish(throwing: error)
        }
    }

    private nonisolated func createFrame(for sampleBuffer: CMSampleBuffer) -> CapturedFrame? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first,
            let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue),
            status == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer,
            let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
            let contentRectDict = attachments[.contentRect],
            let contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
            let contentScale = attachments[.contentScale] as? CGFloat,
            let scaleFactor = attachments[.scaleFactor] as? CGFloat
        else { return nil }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)
        return CapturedFrame(surface: surface, contentRect: contentRect, contentScale: contentScale, scaleFactor: scaleFactor)
    }
}
