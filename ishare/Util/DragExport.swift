import AppKit
import UniformTypeIdentifiers

struct DragExportPlan: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case file(URL)
        case image(ThumbnailKey)
        case none
    }

    static let fallbackPixelSize = 1024

    let payload: Payload
    let link: String?
    let suggestedName: String?

    static func make(
        localFile: URL?,
        remoteURL: URL?,
        linkText: String?,
        fileName: String?,
        isImage: Bool,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> DragExportPlan {
        let link = linkText.flatMap { $0.isEmpty ? nil : $0 } ?? remoteURL?.absoluteString
        if let localFile, fileExists(localFile.path) {
            return DragExportPlan(payload: .file(localFile), link: link, suggestedName: localFile.lastPathComponent)
        }
        let name = fileName.flatMap { $0.isEmpty ? nil : $0 }
        guard isImage, let remoteURL, let scheme = remoteURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return DragExportPlan(payload: .none, link: link, suggestedName: name)
        }
        let key = ThumbnailKey(source: .remote(remoteURL), requestedPixelSize: fallbackPixelSize)
        return DragExportPlan(payload: .image(key), link: link, suggestedName: name)
    }

    static func make(for item: HistoryItem, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> DragExportPlan {
        make(
            localFile: item.localFileURL,
            remoteURL: item.remoteURL,
            linkText: item.preferredURL?.absoluteString ?? item.fileUrl,
            fileName: item.fileName,
            isImage: item.kind == .image,
            fileExists: fileExists
        )
    }
}

@MainActor
enum DragExport {
    static func provider(for item: HistoryItem) -> NSItemProvider {
        provider(for: .make(for: item))
    }

    static func provider(fileURL: URL?, historyItem: HistoryItem?, isImage: Bool) -> NSItemProvider {
        let plan = DragExportPlan.make(
            localFile: fileURL ?? historyItem?.localFileURL,
            remoteURL: historyItem?.remoteURL,
            linkText: historyItem.flatMap { $0.preferredURL?.absoluteString ?? $0.fileUrl },
            fileName: fileURL?.lastPathComponent ?? historyItem?.fileName,
            isImage: isImage
        )
        return provider(for: plan)
    }

    static func provider(for plan: DragExportPlan) -> NSItemProvider {
        let provider: NSItemProvider
        switch plan.payload {
        case let .file(url):
            provider = NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        case let .image(key):
            provider = NSItemProvider()
            registerImage(key, on: provider)
        case .none:
            provider = NSItemProvider()
        }
        provider.suggestedName = plan.suggestedName
        if let link = plan.link {
            registerText(link, on: provider)
        }
        return provider
    }

    private static func registerText(_ text: String, on provider: NSItemProvider) {
        let data = Data(text.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
    }

    private static func registerImage(_ key: ThumbnailKey, on provider: NSItemProvider) {
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            Task { @MainActor in
                let image = await ThumbnailCache.shared.image(for: key)
                completion(image.flatMap(pngData(of:)), nil)
            }
            return nil
        }
    }

    static func pngData(of image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
