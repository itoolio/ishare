import AppKit
import Defaults
import UniformTypeIdentifiers

enum ExternalUploadPayload: Equatable {
    case files([URL])
    case imageData(Data)
}

@MainActor
enum ExternalUpload {
    static let draggedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .png, .tiff]

    nonisolated static func uploadableFiles(_ urls: [URL], fileManager: FileManager = .default) -> [URL] {
        urls.filter { url in
            var isDirectory: ObjCBool = false
            return url.isFileURL && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    nonisolated static func payload(from pasteboard: NSPasteboard) -> ExternalUploadPayload? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let files = uploadableFiles(urls)
        if !files.isEmpty {
            return .files(files)
        }
        if let png = pasteboard.data(forType: .png) {
            return .imageData(png)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:])
        {
            return .imageData(png)
        }
        return nil
    }

    static func upload(_ payload: ExternalUploadPayload) async {
        switch payload {
        case let .files(urls):
            for url in urls {
                await upload(fileURL: url)
            }
        case let .imageData(data):
            let url = FileManager.default.temporaryDirectory.appending(
                path: CaptureFileName.make(prefix: Defaults[.captureFileName], suffix: "dropped", ext: "png")
            )
            do {
                try data.write(to: url)
            } catch {
                Log.upload.error("Writing the dropped image failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            await upload(fileURL: url, keepsLocalCopy: false)
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func upload(fileURL: URL, keepsLocalCopy: Bool = true) async {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        Log.upload.info("Uploading external file \(fileURL.path, privacy: .public)")
        let toast = Task { @MainActor in
            await showToast(fileURL: fileURL, awaitingUpload: true)
        }
        await UploadOrigin.$current.withValue(.imported) {
            _ = await UploadCoordinator.upload(fileURL: fileURL, localFileURL: keepsLocalCopy ? fileURL : nil)
        }
        if !keepsLocalCopy {
            await toast.value
        }
    }
}
