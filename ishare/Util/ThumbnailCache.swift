import AppKit
import QuickLookThumbnailing
import SwiftUI
import Synchronization

struct ThumbnailKey: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case file(String)
        case remote(URL)
    }

    static let pixelBuckets = [64, 128, 256, 512, 1024]

    let source: Source
    let pixelSize: Int

    init(source: Source, requestedPixelSize: Int) {
        self.source = source
        pixelSize = Self.bucket(for: requestedPixelSize)
    }

    static func bucket(for pixelSize: Int) -> Int {
        pixelBuckets.first { $0 >= pixelSize } ?? pixelBuckets[pixelBuckets.count - 1]
    }

    var cacheKey: String {
        switch source {
        case let .file(path): "file:\(path)@\(pixelSize)"
        case let .remote(url): "remote:\(url.absoluteString)@\(pixelSize)"
        }
    }

    static func forFile(_ url: URL, pointSize: CGFloat, scale: CGFloat = 2) -> ThumbnailKey {
        ThumbnailKey(source: .file(url.standardizedFileURL.path), requestedPixelSize: Int((pointSize * scale).rounded(.up)))
    }

    static func forItem(
        _ item: HistoryItem, pointSize: CGFloat, scale: CGFloat = 2,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> ThumbnailKey? {
        let pixels = Int((pointSize * scale).rounded(.up))
        if let path = item.localPath, !path.isEmpty, fileExists(path) {
            return ThumbnailKey(source: .file(URL(fileURLWithPath: path).standardizedFileURL.path), requestedPixelSize: pixels)
        }
        guard item.kind != .video, let string = item.fileUrl, let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return HistorySyncPreviews.existingURL(for: item).map { ThumbnailKey(source: .file($0.path), requestedPixelSize: pixels) }
        }
        return ThumbnailKey(source: .remote(url), requestedPixelSize: pixels)
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images = NSCache<NSString, NSImage>()
    private var inFlight: [ThumbnailKey: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = ThumbnailCache.makeSession()) {
        self.session = session
        images.countLimit = 400
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "Thumbnails", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }

    func cachedImage(for key: ThumbnailKey?) -> NSImage? {
        guard let key else { return nil }
        return images.object(forKey: key.cacheKey as NSString)
    }

    func store(_ image: NSImage, for key: ThumbnailKey) {
        images.setObject(image, forKey: key.cacheKey as NSString)
    }

    func removeAll() {
        images.removeAllObjects()
    }

    func removeImages(forFile url: URL) {
        let path = url.standardizedFileURL.path
        for bucket in ThumbnailKey.pixelBuckets {
            images.removeObject(forKey: ThumbnailKey(source: .file(path), requestedPixelSize: bucket).cacheKey as NSString)
        }
    }

    func image(for key: ThumbnailKey) async -> NSImage? {
        if let cached = cachedImage(for: key) {
            return cached
        }
        if let running = inFlight[key] {
            return await running.value
        }
        let session = session
        let task = Task<NSImage?, Never> {
            switch key.source {
            case let .file(path):
                await Self.generateThumbnail(for: URL(fileURLWithPath: path), pixelSize: key.pixelSize)
            case let .remote(url):
                await Self.fetchThumbnail(from: url, pixelSize: key.pixelSize, session: session)
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            store(image, for: key)
        }
        return image
    }

    nonisolated static let quickLookTimeout: TimeInterval = 5

    nonisolated static func generateThumbnail(for url: URL, pixelSize: Int) async -> NSImage? {
        if let image = ImageProcessing.thumbnail(for: url, maxPixelSize: pixelSize) {
            return image
        }
        return await quickLookThumbnail(for: url, pixelSize: pixelSize)
    }

    nonisolated static func quickLookThumbnail(for url: URL, pixelSize: Int) async -> NSImage? {
        let size = CGSize(width: pixelSize, height: pixelSize)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1, representationTypes: .thumbnail)
        return await withCheckedContinuation { continuation in
            let delivery = SingleDelivery(continuation)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                delivery.deliver(representation.map { NSImage(cgImage: $0.cgImage, size: CGSize(width: $0.cgImage.width, height: $0.cgImage.height)) })
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + quickLookTimeout) {
                delivery.deliver(nil)
            }
        }
    }

    nonisolated static func fetchThumbnail(from url: URL, pixelSize: Int, session: URLSession) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true
        else { return nil }
        return downsampled(data, pixelSize: pixelSize)
    }

    nonisolated static func downsampled(_ data: Data, pixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
}

struct ThumbnailImage<Placeholder: View>: View {
    let key: ThumbnailKey?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: (Bool) -> Placeholder
    @State private var image: NSImage?
    @State private var failed = false

    init(key: ThumbnailKey?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping (Bool) -> Placeholder) {
        self.key = key
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: ThumbnailCache.shared.cachedImage(for: key))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder(failed || key == nil)
            }
        }
        .task(id: key) {
            guard let key else { return }
            if let cached = ThumbnailCache.shared.cachedImage(for: key) {
                image = cached
                return
            }
            let loaded = await ThumbnailCache.shared.image(for: key)
            image = loaded
            failed = loaded == nil
        }
    }
}

private final class SingleDelivery: Sendable {
    private let continuation: Mutex<CheckedContinuation<NSImage?, Never>?>

    init(_ continuation: CheckedContinuation<NSImage?, Never>) {
        self.continuation = Mutex(continuation)
    }

    func deliver(_ image: sending NSImage?) {
        let pending = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: image)
    }
}
