import AppKit
import BezelNotification
import UniformTypeIdentifiers

@MainActor
enum NewCaptureDocument {
    static func save(_ image: CGImage, suffix: String, preservesTransparency: Bool) throws -> URL {
        let captured = CapturedImage(image: image, suffix: suffix)
        guard preservesTransparency else { return try ImageCaptureFlow.save(captured) }
        let url = SaveLocation.fileURL(for: .captures, fileName: ImageCaptureFlow.fileName(for: captured, ext: FileType.PNG.rawValue))
        try ImageEncoder.write(image, as: .PNG, to: url)
        return url
    }

    static func openInEditor(_ image: CGImage, suffix: String, preservesTransparency: Bool) async {
        do {
            let url = try save(image, suffix: suffix, preservesTransparency: preservesTransparency)
            await CaptureSession.finish(fileURL: url, kind: .image, options: CaptureOptions(openEditor: true))
        } catch {
            Log.app.error("Saving the \(suffix, privacy: .public) capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Couldn't save the image".localized(), icon: ToastIcon)
        }
    }

    static func chooseImages(message: String) -> [URL] {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = message
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
