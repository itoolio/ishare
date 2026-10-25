import AppKit
import AVFoundation
import BezelNotification
import Defaults
import Foundation

struct CaptureOptions: Sendable {
    var forceUpload = false
    var openEditor = false
    var destinations: [UploadTarget]?
    var preset: UploadPreset?
    var recordingPreset: RecordingPreset?
    var delay: Int?
    var resultHandler: (@MainActor @Sendable (URL) -> Void)?

    static let standard = CaptureOptions()
}

@MainActor
enum CaptureSession {
    private static var isCapturingImage = false
    private static var pendingRecording: (gif: Bool, options: CaptureOptions)?

    static var isRecording: Bool {
        AppModel.shared.recorder.isRunning
    }

    static func captureImage(_ type: CaptureType, display: Int = 1, options: CaptureOptions = .standard) async {
        guard !isCapturingImage else { return }
        isCapturingImage = true
        Log.capture.info("Starting \(type.rawValue, privacy: .public) capture on display \(display)")
        if type == .TEXT {
            await TextCaptureFlow.captureAndCopy()
            isCapturingImage = false
            return
        }
        let wantsDestinationChoice = DestinationChooser.isRequested()
        let delay = CaptureDelay.effectiveSeconds(for: type, explicit: options.delay, setting: Defaults[.captureDelay])
        let captured = await ImageCaptureFlow.capture(type: type, display: display, delay: delay)
        isCapturingImage = false
        guard let captured else { return }
        ToastPlacement.capturedDisplayID = captured.geometry?.displayID
        var options = options
        if wantsDestinationChoice, let target = DestinationChooser.choose() {
            options.destinations = [target]
        }
        do {
            let fileURL = try ImageCaptureFlow.save(captured)
            Log.capture.info("Saved capture to \(fileURL.path, privacy: .public)")
            if let resultHandler = options.resultHandler {
                ToastPlacement.capturedDisplayID = nil
                resultHandler(fileURL)
                return
            }
            await finish(fileURL: fileURL, kind: .image, options: options)

        } catch {
            Log.capture.error("Saving capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
        }
    }

    static func toggleRecording(gif: Bool = false, region: Bool = false, options: CaptureOptions = .standard) {
        guard !isRecording else {
            stopRecording()
            return
        }
        pendingRecording = (gif, options)
        Task { @MainActor in
            await startRecording(region: region, preset: options.recordingPreset)
        }
    }

    private static func startRecording(region: Bool, preset: RecordingPreset?) async {
        let recorder = AppModel.shared.recorder
        guard await recorder.canRecord else {
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return
        }
        RecordingDefaults.begin(preset)
        let fileURL = RecordingFlow.recordingURL()
        guard region else {
            await recorder.start(fileURL, target: .picker)
            return
        }
        let outcome = await RegionSelector.select(options: .init(showsMagnifier: false, allowsWindowMode: false, hint: "Select the area to record".localized()))
        switch outcome {
        case let .region(screen, rect):
            await recorder.start(fileURL, target: .region(screen, rect))
        case let .fullScreen(screen):
            await recorder.start(fileURL, target: .region(screen, CGRect(origin: .zero, size: screen.frame.size)))
        case .switchToWindow, .cancelled:
            pendingRecording = nil
            RecordingDefaults.end()
        }
    }

    static func recordDevice(_ device: ExternalScreenDevice, options: CaptureOptions = .standard) {
        guard !isRecording else {
            stopRecording()
            return
        }
        pendingRecording = (false, options)
        RecordingDefaults.begin(options.recordingPreset)
        let fileURL = ExternalScreenCaptureSupport.fileURL(for: device, ext: Defaults[.recordMP4] ? "mp4" : "mov", kind: .recordings)
        Task { @MainActor in
            await AppModel.shared.recorder.start(fileURL, target: .device(device))
            if !isRecording {
                pendingRecording = nil
            }
        }
    }

    static func captureDeviceScreenshot(_ device: ExternalScreenDevice, options: CaptureOptions = .standard) async {
        guard !isCapturingImage else { return }
        guard let captureDevice = AVCaptureDevice(uniqueID: device.id) else {
            BezelNotification.show(messageText: ExternalScreenCaptureError.deviceUnavailable.localizedDescription, icon: ToastIcon)
            return
        }
        guard await ExternalScreenCaptureSupport.requestAccess() else {
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return
        }
        isCapturingImage = true
        defer { isCapturingImage = false }
        Log.capture.info("Capturing the screen of \(device.name, privacy: .public)")
        do {
            let image = try await ExternalScreenFrameGrabber().grab(from: captureDevice)
            let fileURL = try ImageCaptureFlow.save(CapturedImage(image: image, suffix: device.fileSuffix))
            if let resultHandler = options.resultHandler {
                resultHandler(fileURL)
                return
            }
            await finish(fileURL: fileURL, kind: .image, options: options)
        } catch {
            Log.capture.error("Capturing \(device.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
        }
    }

    static func stopRecording() {
        let pending = pendingRecording ?? (false, .standard)
        pendingRecording = nil
        let wantsDestinationChoice = DestinationChooser.isRequested()
        Task { @MainActor in
            ContentSharingPickerManager.shared.deactivatePicker()
            switch await AppModel.shared.recorder.stop() {
            case let .success(url):
                var options = pending.options
                if wantsDestinationChoice, let target = DestinationChooser.choose() {
                    options.destinations = [target]
                }
                await finishRecording(url, gif: pending.gif, options: options, sidecar: AppModel.shared.recorder.takeSidecar())
            case let .failure(error):
                Log.capture.error("Stopping the recording failed: \(error.localizedDescription, privacy: .public)")
            }
            if !isRecording {
                RecordingDefaults.end()
            }
        }
    }

    static func finishInstantReplay(_ url: URL) async {
        await finishRecording(url, gif: false, options: .standard, sidecar: .empty)
    }

    private static func finishRecording(_ url: URL, gif: Bool, options: CaptureOptions, sidecar: RecordingSidecar) async {
        await RecordingPostProcessor.mergeAppAudio(url, sidecar: sidecar)
        let deferredZoom = await RecordingPostProcessor.compositeOverlays(url, sidecar: sidecar)
        var fileURL = url
        var markers = sidecar.markers
        var isGIF = false
        if Defaults[.trimBeforeSaving] {
            switch await RecordingTrimWindow.present(url, markers: markers, autoZoom: deferredZoom) {
            case .keepOriginal:
                break
            case let .trimmed(trimmedURL, range):
                fileURL = trimmedURL
                markers = RecordingChapters.rebased(markers, to: range)
            case let .exportedGIF(gifURL):
                fileURL = gifURL
                isGIF = true
            case let .exported(exportedURL, range):
                fileURL = exportedURL
                markers = range.map { RecordingChapters.rebased(markers, to: $0) } ?? markers
            }
        }
        if gif, !isGIF {
            do {
                fileURL = try await RecordingConversions.convertToGIF(fileURL, range: nil, preset: .current, deletingSource: true)
                isGIF = true
            } catch {
                Log.capture.error("GIF export failed: \(error.localizedDescription, privacy: .public)")
                BezelNotification.show(messageText: "GIF export failed".localized(), icon: ToastIcon)
            }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        if !isGIF {
            await RecordingPostProcessor.finalize(fileURL, markers: markers)
        }
        await finish(fileURL: fileURL, kind: .video, options: options)
    }

    static func finish(fileURL originalURL: URL, kind: PostCapture.Kind, options: CaptureOptions = .standard) async {
        var fileURL = originalURL
        let saveToDisk = options.isEnabled(.saveToDisk)
        var copiedCode: Bool?
        var uploadToast: (model: ToastModel, presentation: Task<Void, Never>)?
        for step in AfterCaptureStep.allCases where step.runs(for: kind, options: options) {
            if copiedCode == nil, step != .openEditor, kind == .image {
                copiedCode = await CodeDetection.copyPayloadIfEnabled(fromImageAt: fileURL)
            }
            switch step {
            case .openEditor:
                switch await ImageEditor.edit(fileURL: fileURL) {
                case let .saved(url):
                    fileURL = url
                case .discarded:
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
            case .saveToDisk:
                break
            case .copyToClipboard:
                if copiedCode != true {
                    PostCapture.copyToClipboard(fileURL, kind: kind)
                }
            case .openInFinder:
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            case .airdrop, .photos, .messages, .mail:
                if let service = step.sharingService {
                    NSSharingService(named: service)?.perform(withItems: [fileURL])
                }
            case .upload:
                uploadToast = beginUploadToast(fileURL: fileURL)
                await upload(fileURL, kind: kind, options: options, keepsLocalFile: saveToDisk)
                uploadToast?.model.resolveUpload()
            }
        }
        if copiedCode == nil, kind == .image {
            await CodeDetection.copyPayloadIfEnabled(fromImageAt: fileURL)
        }

        if let uploadToast {
            await uploadToast.presentation.value
        } else {
            await showToast(fileURL: fileURL)
        }
        ToastPlacement.capturedDisplayID = nil
        SoundPlayer.play(.capture)
        if !saveToDisk {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func upload(_ fileURL: URL, kind: PostCapture.Kind, options: CaptureOptions, keepsLocalFile: Bool) async {
        var redactedURL: URL?
        if kind == .image {
            switch await Redactor.prepareUpload(of: fileURL) {
            case .unchanged:
                break
            case let .redacted(url):
                redactedURL = url
            case .failed:
                BezelNotification.show(messageText: "Upload skipped because sensitive text couldn't be checked".localized(), icon: ToastIcon)
                return
            }
        }
        let uploadURL = kind == .video ? await PostCapture.compressedIfNeeded(fileURL) : redactedURL ?? fileURL
        let localFileURL = keepsLocalFile ? fileURL : nil
        let altText = kind == .image && AltText.isEnabled ? Task { await AltText.generate(for: uploadURL) } : nil
        var results: [Result<UploadOutcome, any Error>] = []
        if let destinations = options.destinations {
            for target in destinations {
                results.append(await UploadCoordinator.upload(fileURL: uploadURL, target: target, localFileURL: localFileURL))
            }
        } else if let preset = options.preset {
            results.append(await UploadCoordinator.upload(fileURL: uploadURL, preset: preset, localFileURL: localFileURL))
        } else {
            results.append(await UploadCoordinator.upload(fileURL: uploadURL, localFileURL: localFileURL))
        }
        if let altText, let text = await altText.value {
            AltText.store(text, forUploadsAt: results.compactMap { try? $0.get().url })
        }
        if let redactedURL {
            Redactor.discard(redactedURL)
        } else if uploadURL != fileURL {
            try? FileManager.default.removeItem(at: uploadURL)
        }
    }
}

extension AfterCaptureStep {
    @MainActor func runs(for kind: PostCapture.Kind, options: CaptureOptions) -> Bool {
        switch self {
        case .openEditor: kind == .image && (options.openEditor || options.isEnabled(self))
        case .upload: options.isEnabled(self) || options.forceUpload || options.destinations != nil
        default: options.isEnabled(self)
        }
    }
}
