import BezelNotification
import Defaults
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Default(.uploadHistory) var uploadHistory

    init() {
        if !ScreenshotMode.isActive {
            setupKeyboardShortcuts()
            UploadPresetShortcuts.start()
            RecordingPresetShortcuts.start()
            UploadBackgroundServices.start()
            InstantReplay.shared.activate()
        }
    }

    private func onCapture(_ name: KeyboardShortcuts.Name, _ type: CaptureType, forceUpload: Bool = false) {
        KeyboardShortcuts.onKeyUp(for: name) {
            Task { @MainActor in
                await CaptureSession.captureImage(type, options: CaptureOptions(forceUpload: forceUpload))
            }
        }
    }

    private func onRecord(_ name: KeyboardShortcuts.Name, gif: Bool, region: Bool = false, forceUpload: Bool = false) {
        KeyboardShortcuts.onKeyUp(for: name) {
            Task { @MainActor in
                CaptureSession.toggleRecording(gif: gif, region: region, options: CaptureOptions(forceUpload: forceUpload))
            }
        }
    }

    func setupKeyboardShortcuts() {
        onCapture(.captureRegion, .REGION)
        onCapture(.captureWindow, .WINDOW)
        onCapture(.captureScreen, .SCREEN)
        onCapture(.captureScrolling, .SCROLLING)
        onCapture(.captureLastRegion, .LAST_REGION)
        onCapture(.captureText, .TEXT)
        IntervalCapture.registerShortcut()
        CaptureTranslateFlow.registerShortcut()
        CaptureAskFlow.registerShortcut()
        onCapture(.captureRegionForceUpload, .REGION, forceUpload: true)
        onCapture(.captureWindowForceUpload, .WINDOW, forceUpload: true)
        onCapture(.captureScreenForceUpload, .SCREEN, forceUpload: true)

        onRecord(.recordScreen, gif: false)
        onRecord(.recordGif, gif: true)
        onRecord(.recordRegion, gif: false, region: true)
        onRecord(.recordRegionGif, gif: true, region: true)
        onRecord(.recordScreenForceUpload, gif: false, forceUpload: true)
        onRecord(.recordGifForceUpload, gif: true, forceUpload: true)

        KeyboardShortcuts.onKeyUp(for: .addRecordingMarker) { Task { @MainActor in AppModel.shared.recorder.addMarker() } }
        KeyboardShortcuts.onKeyUp(for: .toggleRecordingNotes) { Task { @MainActor in AppModel.shared.recorder.toggleNotes() } }
        KeyboardShortcuts.onKeyUp(for: .saveInstantReplay) { Task { @MainActor in await InstantReplay.shared.save() } }
        KeyboardShortcuts.onKeyUp(for: .toggleRecordingDrawing) { Task { @MainActor in AppModel.shared.recorder.toggleDrawing() } }
        KeyboardShortcuts.onKeyUp(for: .togglePauseRecording) { Task { @MainActor in AppModel.shared.recorder.togglePause() } }

        KeyboardShortcuts.onKeyUp(for: .toggleMainMenu) {
            Task { @MainActor in
                MenuController.shared.toggle()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openHistoryWindow) {
            Task { @MainActor in
                openHistoryWindow(uploadHistory: Defaults[.uploadHistory])
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openEditor) {
            Task { @MainActor in
                await ImageEditor.chooseAndEdit()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openMostRecentItem) {
            Task { @MainActor in
                guard let item = Defaults[.uploadHistory].first, let string = item.fileUrl, let url = URL(string: string) else { return }
                NSWorkspace.shared.open(url)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .uploadPasteBoardItem) {
            Task { @MainActor in
                await AppState.uploadPasteboard()
            }
        }
    }

    static func uploadPasteboard() async {
        let pasteboard = NSPasteboard.general
        if let mediaURL = pasteboard.mediaURL {
            await UploadCoordinator.upload(fileURL: mediaURL, localFileURL: mediaURL)
            await showToast(fileURL: mediaURL)
            return
        }
        if let image = pasteboard.imageFromData,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        {
            let url = FileManager.default.temporaryDirectory.appending(path: CaptureFileName.make(prefix: Defaults[.captureFileName], suffix: "pasteboard", ext: "png"))
            try? data.write(to: url)
            await UploadCoordinator.upload(fileURL: url)
            await showToast(fileURL: url)
            try? FileManager.default.removeItem(at: url)
            return
        }
        if let text = pasteboard.plainText {
            await uploadText(text)
        }
    }

    static func uploadText(_ text: String) async {
        guard let url = try? TextSnippet.write(text, in: FileManager.default.temporaryDirectory, prefix: Defaults[.captureFileName]) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        if case .success = await UploadCoordinator.upload(fileURL: url) {
            BezelNotification.show(messageText: "Text uploaded".localized(), icon: ToastIcon)
        }
    }
}
