import Defaults
import Foundation

struct HistoryItem: Codable, Hashable, Defaults.Serializable {
    var fileUrl: String?
    var deletionUrl: String?
    var uploaderId: UUID?
    var s3Key: String?
    var localPath: String?
    var date: Date?
    var shortUrl: String?
    var altText: String?
    var localIdentifier: String?
    var id: Self { self }
}

enum HistoryItemKind: String, CaseIterable, Identifiable, Sendable {
    case image
    case video
    case other

    var id: Self { self }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp", "avif"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "avi", "mkv"]

    init(fileExtension: String) {
        let ext = fileExtension.lowercased()
        if Self.imageExtensions.contains(ext) {
            self = .image
        } else if Self.videoExtensions.contains(ext) {
            self = .video
        } else {
            self = .other
        }
    }
}

enum HistoryUploader: Hashable, Sendable {
    case imgur
    case custom(UUID)
    case unknown
}

extension HistoryItem {
    var remoteURL: URL? {
        fileUrl.flatMap(URL.init(string:))
    }

    var shortURL: URL? {
        shortUrl.flatMap(URL.init(string:))
    }

    var preferredURL: URL? {
        shortURL ?? remoteURL
    }

    var localFileURL: URL? {
        guard let localPath, !localPath.isEmpty else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    var existingLocalFileURL: URL? {
        guard let url = localFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var fileName: String {
        let remoteName = remoteURL?.lastPathComponent ?? ""
        if !remoteName.isEmpty, remoteName != "/" {
            return remoteName
        }
        return localFileURL?.lastPathComponent ?? fileUrl ?? ""
    }

    var fileExtension: String {
        let remoteExtension = remoteURL?.pathExtension ?? ""
        return remoteExtension.isEmpty ? localFileURL?.pathExtension ?? "" : remoteExtension
    }

    var kind: HistoryItemKind {
        HistoryItemKind(fileExtension: fileExtension)
    }

    var canDeleteFromServer: Bool {
        !(deletionUrl ?? "").trimmingCharacters(in: .whitespaces).isEmpty || !(s3Key ?? "").isEmpty || !(localIdentifier ?? "").isEmpty
    }

    var uploader: HistoryUploader {
        if let uploaderId {
            return .custom(uploaderId)
        }
        let hosts = [remoteURL?.host(), deletionUrl.flatMap(URL.init(string:))?.host()].compactMap { $0?.lowercased() }
        return hosts.contains { $0 == "imgur.com" || $0.hasSuffix(".imgur.com") } ? .imgur : .unknown
    }

    func uploaderName(among uploaders: [CustomUploader]) -> String? {
        switch uploader {
        case .imgur:
            "Imgur"
        case let .custom(id):
            uploaders.first { $0.id == id }?.name
        case .unknown:
            nil
        }
    }
}

enum HistoryLimit: Int, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case items25 = 25
    case items50 = 50
    case items100 = 100
    case items250 = 250
    case unlimited = 0

    var id: Self { self }

    var maximumCount: Int? {
        self == .unlimited ? nil : rawValue
    }
}

enum HistoryRetention: Int, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case never = 0

    var id: Self { self }

    var maximumAge: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue) * 86400
    }
}

enum HistoryPruning {
    static func pruned(_ items: [HistoryItem], limit: HistoryLimit, retention: HistoryRetention, now: Date = Date()) -> [HistoryItem] {
        var result = items
        if let maximumAge = retention.maximumAge {
            let cutoff = now.addingTimeInterval(-maximumAge)
            result.removeAll { item in
                guard let date = item.date else { return false }
                return date < cutoff
            }
        }
        if let maximumCount = limit.maximumCount, result.count > maximumCount {
            result.removeLast(result.count - maximumCount)
        }
        return result
    }

    static func inserting(_ item: HistoryItem, into items: [HistoryItem], limit: HistoryLimit, retention: HistoryRetention, now: Date = Date()) -> [HistoryItem] {
        pruned([item] + items, limit: limit, retention: retention, now: now)
    }
}

func addToUploadHistory(_ item: HistoryItem) {
    NSLog("Adding item to upload history: %@", item.fileUrl ?? "nil")
    Defaults[.uploadHistory] = HistoryPruning.inserting(
        item, into: Defaults[.uploadHistory], limit: Defaults[.historyLimit], retention: Defaults[.historyRetention]
    )
}

func applyHistoryLimits() {
    let history = Defaults[.uploadHistory]
    let pruned = HistoryPruning.pruned(history, limit: Defaults[.historyLimit], retention: Defaults[.historyRetention])
    if pruned != history {
        Defaults[.uploadHistory] = pruned
    }
}

func removeFromUploadHistory(_ item: HistoryItem) {
    Defaults[.uploadHistory].removeAll { $0 == item }
}

func clearUploadHistory() {
    Defaults[.uploadHistory] = []
}
