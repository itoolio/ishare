import CryptoKit
import Foundation

struct HistorySyncEntry: Codable, Equatable, Sendable {
    let id: String
    var link: String
    var shortLink: String?
    var deletionLink: String?
    var title: String?
    var altText: String?
    var uploaderName: String?
    var uploaderID: UUID?
    var date: Date
    var preview: Data?

    static let maximumPreviewBytes = 8 * 1024

    enum CodingKeys: String, CodingKey {
        case id = "i"
        case link = "u"
        case shortLink = "s"
        case deletionLink = "d"
        case title = "t"
        case altText = "a"
        case uploaderName = "n"
        case uploaderID = "p"
        case date = "c"
        case preview = "v"
    }

    static func identifier(forLink link: String) -> String {
        SHA256.hash(data: Data(link.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func isSyncable(_ item: HistoryItem) -> Bool {
        guard let link = item.fileUrl, let url = URL(string: link), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), let host = url.host(), !LocalNetworkAddress.isPrivateHost(host)
        else { return false }
        return true
    }

    init?(item: HistoryItem, uploaderName: String?, preview: Data? = nil, now: Date = Date()) {
        guard Self.isSyncable(item), let link = item.fileUrl else { return nil }
        id = Self.identifier(forLink: link)
        self.link = link
        shortLink = item.shortUrl
        deletionLink = item.deletionUrl
        title = item.title ?? item.localFileURL?.lastPathComponent
        altText = item.altText
        self.uploaderName = uploaderName ?? item.uploaderName
        uploaderID = item.uploaderId
        date = item.date ?? now
        self.preview = preview.flatMap { $0.count <= Self.maximumPreviewBytes ? $0 : nil }
    }

    var historyItem: HistoryItem {
        HistoryItem(
            fileUrl: link, deletionUrl: deletionLink, uploaderId: uploaderID, date: date, shortUrl: shortLink,
            altText: altText, uploaderName: uploaderName, title: title
        )
    }

    func merged(with other: HistorySyncEntry) -> HistorySyncEntry {
        var result = self
        result.shortLink = shortLink ?? other.shortLink
        result.deletionLink = deletionLink ?? other.deletionLink
        result.title = title ?? other.title
        result.altText = altText ?? other.altText
        result.uploaderName = uploaderName ?? other.uploaderName
        result.uploaderID = uploaderID ?? other.uploaderID
        result.date = min(date, other.date)
        result.preview = preview ?? other.preview
        return result
    }
}

struct HistorySyncState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = HistorySyncState.currentVersion
    var entries: [HistorySyncEntry] = []
    var tombstones: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case entries = "e"
        case tombstones = "x"
    }

    static let empty = HistorySyncState()
}

struct HistorySyncMergeResult: Equatable {
    let history: [HistoryItem]
    let state: HistorySyncState
}

enum HistorySyncMerge {
    static let maximumEntries = 200
    static let maximumTombstones = 1000
    static let tombstoneLifetime: TimeInterval = 90 * 86400

    static func tombstones(_ lhs: [String: Date], _ rhs: [String: Date], now: Date) -> [String: Date] {
        let union = lhs.merging(rhs) { max($0, $1) }
        let cutoff = now.addingTimeInterval(-tombstoneLifetime)
        let fresh = union.filter { $0.value >= cutoff }
        guard fresh.count > maximumTombstones else { return fresh }
        return Dictionary(uniqueKeysWithValues: fresh.sorted { $0.value > $1.value }.prefix(maximumTombstones).map { ($0.key, $0.value) })
    }

    static func isDeleted(_ entry: HistorySyncEntry, tombstones: [String: Date]) -> Bool {
        guard let deletedAt = tombstones[entry.id] else { return false }
        return deletedAt >= entry.date
    }

    static func merge(
        local: [HistoryItem], remote: HistorySyncState, localTombstones: [String: Date],
        uploaderName: (HistoryItem) -> String? = { $0.uploaderName }, previews: [String: Data] = [:], now: Date = Date()
    ) -> HistorySyncMergeResult {
        let allTombstones = tombstones(remote.tombstones, localTombstones, now: now)
        var byID: [String: HistorySyncEntry] = [:]
        for entry in remote.entries {
            byID[entry.id] = byID[entry.id].map { $0.merged(with: entry) } ?? entry
        }
        var localIDs = Set<String>()
        for item in local {
            guard var entry = HistorySyncEntry(item: item, uploaderName: uploaderName(item), now: now) else { continue }
            entry.preview = previews[entry.id]
            localIDs.insert(entry.id)
            byID[entry.id] = byID[entry.id].map { entry.merged(with: $0) } ?? entry
        }
        let live = byID.values
            .filter { !isDeleted($0, tombstones: allTombstones) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        let capped = Array(live.prefix(maximumEntries))
        let deletedIDs = Set(byID.values.filter { isDeleted($0, tombstones: allTombstones) }.map(\.id))

        var history = local.filter { item in
            guard let link = item.fileUrl, HistorySyncEntry.isSyncable(item) else { return true }
            return !deletedIDs.contains(HistorySyncEntry.identifier(forLink: link))
        }
        let incoming = capped.filter { !localIDs.contains($0.id) }.map(\.historyItem)
        if !incoming.isEmpty {
            history = (history + incoming).enumerated()
                .sorted { lhs, rhs in
                    let left = lhs.element.date ?? .distantPast
                    let right = rhs.element.date ?? .distantPast
                    return left != right ? left > right : lhs.offset < rhs.offset
                }
                .map(\.element)
        }
        return HistorySyncMergeResult(history: history, state: HistorySyncState(entries: capped, tombstones: allTombstones))
    }
}
