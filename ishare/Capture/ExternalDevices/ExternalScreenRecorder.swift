@preconcurrency import AVFoundation
import CoreImage
import Foundation
import ishareCore

enum ExternalScreenCaptureError: LocalizedError {
    case deviceUnavailable
    case cannotAddInput
    case noFrame
    case notRecording

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The device is no longer connected".localized()
        case .cannotAddInput: "The device's screen can't be captured".localized()
        case .noFrame: "The device didn't send its screen".localized()
        case .notRecording: "No recording is in progress".localized()
        }
    }
}

final class ExternalScreenRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.adrian.ishare.ExternalScreenRecorder")
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let context = CIContext(options: [.cacheIntermediates: false])

    private var fileURL: URL?
    private var fileType: AVFileType = .mp4
    private var codec: AVVideoCodecType = .h264
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var canvas = CGSize.zero
    private var firstTime: Double?
    private var lastVideoTime = CMTime.invalid
    private var pauses = RecordingPauseTimeline()
    private var isStopping = false

    var clockTime: Double {
        CMClockGetTime(session.synchronizationClock ?? CMClockGetHostTimeClock()).seconds
    }

    var recordedFileSize: Int64 {
        guard let fileURL, let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(size)
    }

    func start(device: AVCaptureDevice, fileURL: URL, hevc: Bool) throws {
        self.fileURL = fileURL
        fileType = fileURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        codec = hevc ? .hevc : .h264
        try? FileManager.default.removeItem(at: fileURL)
        try configure(device: device, recordsAudio: true)
        queue.async { [self] in session.startRunning() }
    }

    private func configure(device: AVCaptureDevice, recordsAudio: Bool) throws {
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw ExternalScreenCaptureError.cannotAddInput }
        session.addInput(input)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { throw ExternalScreenCaptureError.cannotAddInput }
        session.addOutput(videoOutput)
        if recordsAudio, session.canAddOutput(audioOutput) {
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(audioOutput)
        }
    }

    func pause() {
        let now = clockTime
        queue.async { [self] in pauses.pause(at: now) }
    }

    func resume() {
        let now = clockTime
        queue.async { [self] in pauses.resume(at: now) }
    }

    func stop() async -> Result<URL, any Error> {
        let state: (AVAssetWriter?, URL?, CMTime) = queue.sync {
            isStopping = true
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            return (writer, fileURL, lastVideoTime)
        }
        let session = self.session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                session.stopRunning()
                continuation.resume()
            }
        }
        guard let writer = state.0, let url = state.1 else { return .failure(ExternalScreenCaptureError.noFrame) }
        guard writer.status == .writing else { return .failure(writer.error ?? ExternalScreenCaptureError.notRecording) }
        if state.2.isValid {
            writer.endSession(atSourceTime: state.2)
        }
        await writer.finishWriting()
        if writer.status == .completed {
            return .success(url)
        }
        return .failure(writer.error ?? ExternalScreenCaptureError.notRecording)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard !isStopping, sampleBuffer.isValid else { return }
        if output === videoOutput {
            appendVideo(sampleBuffer)
        } else {
            appendAudio(sampleBuffer)
        }
    }

    private func outputTime(for sampleBuffer: CMSampleBuffer) -> CMTime? {
        let time = sampleBuffer.presentationTimeStamp
        guard time.isNumeric, let firstTime else { return nil }
        guard let offset = pauses.outputTime(of: time.seconds, recordingStart: firstTime), offset >= 0 else { return nil }
        return CMTime(seconds: firstTime + offset, preferredTimescale: time.timescale > 0 ? max(time.timescale, 600) : 600)
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        if writer == nil {
            startWriter(with: pixelBuffer, at: sampleBuffer.presentationTimeStamp)
        }
        guard let input = videoInput, let adaptor, input.isReadyForMoreMediaData, let time = outputTime(for: sampleBuffer) else { return }
        guard !lastVideoTime.isValid || time > lastVideoTime else { return }
        let frame = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let buffer = ExternalScreenGeometry.needsLetterboxing(frame: frame, canvas: canvas) ? letterboxed(pixelBuffer, frame: frame) : pixelBuffer
        guard let buffer, adaptor.append(buffer, withPresentationTime: time) else { return }
        lastVideoTime = time
    }

    private func letterboxed(_ pixelBuffer: CVPixelBuffer, frame: CGSize) -> CVPixelBuffer? {
        guard let pool = adaptor?.pixelBufferPool else { return nil }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output else { return nil }
        let target = ExternalScreenGeometry.fittedRect(for: frame, in: canvas)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by: CGAffineTransform(scaleX: target.width / frame.width, y: target.height / frame.height))
            .transformed(by: CGAffineTransform(translationX: target.minX, y: target.minY))
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvas))
        context.render(image.composited(over: background), to: output)
        return output
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let input = audioInput, writer?.status == .writing, input.isReadyForMoreMediaData, let time = outputTime(for: sampleBuffer) else { return }
        let shift = CMTimeSubtract(time, sampleBuffer.presentationTimeStamp)
        guard let retimed = Self.retimed(sampleBuffer, by: shift) else { return }
        input.append(retimed)
    }

    private static func retimed(_ sampleBuffer: CMSampleBuffer, by shift: CMTime) -> CMSampleBuffer? {
        guard shift != .zero else { return sampleBuffer }
        let timing = (try? sampleBuffer.sampleTimingInfos()) ?? []
        let shifted = timing.map { info in
            CMSampleTimingInfo(
                duration: info.duration,
                presentationTimeStamp: info.presentationTimeStamp.isValid ? CMTimeAdd(info.presentationTimeStamp, shift) : info.presentationTimeStamp,
                decodeTimeStamp: info.decodeTimeStamp.isValid ? CMTimeAdd(info.decodeTimeStamp, shift) : info.decodeTimeStamp
            )
        }
        return try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: shifted)
    }

    private func startWriter(with pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard let fileURL, time.isNumeric else { return }
        let native = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        canvas = ExternalScreenGeometry.outputSize(for: native)
        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: fileType)
            let video = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: codec,
                    AVVideoWidthKey: Int(canvas.width),
                    AVVideoHeightKey: Int(canvas.height),
                ])
            video.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: video,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferWidthKey as String: Int(canvas.width),
                    kCVPixelBufferHeightKey as String: Int(canvas.height),
                ])
            guard writer.canAdd(video) else { return }
            writer.add(video)
            let audio = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000,
                ])
            audio.expectsMediaDataInRealTime = true
            if session.outputs.contains(audioOutput), writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
            guard writer.startWriting() else {
                Log.capture.error("Starting the device recording failed: \(writer.error?.localizedDescription ?? "", privacy: .public)")
                return
            }
            writer.startSession(atSourceTime: time)
            firstTime = time.seconds
            self.writer = writer
            videoInput = video
            self.adaptor = adaptor
            Log.capture.info("Recording the device screen at \(Int(self.canvas.width))×\(Int(self.canvas.height))")
        } catch {
            Log.capture.error("Creating the device recording failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

final class ExternalScreenFrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let settleFrames = 3
    private static let settleTime: Double = 0.6

    private let queue = DispatchQueue(label: "dev.adrian.ishare.ExternalScreenFrameGrabber")
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private var continuation: CheckedContinuation<CGImage, any Error>?
    private var latest: CGImage?
    private var frameCount = 0

    func grab(from device: AVCaptureDevice, timeout: Double = 10) async throws -> CGImage {
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw ExternalScreenCaptureError.cannotAddInput
        }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw ExternalScreenCaptureError.cannotAddInput
        }
        session.addOutput(output)
        session.commitConfiguration()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                session.startRunning()
                queue.asyncAfter(deadline: .now() + timeout) { [self] in finish() }
            }
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        session.stopRunning()
        if let latest {
            continuation.resume(returning: latest)
        } else {
            continuation.resume(throwing: ExternalScreenCaptureError.noFrame)
        }
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard continuation != nil, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        latest = cgImage
        frameCount += 1
        if frameCount == 1 {
            queue.asyncAfter(deadline: .now() + Self.settleTime) { [self] in finish() }
        } else if frameCount >= Self.settleFrames {
            finish()
        }
    }
}
