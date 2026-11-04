import Foundation
import Testing
@testable import ishareCore

struct StorageSummaryTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func addsUpLocalAndRemoteUse() {
        let files = [
            StorageFile(kind: .image, bytes: 2_000_000, date: now), StorageFile(kind: .video, bytes: 150_000_000, date: now.addingTimeInterval(-40 * 86400)),
            StorageFile(kind: .image, bytes: 1_000_000, date: now.addingTimeInterval(-31 * 86400)),
        ]
        let summary = StorageSummary(files: files, cacheBytes: 30_000_000, remote: [("i.imgur.com", 5), ("s3.example", 10), ("i.imgur.com", 7)], now: now)
        #expect(summary.imageCount == 2 && summary.videoCount == 1)
        #expect(summary.localBytes == 153_000_000)
        #expect(summary.oldCount == 2 && summary.oldBytes == 151_000_000)
        #expect(summary.suggestsCleaningOldFiles)
        #expect(summary.suggestsClearingCache)
        #expect(summary.hostsBySize.map(\.host) == ["i.imgur.com", "s3.example"])
        #expect(summary.hostsBySize.first?.bytes == 12)
    }

    @Test func staysQuietWhenThereIsLittleToClean() {
        let summary = StorageSummary(files: [StorageFile(kind: .image, bytes: 10, date: now)], now: now)
        #expect(!summary.suggestsCleaningOldFiles && !summary.suggestsClearingCache)
    }
}
