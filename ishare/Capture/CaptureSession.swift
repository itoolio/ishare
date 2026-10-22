@preconcurrency import AppKit
import BezelNotification
import Defaults
import Foundation

struct CaptureOptions: Sendable {
    var forceUpload = false
    var openEditor = false
    var destinations: [UploadTarget]?

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
        let captured = await ImageCaptureFlow.capture(type: type, display: display)
        isCapturingImage = false
        guard let captured else { return }
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
        Task { @MainActor in
            ContentSharingPickerManager.shared.deactivatePicker()
            switch await AppDelegate.shared.screenRecorder.stop() {
            case let .success(url):
                await finishRecording(url, gif: pending.gif, options: pending.options)
            case let .failure(error):
                Log.capture.error("Stopping the recording failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func finishRecording(_ url: URL, gif: Bool, options: CaptureOptions) async {
        var fileURL = url
        if gif {
            do {
                fileURL = try await exportGif(from: url, frameRate: Defaults[.gifFrameRate].rawValue)
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
        if kind == .image, options.openEditor || Defaults[.openEditorAfterCapture] {
            switch await ImageEditor.edit(fileURL: fileURL) {
            case let .saved(url):
                fileURL = url
            case .discarded:
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
        }

        let saveToDisk = Defaults[.saveToDisk]
        if Defaults[.copyToClipboard] {
            PostCapture.copyToClipboard(fileURL, kind: kind)
        }
        if Defaults[.openInFinder], saveToDisk {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
        shareBasedOnPreferences(fileURL)

        if Defaults[.uploadMedia] || options.forceUpload || options.destinations != nil {
            let uploadURL = kind == .video ? await PostCapture.compressedIfNeeded(fileURL) : fileURL
            let localFileURL = saveToDisk ? fileURL : nil
            if let destinations = options.destinations {
                for target in destinations {
                    await UploadCoordinator.upload(fileURL: uploadURL, target: target, localFileURL: localFileURL)
                }
            } else {
                await UploadCoordinator.upload(fileURL: uploadURL, localFileURL: localFileURL)
            }
            if uploadURL != fileURL {
                try? FileManager.default.removeItem(at: uploadURL)
            }
        }

        await showToast(fileURL: fileURL)
        NSSound.beep()
        if !saveToDisk {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
