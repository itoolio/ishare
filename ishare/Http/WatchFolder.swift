import Defaults
import Foundation
import UniformTypeIdentifiers

enum WatchFolderFilter: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case images
    case videos
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .images: "Images"
        case .videos: "Videos"
        case .all: "All files"
        }
    }

    func accepts(_ url: URL) -> Bool {
        guard self != .all else { return true }
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        switch self {
        case .images: return type.conforms(to: .image)
        case .videos: return type.conforms(to: .audiovisualContent)
        case .all: return true
        }
    }
}

struct WatchedFile: Hashable, Sendable {
    let url: URL
    let size: Int
    let modified: Date
}

enum WatchFolderScanner {
    static let temporaryExtensions: Set<String> = ["tmp", "temp", "part", "partial", "crdownload", "download", "opdownload", "swp", "lock"]

    static func isCandidate(_ url: URL, filter: WatchFolderFilter) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), !name.hasPrefix("~$"), !name.hasSuffix("~") else { return false }
        guard !temporaryExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return filter.accepts(url)
    }

    static func listing(of directory: URL, filter: WatchFolderFilter) -> [WatchedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isPackageKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return contents.compactMap { url in
            guard isCandidate(url, filter: filter),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isPackage != true
            else { return nil }
            return WatchedFile(url: url.standardizedFileURL, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
        }
    }
}

struct WatchFolderStability {
    let requiredStableScans: Int
    private(set) var pending: [URL: (file: WatchedFile, stableScans: Int)] = [:]

    init(requiredStableScans: Int = 1) {
        self.requiredStableScans = requiredStableScans
    }

    var hasPending: Bool { !pending.isEmpty }

    mutating func observe(_ listing: [WatchedFile], ignoring handled: Set<String>) -> [URL] {
        let current = Dictionary(listing.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        pending = pending.filter { current[$0.key] != nil }
        var ready: [URL] = []
        for file in listing where !handled.contains(file.url.path) {
            if let previous = pending[file.url], previous.file == file, file.size > 0 {
                let scans = previous.stableScans + 1
                if scans >= requiredStableScans {
                    pending[file.url] = nil
                    ready.append(file.url)
                } else {
                    pending[file.url] = (file, scans)
                }
            } else {
                pending[file.url] = (file, 0)
            }
        }
        return ready.sorted { $0.path < $1.path }
    }
}

@MainActor
final class WatchFolderMonitor {
    let directory: URL
    let filter: WatchFolderFilter
    let stabilityInterval: TimeInterval
    private let onFileReady: @MainActor (URL) -> Void
    private var stability: WatchFolderStability
    private(set) var handled: Set<String>
    private var source: DispatchSourceFileSystemObject?
    private var scanTask: Task<Void, Never>?

    init(
        directory: URL, filter: WatchFolderFilter, processed: Set<String> = [], stabilityInterval: TimeInterval = 1,
        requiredStableScans: Int = 1, onFileReady: @escaping @MainActor (URL) -> Void
    ) {
        self.directory = directory.standardizedFileURL
        self.filter = filter
        self.stabilityInterval = stabilityInterval
        self.onFileReady = onFileReady
        stability = WatchFolderStability(requiredStableScans: requiredStableScans)
        handled = processed
    }

    func start() {
        guard source == nil else { return }
        handled.formUnion(WatchFolderScanner.listing(of: directory, filter: filter).map(\.url.path))
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.upload.error("Couldn't watch \(self.directory.path, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleScan(after: 0.3)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        source?.cancel()
        source = nil
    }

    private func scheduleScan(after delay: TimeInterval) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    func scan() {
        let listing = WatchFolderScanner.listing(of: directory, filter: filter)
        let present = Set(listing.map(\.url.path))
        handled = handled.filter { present.contains($0) || !$0.hasPrefix(directory.path) }
        for url in stability.observe(listing, ignoring: handled) {
            handled.insert(url.path)
            onFileReady(url)
        }
        if stability.hasPending {
            scheduleScan(after: stabilityInterval)
        }
    }
}

@MainActor
final class WatchFolderService {
    static let shared = WatchFolderService()
    private var monitor: WatchFolderMonitor?
    private var accessedURL: URL?
    private var observation: Task<Void, Never>?

    func start() {
        restart()
        guard observation == nil else { return }
        observation = Task { [weak self] in
            for await _ in Defaults.updates([.watchFolderEnabled, .watchFolderBookmark, .watchFolderFilter], initial: false) {
                self?.restart()
            }
        }
    }

    static func choose(_ url: URL) {
        Defaults[.watchFolderBookmark] = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        Defaults[.watchFolderPath] = url.path(percentEncoded: false)
        Defaults[.watchFolderProcessed] = []
    }

    private func restart() {
        monitor?.stop()
        monitor = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        guard Defaults[.watchFolderEnabled], let directory = resolveDirectory() else { return }
        let processed = Set(Defaults[.watchFolderProcessed]).filter { FileManager.default.fileExists(atPath: $0) }
        let monitor = WatchFolderMonitor(directory: directory, filter: Defaults[.watchFolderFilter], processed: processed) { url in
            WatchFolderService.markProcessed(url)
            Task { @MainActor in
                guard !WatchFolderService.isOwnCapture(url) else { return }
                await UploadCoordinator.upload(fileURL: url, localFileURL: url)
                await showToast(fileURL: url)
            }
        }
        monitor.start()
        self.monitor = monitor
    }

    static func isOwnCapture(_ url: URL) -> Bool {
        let directory = url.deletingLastPathComponent().standardizedFileURL.path
        let name = url.lastPathComponent.lowercased()
        let sources: [(SaveLocation.Kind, String)] = [(.captures, Defaults[.captureFileName]), (.recordings, Defaults[.recordingFileName])]
        return sources.contains { kind, prefix in
            let base = CaptureFileName.sanitize(prefix).isEmpty ? "ishare" : CaptureFileName.sanitize(prefix)
            return SaveLocation.directory(for: kind).standardizedFileURL.path == directory && name.hasPrefix(base + "-")
        }
    }

    private static func markProcessed(_ url: URL) {
        var processed = Defaults[.watchFolderProcessed].filter { $0 != url.path }
        processed.append(url.path)
        Defaults[.watchFolderProcessed] = Array(processed.suffix(500))
    }

    private func resolveDirectory() -> URL? {
        if let bookmark = Defaults[.watchFolderBookmark] {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if url.startAccessingSecurityScopedResource() {
                    accessedURL = url
                }
                if isStale {
                    Defaults[.watchFolderBookmark] = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                return url
            }
        }
        let path = Defaults[.watchFolderPath]
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
}
