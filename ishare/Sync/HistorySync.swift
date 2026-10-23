import AppKit
import Defaults
import Foundation
import ImageIO
import ishareCore
import UniformTypeIdentifiers

@MainActor
final class HistorySync {
    static let shared = HistorySync(store: NSUbiquitousKeyValueStore.default)

    static var isAvailable: Bool {
        #if APP_STORE
            true
        #else
            false
        #endif
    }

    static let previewCount = 20

    let store: KeyValueSyncStore
    private(set) var isApplyingRemote = false
    private(set) var lastError: (any Error)?
    private var observers: [NSObjectProtocol] = []
    private var tasks: [Task<Void, Never>] = []
    private var pendingPush: Task<Void, Never>?
    private var historyUpdates: Task<Void, Never>?
    private var previewCache: [String: Data] = [:]

    init(store: KeyValueSyncStore) {
        self.store = store
    }

    var isEnabled: Bool {
        Self.isAvailable && Defaults[.historySyncEnabled]
    }

    func start() {
        guard Self.isAvailable, tasks.isEmpty else { return }
        tasks.append(
            Task { @MainActor [weak self] in
                for await enabled in Defaults.updates(.historySyncEnabled) {
                    self?.setActive(enabled)
                }
            })
    }

    private func setActive(_ active: Bool) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        historyUpdates?.cancel()
        historyUpdates = nil
        guard active else {
            pendingPush?.cancel()
            return
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                guard keys.isEmpty || keys.contains(where: { $0.hasPrefix(HistorySyncCodec.keyPrefix) }) else { return }
                Task { @MainActor in
                    self?.syncNow()
                }
            })
        historyUpdates = Task { @MainActor [weak self] in
            for await _ in Defaults.updates(.uploadHistory, initial: false) {
                guard let self, isEnabled, !isApplyingRemote else { continue }
                schedulePush()
            }
        }
        store.synchronize()
        syncNow()
    }

    private func schedulePush() {
        pendingPush?.cancel()
        pendingPush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    func recordDeletion(of items: [HistoryItem], now: Date = Date()) {
        let ids = items.filter(HistorySyncEntry.isSyncable).compactMap(\.fileUrl).map(HistorySyncEntry.identifier(forLink:))
        guard !ids.isEmpty else { return }
        var tombstones = Defaults[.historySyncTombstones]
        for id in ids {
            tombstones[id] = now
        }
        Defaults[.historySyncTombstones] = HistorySyncMerge.tombstones(tombstones, [:], now: now)
    }

    func syncNow(now: Date = Date()) {
        guard isEnabled else { return }
        sync(now: now)
    }

    func sync(now: Date = Date()) {
        let remote: HistorySyncState
        do {
            remote = try HistorySyncCodec.read(from: store) ?? .empty
        } catch {
            lastError = error
            Log.app.info("History sync is waiting for a complete iCloud copy: \(String(describing: error), privacy: .public)")
            return
        }
        let local = Defaults[.uploadHistory]
        let uploaders = CustomUploader.allCases
        let result = HistorySyncMerge.merge(
            local: local, remote: remote, localTombstones: Defaults[.historySyncTombstones],
            uploaderName: { $0.uploaderName(among: uploaders) }, previews: previews(for: local), now: now
        )
        storePreviews(from: result.state.entries)
        let history = HistoryPruning.pruned(result.history, limit: Defaults[.historyLimit], retention: Defaults[.historyRetention], now: now)
        if history != local {
            isApplyingRemote = true
            Defaults[.uploadHistory] = history
            isApplyingRemote = false
        }
        Defaults[.historySyncTombstones] = result.state.tombstones
        if result.state != remote {
            do {
                try HistorySyncCodec.write(result.state, to: store, now: now)
                lastError = nil
            } catch {
                lastError = error
                Log.app.error("Writing the synced history failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func disableAndRemoveCloudCopy() {
        HistorySyncCodec.removeAll(from: store)
    }

    private func previews(for items: [HistoryItem]) -> [String: Data] {
        var result: [String: Data] = [:]
        for item in items.prefix(Self.previewCount) {
            guard let link = item.fileUrl, HistorySyncEntry.isSyncable(item), item.kind == .image, let file = item.existingLocalFileURL else { continue }
            let id = HistorySyncEntry.identifier(forLink: link)
            if let cached = previewCache[id] {
                result[id] = cached
            } else if let preview = HistorySyncPreviews.make(fromImageAt: file) {
                previewCache[id] = preview
                result[id] = preview
            }
        }
        return result
    }

    private func storePreviews(from entries: [HistorySyncEntry]) {
        for entry in entries {
            guard let preview = entry.preview, previewCache[entry.id] == nil else { continue }
            HistorySyncPreviews.store(preview, for: entry.id)
        }
    }
}

enum HistorySyncPreviews {
    static let pixelSize = 128

    static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "SyncedPreviews", directoryHint: .isDirectory)
    }

    static func url(for id: String) -> URL? {
        directory?.appending(path: "\(id).jpg")
    }

    static func existingURL(for item: HistoryItem) -> URL? {
        guard let link = item.fileUrl, let url = url(for: HistorySyncEntry.identifier(forLink: link)),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    static func store(_ data: Data, for id: String) {
        guard data.count <= HistorySyncEntry.maximumPreviewBytes, let url = url(for: id), !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func make(fromImageAt url: URL, maximumBytes: Int = HistorySyncEntry.maximumPreviewBytes) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        for size in [pixelSize, 96, 64] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            for quality in [0.6, 0.4, 0.25] {
                if let data = jpeg(image, quality: quality), data.count <= maximumBytes {
                    return data
                }
            }
        }
        return nil
    }

    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
