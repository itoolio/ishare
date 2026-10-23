import CryptoKit
import Defaults
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

enum WidgetSnapshotWriter {
    static let thumbnailPixelSize = 360

    @MainActor private static var observation: Task<Void, Never>?

    static func itemID(for item: HistoryItem) -> String {
        let source = [item.fileUrl ?? "", item.localPath ?? "", item.date.map { String($0.timeIntervalSince1970) } ?? ""].joined(separator: "|")
        return SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func snapshot(from history: [HistoryItem], hasThumbnail: (HistoryItem) -> Bool) -> WidgetSnapshot {
        let items = history
            .filter { $0.remoteURL != nil || $0.localFileURL != nil }
            .prefix(WidgetSnapshot.maximumItems)
            .map { item in
                let id = itemID(for: item)
                return WidgetSnapshot.Item(
                    id: id, url: item.remoteURL ?? item.localFileURL, name: item.fileName, date: item.date,
                    thumbnail: hasThumbnail(item) ? "\(id).jpg" : nil, isVideo: item.kind == .video
                )
            }
        return WidgetSnapshot(items: Array(items))
    }

    static func write(history: [HistoryItem], to directory: URL) throws -> WidgetSnapshot {
        let thumbnails = directory.appending(path: WidgetSnapshot.thumbnailFolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        let snapshot = snapshot(from: history) { item in
            let destination = thumbnails.appending(path: "\(itemID(for: item)).jpg")
            if FileManager.default.fileExists(atPath: destination.path) { return true }
            guard item.kind == .image, let source = item.existingLocalFileURL else { return false }
            return writeThumbnail(of: source, to: destination)
        }
        let kept = Set(snapshot.items.compactMap(\.thumbnail))
        for file in (try? FileManager.default.contentsOfDirectory(atPath: thumbnails.path)) ?? [] where !kept.contains(file) {
            try? FileManager.default.removeItem(at: thumbnails.appending(path: file))
        }
        try snapshot.encoded().write(to: directory.appending(path: WidgetSnapshot.fileName), options: .atomic)
        return snapshot
    }

    static func writeThumbnail(of source: URL, to destination: URL) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(output, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(output)
    }

    @MainActor static func update(history: [HistoryItem]) {
        guard let directory = WidgetSharedContainer.directory else { return }
        Task.detached(priority: .utility) {
            do {
                _ = try write(history: history, to: directory)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                Log.app.error("Couldn't write the widget snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor static func start() {
        observation?.cancel()
        observation = Task { @MainActor in
            for await history in Defaults.updates(.uploadHistory) {
                update(history: history)
            }
        }
    }
}
