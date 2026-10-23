import AppKit
import AVFoundation
import Defaults
import ishareCore
import ScreenCaptureKit

struct OverlaySource: Sendable {
    var windowID: CGWindowID?
    var sourceRect: CGRect?
    var contentSize: CGSize

    static func make(for filter: SCContentFilter) -> OverlaySource {
        let contentSize = filter.contentRect.size
        if #available(macOS 15.2, *) {
            if filter.style == .window, let window = filter.includedWindows.first {
                return OverlaySource(windowID: window.windowID, sourceRect: window.frame, contentSize: window.frame.size)
            }
            if let display = filter.includedDisplays.first {
                return OverlaySource(windowID: nil, sourceRect: CGDisplayBounds(display.displayID), contentSize: contentSize)
            }
        }
        return OverlaySource(windowID: nil, sourceRect: nil, contentSize: contentSize)
    }

    func currentRect() -> CGRect? {
        guard let windowID else { return sourceRect }
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
            let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds)
        else { return sourceRect }
        return rect
    }
}

struct OverlayCapture: Sendable {
    var log: OverlayEventLog
    var webcam: WebcamFrameRecorder.Clip?
    var contentSize: CGSize
    var webcamDiameter: CGFloat
    var webcamCorner: WebcamCorner

    var isEmpty: Bool { log.isEmpty && webcam == nil }
}

@MainActor
final class OverlayEventRecorder {
    private let monitor = InputEventMonitor()
    private var log = OverlayEventLog()
    private var source: OverlaySource?
    private var webcamRecorder: WebcamFrameRecorder?
    private var shortcutsOnly = true
    private(set) var capturesClicks = false
    private(set) var isActive = false

    var webcamSession: AVCaptureSession? {
        webcamRecorder?.session
    }

    func start(source: OverlaySource, showsClicks: Bool, showsKeystrokes: Bool, shortcutsOnly: Bool, recordsWebcam: Bool) async {
        _ = await stop()
        log = OverlayEventLog()
        self.source = source
        self.shortcutsOnly = shortcutsOnly
        guard showsClicks || showsKeystrokes || recordsWebcam else { return }
        isActive = true
        if showsClicks {
            monitor.onClick = { [weak self] in self?.recordClick(atCocoaPoint: $0) }
            monitor.startClicks()
            capturesClicks = true
        }
        if showsKeystrokes {
            monitor.onKey = { [weak self] in self?.recordKey($0) }
            if !monitor.startKeys() {
                Log.capture.info("Keystrokes aren't composited because Input Monitoring isn't allowed")
            }
        }
        if recordsWebcam {
            let recorder = WebcamFrameRecorder()
            if await recorder.start(deviceID: Defaults[.webcamDeviceID]) {
                webcamRecorder = recorder
            }
        }
    }

    func update(source: OverlaySource) {
        self.source = source
    }

    func stop() async -> OverlayCapture? {
        monitor.stop()
        monitor.onClick = nil
        monitor.onKey = nil
        capturesClicks = false
        let wasActive = isActive
        isActive = false
        let clip = await webcamRecorder?.stop()
        webcamRecorder = nil
        guard wasActive, let source else { return nil }
        let capture = OverlayCapture(
            log: log,
            webcam: clip,
            contentSize: source.contentSize,
            webcamDiameter: Defaults[.webcamSize].diameter,
            webcamCorner: Defaults[.webcamCorner]
        )
        log = OverlayEventLog()
        return capture.isEmpty ? nil : capture
    }

    private func recordClick(atCocoaPoint point: CGPoint) {
        guard let source, let rect = source.currentRect() else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let globalPoint = OverlayCoordinateMapper.cgGlobalPoint(fromCocoa: point, primaryScreenHeight: primaryHeight)
        log.recordClick(at: globalPoint, sourceRect: rect, time: RecordingClock.now)
    }

    private func recordKey(_ event: RawKeyEvent) {
        guard !event.isRepeat,
            let keystroke = KeystrokeFormatter.keystroke(
                keyCode: event.keyCode,
                characters: event.characters,
                baseCharacters: event.baseCharacters,
                modifiers: event.modifiers,
                shortcutsOnly: shortcutsOnly
            )
        else { return }
        log.recordKey(keystroke, time: RecordingClock.now)
    }
}

final class WebcamFrameRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Clip: Sendable {
        var url: URL
        var startTime: Double
    }

    private static let maximumShortSide: CGFloat = 480

    private let runner = CaptureSessionRunner()
    private let queue = DispatchQueue(label: "dev.adrian.ishare.WebcamFrameRecorder")

    var session: AVCaptureSession { runner.session }
    private let url = FileManager.default.temporaryDirectory.appending(path: "ishare-webcam-\(UUID().uuidString).mov")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startTime: Double?
    private var lastTime: CMTime = .invalid
    private var isStopped = false

    func start(deviceID: String?) async -> Bool {
        guard await CaptureDevices.requestAccess(for: .video),
            let device = CaptureDevices.camera(id: deviceID),
            let deviceInput = try? AVCaptureDeviceInput(device: device)
        else { return false }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        let session = runner.session
        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(deviceInput), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(deviceInput)
        session.addOutput(output)
        session.commitConfiguration()
        runner.start()
        return true
    }

    func stop() async -> Clip? {
        runner.stop()
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                isStopped = true
                guard let writer, let input, let startTime, writer.status == .writing else {
                    continuation.resume(returning: nil)
                    return
                }
                input.markAsFinished()
                if lastTime.isValid { writer.endSession(atSourceTime: lastTime) }
                writer.finishWriting { [self] in
                    continuation.resume(returning: self.writer?.status == .completed ? Clip(url: url, startTime: startTime) : nil)
                }
            }
        }
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard !isStopped, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        if writer == nil {
            prepareWriter(for: pixelBuffer, at: sampleBuffer.presentationTimeStamp)
        }
        guard let input, input.isReadyForMoreMediaData, writer?.status == .writing else { return }
        if input.append(sampleBuffer) {
            lastTime = sampleBuffer.presentationTimeStamp
        }
    }

    private func prepareWriter(for pixelBuffer: CVPixelBuffer, at time: CMTime) {
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let scale = min(1, Self.maximumShortSide / max(1, min(size.width, size.height)))
        let output = ScreenGeometry.evenPixelSize(CGSize(width: size.width * scale, height: size.height * scale))
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(output.width),
                AVVideoHeightKey: Int(output.height),
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return }
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: time)
        let hostTime = CMSyncConvertTime(time, from: runner.session.synchronizationClock ?? CMClockGetHostTimeClock(), to: CMClockGetHostTimeClock())
        startTime = hostTime.seconds
        self.writer = writer
        self.input = input
    }
}
