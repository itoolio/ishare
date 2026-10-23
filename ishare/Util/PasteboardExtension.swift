import AppKit
import UniformTypeIdentifiers

extension NSPasteboard {
    var mediaURL: URL? {
        guard let urls = readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
            let url = urls.first
        else { return nil }

        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) ? url : nil
    }

    var imageFromData: NSImage? {
        guard let data = data(forType: .tiff) ?? data(forType: .png) else { return nil }
        return NSImage(data: data)
    }

    var plainText: String? {
        let hasFiles = (readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.isEmpty == false
        guard !hasFiles, let text = string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    var hasMediaContent: Bool {
        return mediaURL != nil || imageFromData != nil
    }
}
