@preconcurrency import AVFAudio
import Combine
import Defaults
import Foundation
@preconcurrency import ScreenCaptureKit

struct CapturedFrame: Sendable {
    static let invalid = CapturedFrame(surface: nil, contentRect: .zero, contentScale: 0, scaleFactor: 0)

    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
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
    private let videoSampleBufferQueue = DispatchQueue(label: "dev.adrian.ishare.VideoSampleBufferQueue")
    private let audioSampleBufferQueue = DispatchQueue(label: "dev.adrian.ishare.AudioSampleBufferQueue")
    private let micAudioSampleBufferQueue = DispatchQueue(label: "dev.adrian.ishare.MicAudioSampleBufferQueue")

    private let powerMeter = PowerMeter()
    var audioLevels: AudioLevels { powerMeter.levels }

    private var streamOutput: CaptureEngineStreamOutput?
    private let finishLock = NSLock()
    private var finishContinuation: CheckedContinuation<Void, any Error>?
    private var didFinishRecording = false
    private var recordingError: (any Error)?

    @MainActor func startCapture(configuration: SCStreamConfiguration, filter: SCContentFilter, fileURL: URL) -> AsyncThrowingStream<CapturedFrame, any Error> {
        let recordMP4 = Defaults[.recordMP4]
        let useHEVC = Defaults[.useHEVC]
        let recordAudio = Defaults[.recordAudio]
        let recordMic = Defaults[.recordMic]
        let recordPointer = Defaults[.recordPointer]
        let recordClicks = Defaults[.recordClicks]
        finishLock.withLock {
            didFinishRecording = false
            recordingError = nil
            finishContinuation = nil
        }

        return AsyncThrowingStream<CapturedFrame, any Error> { continuation in
            let output = CaptureEngineStreamOutput(continuation: continuation)
            streamOutput = output
            output.capturedFrameHandler = { continuation.yield($0) }
            output.pcmBufferHandler = { [weak self] in self?.powerMeter.process(buffer: $0) }

            do {
                configuration.capturesAudio = recordAudio
                configuration.captureMicrophone = recordMic
                configuration.showsCursor = recordPointer
                configuration.showMouseClicks = recordClicks

                let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
                self.stream = stream
                self.fileURL = fileURL

                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioSampleBufferQueue)
                try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: micAudioSampleBufferQueue)

                let recordingConfiguration = SCRecordingOutputConfiguration()
                recordingConfiguration.outputURL = fileURL
                recordingConfiguration.outputFileType = recordMP4 ? .mp4 : .mov
                recordingConfiguration.videoCodecType = useHEVC ? .hevc : .h264

                let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
                try stream.addRecordingOutput(recordingOutput)
                stream.startCapture()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func stopCapture() async -> Result<URL, any Error> {
        guard let url = fileURL else { return .failure(RecordingError.notRecording) }
        let activeStream = stream
        stream = nil
        fileURL = nil
        try? await activeStream?.stopCapture()
        do {
            try await waitForRecordingToFinish(timeout: .seconds(8))
            return .success(url)
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                return .success(url)
            }
            return .failure(error)
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

    func update(configuration: SCStreamConfiguration, filter: SCContentFilter) async {
        try? await stream?.updateConfiguration(configuration)
        try? await stream?.updateContentFilter(filter)
    }
}

@MainActor
private class CaptureEngineStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var pcmBufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var capturedFrameHandler: (@Sendable (CapturedFrame) -> Void)?
    private var continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation?

    init(continuation: AsyncThrowingStream<CapturedFrame, any Error>.Continuation?) {
        self.continuation = continuation
    }

    nonisolated func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch outputType {
        case .screen:
            guard let frame = createFrame(for: sampleBuffer) else { return }
            Task { @MainActor [self] in
                capturedFrameHandler?(frame)
            }
        case .audio, .microphone:
            guard let samples = createPCMBuffer(for: sampleBuffer) else { return }
            Task { @MainActor [self] in
                pcmBufferHandler?(samples)
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
                AppDelegate.shared.stopRecording()
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

    private nonisolated func createPCMBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        var ablPointer: UnsafePointer<AudioBufferList>?
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            ablPointer = audioBufferList.unsafePointer
        }
        guard let audioBufferList = ablPointer,
              let absd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame)
        else { return nil }
        return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList)
    }
}
