import Foundation

public struct StorageFile: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case image
        case video
    }

    public var kind: Kind
    public var bytes: Int64
    public var date: Date

    public init(kind: Kind, bytes: Int64, date: Date) {
        self.kind = kind
        self.bytes = bytes
        self.date = date
    }
}

public struct StorageSummary: Equatable, Sendable {
    public static let suggestionAge = 30
    public static let suggestionMinimumBytes: Int64 = 100 * 1_048_576

    public var imageBytes: Int64 = 0
    public var imageCount = 0
    public var videoBytes: Int64 = 0
    public var videoCount = 0
    public var oldBytes: Int64 = 0
    public var oldCount = 0
    public var cacheBytes: Int64 = 0
    public var remoteBytes: [String: Int64] = [:]

    public init(files: [StorageFile], cacheBytes: Int64 = 0, remote: [(host: String, bytes: Int64)] = [], now: Date = Date(), oldAfterDays: Int = suggestionAge) {
        let cutoff = now.addingTimeInterval(-Double(oldAfterDays) * 86400)
        for file in files {
            switch file.kind {
            case .image:
                imageBytes += file.bytes
                imageCount += 1
            case .video:
                videoBytes += file.bytes
                videoCount += 1
            }
            if file.date < cutoff {
                oldBytes += file.bytes
                oldCount += 1
            }
        }
        self.cacheBytes = cacheBytes
        for entry in remote {
            remoteBytes[entry.host, default: 0] += entry.bytes
        }
    }

    public var localBytes: Int64 {
        imageBytes + videoBytes
    }

    public var suggestsCleaningOldFiles: Bool {
        oldBytes >= Self.suggestionMinimumBytes
    }

    public var suggestsClearingCache: Bool {
        cacheBytes >= 20 * 1_048_576
    }

    public var hostsBySize: [(host: String, bytes: Int64)] {
        remoteBytes.map { ($0.key, $0.value) }.sorted { $0.bytes == $1.bytes ? $0.host < $1.host : $0.bytes > $1.bytes }
    }
}
