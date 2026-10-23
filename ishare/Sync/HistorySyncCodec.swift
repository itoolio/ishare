import CryptoKit
import Foundation

protocol KeyValueSyncStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    var storedKeys: [String] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueSyncStore {
    var storedKeys: [String] {
        Array(dictionaryRepresentation.keys)
    }
}

struct HistorySyncManifest: Codable, Equatable, Sendable {
    var version: Int
    var generation: String
    var chunkCount: Int
    var digest: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case generation = "g"
        case chunkCount = "n"
        case digest = "h"
        case updatedAt = "t"
    }
}

enum HistorySyncCodecError: Error, Equatable {
    case missingChunk(Int)
    case digestMismatch
    case unsupportedVersion(Int)
    case corrupt
}

enum HistorySyncCodec {
    static let keyPrefix = "historySync."
    static let manifestKey = "historySync.manifest"
    static let chunkSize = 60 * 1024
    static let byteBudget = 768 * 1024
    static let maximumChunks = 16

    static func chunkKey(generation: String, index: Int) -> String {
        "\(keyPrefix)\(generation).\(index)"
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func payload(for state: HistorySyncState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(state)
        return try (json as NSData).compressed(using: .lzfse) as Data
    }

    static func state(fromPayload payload: Data) throws -> HistorySyncState {
        guard let json = try? (payload as NSData).decompressed(using: .lzfse) as Data else { throw HistorySyncCodecError.corrupt }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(HistorySyncState.self, from: json)
        guard state.version <= HistorySyncState.currentVersion else { throw HistorySyncCodecError.unsupportedVersion(state.version) }
        return state
    }

    static func fitted(_ state: HistorySyncState, budget: Int = byteBudget) throws -> (state: HistorySyncState, payload: Data) {
        var state = state
        var payload = try payload(for: state)
        while payload.count > budget {
            let previewIndices = state.entries.indices.filter { state.entries[$0].preview != nil }
            if !previewIndices.isEmpty {
                let excess = payload.count - budget
                let count = min(previewIndices.count, max(1, excess / HistorySyncEntry.maximumPreviewBytes + 1))
                for index in previewIndices.suffix(count) {
                    state.entries[index].preview = nil
                }
            } else if !state.entries.isEmpty {
                state.entries.removeLast(max(1, state.entries.count / 10))
            } else if !state.tombstones.isEmpty {
                let keep = state.tombstones.sorted { $0.value > $1.value }.prefix(state.tombstones.count / 2)
                state.tombstones = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            } else {
                break
            }
            payload = try self.payload(for: state)
        }
        return (state, payload)
    }

    static func chunks(of payload: Data, size: Int = chunkSize) -> [Data] {
        guard !payload.isEmpty else { return [] }
        return stride(from: 0, to: payload.count, by: size).map { payload.subdata(in: $0 ..< min($0 + size, payload.count)) }
    }

    static func readManifest(from store: KeyValueSyncStore) -> HistorySyncManifest? {
        guard let data = store.data(forKey: manifestKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(HistorySyncManifest.self, from: data)
    }

    static func read(from store: KeyValueSyncStore) throws -> HistorySyncState? {
        guard let manifest = readManifest(from: store) else { return nil }
        guard manifest.version <= HistorySyncState.currentVersion else { throw HistorySyncCodecError.unsupportedVersion(manifest.version) }
        guard manifest.chunkCount <= maximumChunks else { throw HistorySyncCodecError.corrupt }
        var payload = Data()
        for index in 0 ..< manifest.chunkCount {
            guard let chunk = store.data(forKey: chunkKey(generation: manifest.generation, index: index)) else {
                throw HistorySyncCodecError.missingChunk(index)
            }
            payload.append(chunk)
        }
        guard digest(payload) == manifest.digest else { throw HistorySyncCodecError.digestMismatch }
        return try state(fromPayload: payload)
    }

    @discardableResult
    static func write(_ state: HistorySyncState, to store: KeyValueSyncStore, now: Date = Date(), generation: String = makeGeneration()) throws -> HistorySyncState {
        let (fitted, payload) = try fitted(state)
        let digest = digest(payload)
        if let current = readManifest(from: store), current.digest == digest {
            return fitted
        }
        let pieces = chunks(of: payload)
        for (index, piece) in pieces.enumerated() {
            store.set(piece, forKey: chunkKey(generation: generation, index: index))
        }
        let manifest = HistorySyncManifest(version: HistorySyncState.currentVersion, generation: generation, chunkCount: pieces.count, digest: digest, updatedAt: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        store.set(try encoder.encode(manifest), forKey: manifestKey)
        let live = Set(pieces.indices.map { chunkKey(generation: generation, index: $0) } + [manifestKey])
        for key in store.storedKeys where key.hasPrefix(keyPrefix) && !live.contains(key) {
            store.removeObject(forKey: key)
        }
        store.synchronize()
        return fitted
    }

    static func makeGeneration() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    static func removeAll(from store: KeyValueSyncStore) {
        for key in store.storedKeys where key.hasPrefix(keyPrefix) {
            store.removeObject(forKey: key)
        }
        store.synchronize()
    }
}
