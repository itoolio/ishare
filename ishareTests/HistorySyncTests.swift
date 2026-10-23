import Defaults
import Foundation
import Testing
@testable import ishare

final class MemoryKeyValueStore: KeyValueSyncStore {
    var values: [String: Data] = [:]
    var synchronizeCount = 0

    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    var storedKeys: [String] { Array(values.keys) }
    func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }
}

struct HistorySyncEntryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func usesAStableIdentifierPerLink() {
        let id = HistorySyncEntry.identifier(forLink: "https://example.com/a.png")
        #expect(id == HistorySyncEntry.identifier(forLink: "https://example.com/a.png"))
        #expect(id != HistorySyncEntry.identifier(forLink: "https://example.com/b.png"))
        #expect(id.count == 32)
    }

    @Test func syncsOnlyPublicWebLinks() {
        #expect(HistorySyncEntry.isSyncable(HistoryItem(fileUrl: "https://i.imgur.com/a.png")))
        #expect(!HistorySyncEntry.isSyncable(HistoryItem(fileUrl: "file:///Users/me/a.png")))
        #expect(!HistorySyncEntry.isSyncable(HistoryItem(fileUrl: "http://192.168.1.4:5000/t/a.png")))
        #expect(!HistorySyncEntry.isSyncable(HistoryItem(localPath: "/tmp/a.png")))
    }

    @Test func keepsLinksAndMetadataButNotLocalFiles() throws {
        let item = HistoryItem(
            fileUrl: "https://example.com/a.png", deletionUrl: "https://example.com/delete/a", uploaderId: UUID(), s3Key: "a.png",
            localPath: "/Users/me/Pictures/Screenshot.png", date: now, shortUrl: "https://is.gd/x", altText: "A chart", localIdentifier: "photo-1"
        )
        let entry = try #require(HistorySyncEntry(item: item, uploaderName: "My Server", preview: Data(repeating: 1, count: 10_000)))
        #expect(entry.preview == nil)
        #expect(entry.title == "Screenshot.png")
        let restored = entry.historyItem
        #expect(restored.fileUrl == item.fileUrl)
        #expect(restored.deletionUrl == item.deletionUrl)
        #expect(restored.shortUrl == item.shortUrl)
        #expect(restored.altText == "A chart")
        #expect(restored.uploaderName == "My Server")
        #expect(restored.uploaderId == item.uploaderId)
        #expect(restored.date == now)
        #expect(restored.localPath == nil)
        #expect(restored.s3Key == nil)
        #expect(restored.localIdentifier == nil)
    }

    @Test func fallsBackToTheSyncedUploaderName() {
        let item = HistoryItem(fileUrl: "https://example.com/a.png", uploaderId: UUID(), uploaderName: "Other Mac's Server")
        #expect(item.uploaderName(among: []) == "Other Mac's Server")
    }
}

struct HistorySyncMergeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ index: Int, age: TimeInterval = 0, alt: String? = nil) -> HistoryItem {
        HistoryItem(fileUrl: "https://example.com/\(index).png", date: now.addingTimeInterval(-age - TimeInterval(index)), altText: alt)
    }

    func entry(_ index: Int, age: TimeInterval = 0) -> HistorySyncEntry {
        HistorySyncEntry(item: item(index, age: age), uploaderName: nil, now: now)!
    }

    @Test func unionsLocalAndRemoteEntries() {
        let remote = HistorySyncState(entries: [entry(2), entry(3)])
        let result = HistorySyncMerge.merge(local: [item(1), item(2)], remote: remote, localTombstones: [:], now: now)
        #expect(result.history.compactMap(\.fileUrl) == ["https://example.com/1.png", "https://example.com/2.png", "https://example.com/3.png"])
        #expect(result.state.entries.map(\.link) == result.history.compactMap(\.fileUrl))
    }

    @Test func isCommutativeAndIdempotent() {
        let a = HistoryItem(fileUrl: "https://example.com/a.png", date: now)
        let b = HistoryItem(fileUrl: "https://example.com/b.png", date: now.addingTimeInterval(-10))
        let fromA = HistorySyncMerge.merge(local: [a], remote: .empty, localTombstones: [:], now: now).state
        let fromB = HistorySyncMerge.merge(local: [b], remote: .empty, localTombstones: [:], now: now).state
        let onA = HistorySyncMerge.merge(local: [a], remote: fromB, localTombstones: [:], now: now)
        let onB = HistorySyncMerge.merge(local: [b], remote: fromA, localTombstones: [:], now: now)
        #expect(onA.state == onB.state)
        #expect(onA.history.compactMap(\.fileUrl) == onB.history.compactMap(\.fileUrl))
        let again = HistorySyncMerge.merge(local: onA.history, remote: onA.state, localTombstones: [:], now: now)
        #expect(again.state == onA.state)
        #expect(again.history == onA.history)
    }

    @Test func fillsMissingFieldsFromTheOtherMac() {
        var remoteEntry = entry(1)
        remoteEntry.altText = "From the other Mac"
        remoteEntry.deletionLink = "https://example.com/delete/1"
        let result = HistorySyncMerge.merge(local: [item(1)], remote: HistorySyncState(entries: [remoteEntry]), localTombstones: [:], now: now)
        #expect(result.state.entries.first?.altText == "From the other Mac")
        #expect(result.state.entries.first?.deletionLink == "https://example.com/delete/1")
        #expect(result.history.count == 1)
    }

    @Test func tombstonesRemoveEntriesEverywhere() {
        let deleted = HistorySyncEntry.identifier(forLink: "https://example.com/2.png")
        let remote = HistorySyncState(entries: [entry(2), entry(3)], tombstones: [:])
        let result = HistorySyncMerge.merge(local: [item(1), item(2)], remote: remote, localTombstones: [deleted: now], now: now)
        #expect(!result.history.contains { $0.fileUrl == "https://example.com/2.png" })
        #expect(!result.state.entries.contains { $0.id == deleted })
        #expect(result.state.tombstones[deleted] == now)

        let otherMac = HistorySyncMerge.merge(local: [item(2), item(4)], remote: result.state, localTombstones: [:], now: now)
        #expect(otherMac.history.compactMap(\.fileUrl) == ["https://example.com/1.png", "https://example.com/3.png", "https://example.com/4.png"])
    }

    @Test func aNewerUploadOfTheSameLinkOutlivesAnOldTombstone() {
        let id = HistorySyncEntry.identifier(forLink: "https://example.com/1.png")
        let reuploaded = HistoryItem(fileUrl: "https://example.com/1.png", date: now)
        let result = HistorySyncMerge.merge(local: [reuploaded], remote: .empty, localTombstones: [id: now.addingTimeInterval(-60)], now: now)
        #expect(result.history == [reuploaded])
    }

    @Test func expiresOldTombstonesAndCapsTheirCount() {
        let old = now.addingTimeInterval(-HistorySyncMerge.tombstoneLifetime - 1)
        var many: [String: Date] = ["old": old]
        for index in 0 ..< 1200 {
            many["t\(index)"] = now.addingTimeInterval(-TimeInterval(index))
        }
        let merged = HistorySyncMerge.tombstones(many, [:], now: now)
        #expect(merged["old"] == nil)
        #expect(merged.count == HistorySyncMerge.maximumTombstones)
        #expect(merged["t0"] != nil)
        #expect(merged["t1199"] == nil)
    }

    @Test func capsTheSyncedEntriesAtTheNewest200() {
        let local = (0 ..< 260).map { item($0) }
        let result = HistorySyncMerge.merge(local: local, remote: .empty, localTombstones: [:], now: now)
        #expect(result.state.entries.count == HistorySyncMerge.maximumEntries)
        #expect(result.state.entries.first?.link == "https://example.com/0.png")
        #expect(result.history.count == 260)
    }

    @Test func keepsUnsyncableLocalItems() {
        let local = [HistoryItem(localPath: "/tmp/a.png", date: now), item(1)]
        let result = HistorySyncMerge.merge(local: local, remote: HistorySyncState(entries: [entry(2)]), localTombstones: [:], now: now)
        #expect(result.history.count == 3)
        #expect(result.history.contains { $0.localPath == "/tmp/a.png" })
        #expect(result.state.entries.count == 2)
    }
}

struct HistorySyncCodecTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func state(count: Int, previews: Bool = false) -> HistorySyncState {
        let entries = (0 ..< count).map { index in
            var entry = HistorySyncEntry(
                item: HistoryItem(
                    fileUrl: "https://example.com/uploads/\(UUID().uuidString)-\(index).png",
                    deletionUrl: "https://example.com/delete/\(UUID().uuidString)",
                    date: now.addingTimeInterval(-TimeInterval(index)), shortUrl: "https://is.gd/\(index)",
                    altText: "Alt text number \(index) describing the screenshot in a long sentence"
                ),
                uploaderName: "Server", now: now
            )!
            if previews {
                entry.preview = Data((0 ..< 8000).map { _ in UInt8.random(in: 0 ... 255) })
            }
            return entry
        }
        return HistorySyncState(entries: entries, tombstones: ["gone": now])
    }

    @Test func roundTripsThroughTheStore() throws {
        let store = MemoryKeyValueStore()
        let original = state(count: 30)
        try HistorySyncCodec.write(original, to: store, now: now)
        #expect(try HistorySyncCodec.read(from: store) == original)
        #expect(store.synchronizeCount == 1)
    }

    @Test func returnsNilForAnEmptyStore() throws {
        #expect(try HistorySyncCodec.read(from: MemoryKeyValueStore()) == nil)
    }

    @Test func splitsLargePayloadsIntoChunksWithinTheLimits() throws {
        let store = MemoryKeyValueStore()
        let written = try HistorySyncCodec.write(state(count: 200, previews: true), to: store, now: now)
        let manifest = try #require(HistorySyncCodec.readManifest(from: store))
        #expect(manifest.chunkCount > 1)
        #expect(store.values.count == manifest.chunkCount + 1)
        #expect(store.values.values.allSatisfy { $0.count <= HistorySyncCodec.chunkSize })
        #expect(store.values.values.reduce(0) { $0 + $1.count } <= HistorySyncCodec.byteBudget + 1024)
        #expect(store.values.count < 1024)
        #expect(written.entries.contains { $0.preview == nil })
        #expect(try HistorySyncCodec.read(from: store) == written)
    }

    @Test func chunksReassembleExactly() {
        let payload = Data((0 ..< 150_000).map { UInt8($0 % 251) })
        let chunks = HistorySyncCodec.chunks(of: payload, size: 60_000)
        #expect(chunks.map(\.count) == [60_000, 60_000, 30_000])
        #expect(chunks.reduce(Data(), +) == payload)
        #expect(HistorySyncCodec.chunks(of: Data()).isEmpty)
    }

    @Test func dropsPreviewsBeforeEntriesToFitTheBudget() throws {
        let (fitted, payload) = try HistorySyncCodec.fitted(state(count: 50, previews: true), budget: 100_000)
        #expect(payload.count <= 100_000)
        #expect(fitted.entries.count == 50)
        #expect(fitted.entries.first?.preview != nil)
        #expect(fitted.entries.last?.preview == nil)
    }

    @Test func replacesTheOldGenerationAndSkipsUnchangedWrites() throws {
        let store = MemoryKeyValueStore()
        try HistorySyncCodec.write(state(count: 5), to: store, now: now, generation: "one")
        let next = state(count: 6)
        try HistorySyncCodec.write(next, to: store, now: now, generation: "two")
        #expect(!store.values.keys.contains { $0.hasPrefix("historySync.one.") })
        #expect(try HistorySyncCodec.read(from: store) == next)
        try HistorySyncCodec.write(next, to: store, now: now, generation: "three")
        #expect(HistorySyncCodec.readManifest(from: store)?.generation == "two")
        store.values["unrelated"] = Data([1])
        HistorySyncCodec.removeAll(from: store)
        #expect(store.values.keys.sorted() == ["unrelated"])
    }

    @Test func detectsIncompleteOrCorruptCopies() throws {
        let store = MemoryKeyValueStore()
        try HistorySyncCodec.write(state(count: 200, previews: true), to: store, now: now, generation: "g")
        let manifest = try #require(HistorySyncCodec.readManifest(from: store))
        let lastChunk = HistorySyncCodec.chunkKey(generation: "g", index: manifest.chunkCount - 1)
        let saved = store.values[lastChunk]
        store.values[lastChunk] = nil
        #expect(throws: HistorySyncCodecError.missingChunk(manifest.chunkCount - 1)) { try HistorySyncCodec.read(from: store) }
        store.values[lastChunk] = Data([1, 2, 3])
        #expect(throws: HistorySyncCodecError.digestMismatch) { try HistorySyncCodec.read(from: store) }
        store.values[lastChunk] = saved
        #expect(try HistorySyncCodec.read(from: store) != nil)
    }

    @Test func makesTinyPreviews() throws {
        let image = try #require(QRCodeRenderer.image(for: "https://example.com/preview", targetPixels: 800))
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).jpg")
        try #require(HistorySyncPreviews.jpeg(image, quality: 0.9)).write(to: url)
        let preview = try #require(HistorySyncPreviews.make(fromImageAt: url))
        #expect(preview.count <= HistorySyncEntry.maximumPreviewBytes)
    }
}

@MainActor
struct HistorySyncEngineTests {
    @Test func twoMacsConvergeThroughTheSharedStore() throws {
        let store = MemoryKeyValueStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let macA = [HistoryItem(fileUrl: "https://example.com/a.png", date: now)]
        let macB = [HistoryItem(fileUrl: "https://example.com/b.png", date: now.addingTimeInterval(-5))]
        let first = HistorySyncMerge.merge(local: macA, remote: try HistorySyncCodec.read(from: store) ?? .empty, localTombstones: [:], now: now)
        try HistorySyncCodec.write(first.state, to: store, now: now)
        let second = HistorySyncMerge.merge(local: macB, remote: try HistorySyncCodec.read(from: store) ?? .empty, localTombstones: [:], now: now)
        try HistorySyncCodec.write(second.state, to: store, now: now)
        let third = HistorySyncMerge.merge(local: first.history, remote: try HistorySyncCodec.read(from: store) ?? .empty, localTombstones: [:], now: now)
        #expect(third.history.compactMap(\.fileUrl) == ["https://example.com/a.png", "https://example.com/b.png"])
        #expect(second.history.compactMap(\.fileUrl) == third.history.compactMap(\.fileUrl))
    }

    @Test func recordsTombstonesForDeletedSyncableItems() {
        let engine = HistorySync(store: MemoryKeyValueStore())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        engine.recordDeletion(of: [HistoryItem(fileUrl: "https://example.com/z.png"), HistoryItem(localPath: "/tmp/z.png")], now: now)
        let id = HistorySyncEntry.identifier(forLink: "https://example.com/z.png")
        #expect(Defaults[.historySyncTombstones][id] == now)
        #expect(Defaults[.historySyncTombstones].count == 1)
        Defaults[.historySyncTombstones] = [:]
    }

    @Test func isOffByDefault() {
        #expect(Defaults.Keys.historySyncEnabled.defaultValue == false)
        #expect(SettingsTransfer.preferenceNames.isSuperset(of: ["historySyncEnabled", "showQRCodeAfterUpload", "localShareExpiry", "localShareMaxDownloads"]))
    }
}
