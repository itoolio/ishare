@preconcurrency import AppKit
import BezelNotification
import Defaults
import Foundation

struct CaptureOptions: Sendable {
    var forceUpload = false
    var openEditor = false
    var destinations: [UploadTarget]?
    var preset: UploadPreset?

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
        let wantsDestinationChoice = DestinationChooser.isRequested()
        Log.capture.info("Starting \(type.rawValue, privacy: .public) capture on display \(display)")
        let captured = await ImageCaptureFlow.capture(type: type, display: display)
        isCapturingImage = false
        guard let captured else { return }
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
                await finishRecording(url, gif: pending.gif, options: options)
            case let .failure(error):
                Log.capture.error("Stopping the recording failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func finishRecording(_ url: URL, gif: Bool, options: CaptureOptions) async {
        var fileURL = url
        var isGIF = false
        if Defaults[.trimBeforeSaving] {
            switch await RecordingTrimWindow.present(url) {
            case .keepOriginal:
                break
            case let .trimmed(trimmedURL):
                fileURL = trimmedURL
            case let .exportedGIF(gifURL):
                fileURL = gifURL
                isGIF = true
            }
        }
        if gif, !isGIF {
            do {
                fileURL = try await RecordingConversions.convertToGIF(fileURL, range: nil, preset: .current, deletingSource: true)
            } catch {
                Log.capture.error("GIF export failed: \(error.localizedDescription, privacy: .public)")
                BezelNotification.show(messageText: "GIF export failed".localized(), icon: ToastIcon)
            }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        await finish(fileURL: fileURL, kind: .video, options: options)
    }

    static func finish(fileURL originalURL: URL, kind: PostCapture.Kind, options: CaptureOptions = .standard) async {
        var fileURL = originalURL
        let saveToDisk = options.isEnabled(.saveToDisk)
        for step in AfterCaptureStep.allCases where step.runs(for: kind, options: options) {
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
                PostCapture.copyToClipboard(fileURL, kind: kind)
            case .openInFinder:
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            case .airdrop, .photos, .messages, .mail:
                if let service = step.sharingService {
                    NSSharingService(named: service)?.perform(withItems: [fileURL])
                }
            case .upload:
                await upload(fileURL, kind: kind, options: options, keepsLocalFile: saveToDisk)
            }
        }

        await showToast(fileURL: fileURL)
        SoundPlayer.play(.capture)
        if !saveToDisk {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func upload(_ fileURL: URL, kind: PostCapture.Kind, options: CaptureOptions, keepsLocalFile: Bool) async {
        let uploadURL = kind == .video ? await PostCapture.compressedIfNeeded(fileURL) : fileURL
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
        if uploadURL != fileURL {
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
