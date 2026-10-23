@preconcurrency import AppKit
import BezelNotification
import Defaults
import Foundation

struct CaptureOptions: Sendable {
    var forceUpload = false
    var openEditor = false
    var destinations: [UploadTarget]?
    var preset: UploadPreset?
    var delay: Int?

    static let standard = CaptureOptions()
}

@MainActor
enum CaptureSession {
    private static var isCapturingImage = false
    private static var pendingRecording: (gif: Bool, options: CaptureOptions)?

    static var isRecording: Bool {
        AppDelegate.shared.screenRecorder.isRunning
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
            await startRecording(region: region)
        }
    }

    private static func startRecording(region: Bool) async {
        let recorder = AppDelegate.shared.screenRecorder
        guard await recorder.canRecord else {
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return
        }
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
        }
    }

    static func stopRecording() {
        let pending = pendingRecording ?? (false, .standard)
        pendingRecording = nil
        let wantsDestinationChoice = DestinationChooser.isRequested()
        Task { @MainActor in
            ContentSharingPickerManager.shared.deactivatePicker()
            switch await AppDelegate.shared.screenRecorder.stop() {
            case let .success(url):
                var options = pending.options
                if wantsDestinationChoice, let target = DestinationChooser.choose() {
                    options.destinations = [target]
                }
                await finishRecording(url, gif: pending.gif, options: options, sidecar: AppDelegate.shared.screenRecorder.takeSidecar())
            case let .failure(error):
                Log.capture.error("Stopping the recording failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func finishInstantReplay(_ url: URL) async {
        await finishRecording(url, gif: false, options: .standard, sidecar: .empty)
    }

    private static func finishRecording(_ url: URL, gif: Bool, options: CaptureOptions, sidecar: RecordingSidecar) async {
        await RecordingPostProcessor.mergeAppAudio(url, sidecar: sidecar)
        await RecordingPostProcessor.compositeOverlays(url, sidecar: sidecar)
        var fileURL = url
        var markers = sidecar.markers
        var isGIF = false
        if Defaults[.trimBeforeSaving] {
            switch await RecordingTrimWindow.present(url, markers: markers) {
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
        if let destinations = options.destinations {
            for target in destinations {
                await UploadCoordinator.upload(fileURL: uploadURL, target: target, localFileURL: localFileURL)
            }
        } else if let preset = options.preset {
            await UploadCoordinator.upload(fileURL: uploadURL, preset: preset, localFileURL: localFileURL)
        } else {
            await UploadCoordinator.upload(fileURL: uploadURL, localFileURL: localFileURL)
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
