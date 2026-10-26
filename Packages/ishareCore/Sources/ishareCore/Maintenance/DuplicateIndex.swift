import CryptoKit
import Foundation

public enum ContentHash {
    public static let defaultChunkSize = 1 << 20

    public static func sha256(of url: URL, chunkSize: Int = defaultChunkSize) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    public static func sha256(of data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum DuplicatePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask
    case alwaysReuse
    case never

    public var id: Self { self }

    public var titleKey: String {
        switch self {
        case .ask: "Ask"
        case .alwaysReuse: "Always reuse the existing link"
        case .never: "Never"
        }
    }

    public var automaticDecision: DuplicateDecision? {
        switch self {
        case .ask: nil
        case .alwaysReuse: .reuse
        case .never: .uploadAgain
        }
    }
}

public enum DuplicateDecision: Equatable, Sendable {
    case reuse
    case uploadAgain
}

public struct DuplicateIndexEntry: Codable, Equatable, Sendable {
    public var hash: String
    public var destination: String
    public var link: String
    public var date: Date

    public init(hash: String, destination: String, link: String, date: Date) {
        self.hash = hash
        self.destination = destination
        self.link = link
        self.date = date
    }
}

public struct DuplicateIndex: Codable, Equatable, Sendable {
    public static let defaultCapacity = 500

    public private(set) var entries: [DuplicateIndexEntry]

    public init(entries: [DuplicateIndexEntry] = []) {
        self.entries = entries
    }

    public mutating func remember(hash: String, destination: String, link: String, date: Date, capacity: Int = defaultCapacity) {
        entries.removeAll { $0.hash == hash && $0.destination == destination && $0.link == link }
        entries.insert(DuplicateIndexEntry(hash: hash, destination: destination, link: link, date: date), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    public func links(hash: String, destination: String) -> [String] {
        entries.filter { $0.hash == hash && $0.destination == destination }.map(\.link)
    }

    public func existingLink(hash: String, destination: String, isLive: (String) -> Bool) -> String? {
        links(hash: hash, destination: destination).first(where: isLive)
    }

    public mutating func forget(link: String) {
        entries.removeAll { $0.link == link }
    }

    public mutating func prune(keeping isLive: (String) -> Bool) {
        entries.removeAll { !isLive($0.link) }
    }
}
