import AppKit
import Foundation

enum HistoryExportWriter {
    static let thumbnailPixelSize = 480
    static let thumbnailFolder = "thumbnails"

    struct Input: Sendable {
        let item: HistoryItem
        let uploaderName: String?
    }

    static func records(for inputs: [Input], fileSize: (URL) -> Int? = Self.fileSize) -> [HistoryExportRecord] {
        inputs.map { input in
            HistoryExportRecord.make(input.item, uploaderName: input.uploaderName, fileSize: input.item.existingLocalFileURL.flatMap(fileSize))
        }
    }

    static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    static func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func defaultFileName(for format: HistoryExportFormat, date: Date = Date()) -> String {
        let stem = "ishare uploads \(date.formatted(.iso8601.year().month().day()))"
        return format.fileExtension.map { "\(stem).\($0)" } ?? stem
    }

    @discardableResult
    static func write(_ inputs: [Input], format: HistoryExportFormat, includesDeletionLinks: Bool, to destination: URL) async throws -> URL {
        let document = HistoryExportDocument(records: records(for: inputs), includesDeletionLinks: includesDeletionLinks)
        switch format {
        case .csv:
            try Data(HistoryCSV.render(document).utf8).write(to: destination, options: .atomic)
            return destination
        case .json:
            try HistoryJSON.render(document).write(to: destination, options: .atomic)
            return destination
        case .html:
            let thumbnails = await embeddedThumbnails(for: inputs)
            let html = HistoryHTML.render(document, thumbnails: thumbnails, formatSize: formatSize, formatDate: formatDate)
            try Data(html.utf8).write(to: destination, options: .atomic)
            return destination
        case .htmlFolder:
            let folder = destination
            let thumbnailsFolder = folder.appending(path: thumbnailFolder, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: thumbnailsFolder, withIntermediateDirectories: true)
            var thumbnails: [HistoryHTML.Thumbnail] = []
            for (index, input) in inputs.enumerated() {
                guard let data = await thumbnailData(for: input.item) else {
                    thumbnails.append(.none)
                    continue
                }
                let name = "\(index + 1).jpg"
                try data.write(to: thumbnailsFolder.appending(path: name), options: .atomic)
                thumbnails.append(.file("\(thumbnailFolder)/\(name)"))
            }
            let html = HistoryHTML.render(document, thumbnails: thumbnails, formatSize: formatSize, formatDate: formatDate)
            let index = folder.appending(path: "index.html")
            try Data(html.utf8).write(to: index, options: .atomic)
            return index
        }
    }

    private static func embeddedThumbnails(for inputs: [Input]) async -> [HistoryHTML.Thumbnail] {
        var thumbnails: [HistoryHTML.Thumbnail] = []
        for input in inputs {
            thumbnails.append(await thumbnailData(for: input.item).map(HistoryHTML.Thumbnail.embedded) ?? .none)
        }
        return thumbnails
    }

    static func thumbnailData(for item: HistoryItem) async -> Data? {
        guard item.kind != .other, let url = item.existingLocalFileURL,
            let image = await ThumbnailCache.generateThumbnail(for: url, pixelSize: thumbnailPixelSize),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }
}
