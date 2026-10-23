import AppKit
import Defaults
import Foundation

@MainActor
enum PostCapture {
    enum Kind {
        case image
        case video
    }

    static func compressedIfNeeded(_ fileURL: URL) async -> URL {
        guard Defaults[.compressBeforeUpload], fileURL.pathExtension.lowercased() != "gif",
            let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            VideoCompressor.needsCompression(fileSize: Int64(size), thresholdMB: Defaults[.compressionThresholdMB])
        else { return fileURL }
        do {
            return try await VideoCompressor.compress(fileURL, preset: Defaults[.compressionPreset], hevc: Defaults[.useHEVC])
        } catch {
            NSLog("Compression failed: %@", error.localizedDescription)
            return fileURL
        }
    }

    static func copyToClipboard(_ fileURL: URL, kind: Kind) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if kind == .image, Defaults[.copyImageToClipboard], let image = NSImage(contentsOf: fileURL) {
            pasteboard.writeObjects([image])
        } else if kind == .image {
            pasteboard.writeObjects([pasteboardItem(forImageAt: fileURL)])
        } else {
            pasteboard.writeObjects([fileURL as NSURL])
        }
    }

    // Apps that only read bitmap types (e.g. terminal CLIs, chat inputs, image editors) ignore
    // a bare file URL, so the PNG rides along while Finder and friends still paste the file.
    static func pasteboardItem(forImageAt fileURL: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        if let png = pngData(at: fileURL) {
            item.setData(png, forType: .png)
        }
        return item
    }

    static func pngData(at fileURL: URL) -> Data? {
        if fileURL.pathExtension.lowercased() == FileType.PNG.rawValue {
            return try? Data(contentsOf: fileURL)
        }
        guard let image = ImageEncoder.loadImage(at: fileURL) else { return nil }
        return try? ImageEncoder.data(for: image, as: .PNG)
    }
}
