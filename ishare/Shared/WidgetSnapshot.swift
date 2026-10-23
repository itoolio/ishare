import Foundation
import Security

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let fileName = "widget-snapshot.json"
    static let thumbnailFolder = "WidgetThumbnails"
    static let maximumItems = 6
    static let captureRegionURL = URL(string: "ishare://capture?type=region")!

    struct Item: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var url: URL?
        var name: String
        var date: Date?
        var thumbnail: String?
        var isVideo: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case url = "u"
            case name = "n"
            case date = "d"
            case thumbnail = "t"
            case isVideo = "v"
        }

        init(id: String, url: URL?, name: String, date: Date?, thumbnail: String?, isVideo: Bool) {
            self.id = id
            self.url = url
            self.name = name
            self.date = date
            self.thumbnail = thumbnail
            self.isVideo = isVideo
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            url = try container.decodeIfPresent(URL.self, forKey: .url)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            date = try container.decodeIfPresent(Date.self, forKey: .date)
            thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
            isVideo = try container.decodeIfPresent(Bool.self, forKey: .isVideo) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(url, forKey: .url)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(date, forKey: .date)
            try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
            if isVideo {
                try container.encode(isVideo, forKey: .isVideo)
            }
        }
    }

    var version = 1
    var items: [Item]

    static let empty = WidgetSnapshot(items: [])

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}

enum WidgetSharedContainer {
    static let fallbackGroupIdentifier = "L988J7YMK5.group.dev.adrian.ishare"

    static var groupIdentifier: String {
        signedGroupIdentifiers().first { $0.hasSuffix("group.dev.adrian.ishare") } ?? fallbackGroupIdentifier
    }

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static var snapshotURL: URL? {
        directory?.appending(path: WidgetSnapshot.fileName)
    }

    static var thumbnailDirectory: URL? {
        directory?.appending(path: WidgetSnapshot.thumbnailFolder, directoryHint: .isDirectory)
    }

    private static func signedGroupIdentifiers() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else { return [] }
        return value as? [String] ?? []
    }

    static func readSnapshot() -> WidgetSnapshot {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url), let snapshot = try? WidgetSnapshot.decode(data) else {
            return .empty
        }
        return snapshot
    }
}
