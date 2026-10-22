import AppKit
import Foundation
import Testing
@testable import ishare

struct HistoryPruningTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func items(count: Int, spacing: TimeInterval = 86400) -> [HistoryItem] {
        (0 ..< count).map { index in
            HistoryItem(fileUrl: "https://example.com/\(index).png", date: now.addingTimeInterval(-TimeInterval(index) * spacing))
        }
    }

    @Test(arguments: [(HistoryLimit.items25, 25), (.items50, 50), (.items100, 100), (.items250, 250), (.unlimited, 300)])
    func capsHistoryAtTheConfiguredSize(limit: HistoryLimit, expected: Int) {
        let pruned = HistoryPruning.pruned(items(count: 300, spacing: 1), limit: limit, retention: .never, now: now)
        #expect(pruned.count == expected)
        #expect(pruned.first?.fileUrl == "https://example.com/0.png")
    }

    @Test func dropsItemsOlderThanTheRetentionPeriod() {
        let pruned = HistoryPruning.pruned(items(count: 40), limit: .unlimited, retention: .days30, now: now)
        #expect(pruned.count == 31)
        #expect(HistoryPruning.pruned(items(count: 40), limit: .unlimited, retention: .days7, now: now).count == 8)
        #expect(HistoryPruning.pruned(items(count: 40), limit: .unlimited, retention: .never, now: now).count == 40)
    }

    @Test func keepsUndatedItemsWhenPruningByAge() {
        let undated = HistoryItem(fileUrl: "https://example.com/legacy.png")
        let pruned = HistoryPruning.pruned([undated] + items(count: 10, spacing: 86400 * 10), limit: .unlimited, retention: .days7, now: now)
        #expect(pruned.contains(undated))
        #expect(pruned.count == 2)
    }

    @Test func insertsNewestFirstAndAppliesBothLimits() {
        let newItem = HistoryItem(fileUrl: "https://example.com/new.png", date: now)
        let result = HistoryPruning.inserting(newItem, into: items(count: 25, spacing: 1), limit: .items25, retention: .days90, now: now)
        #expect(result.count == 25)
        #expect(result.first == newItem)
        #expect(!result.contains { $0.fileUrl == "https://example.com/24.png" })
    }
}

struct HistoryItemTests {
    @Test(arguments: [
        ("https://example.com/a.PNG", HistoryItemKind.image),
        ("https://example.com/a.gif", .image),
        ("https://example.com/a.mp4", .video),
        ("https://example.com/a.mov", .video),
        ("https://example.com/a.zip", .other),
        ("https://example.com/view?id=1", .other),
    ])
    func classifiesItemsByExtension(url: String, kind: HistoryItemKind) {
        #expect(HistoryItem(fileUrl: url).kind == kind)
    }

    @Test func fallsBackToTheLocalFileForNameAndKind() {
        let item = HistoryItem(fileUrl: "https://example.com/", localPath: "/tmp/capture.mov")
        #expect(item.fileName == "capture.mov")
        #expect(item.kind == .video)
    }

    @Test func offersServerDeletionOnlyWithADeletionURLOrS3Key() {
        #expect(!HistoryItem(fileUrl: "https://example.com/a.png").canDeleteFromServer)
        #expect(!HistoryItem(fileUrl: "https://example.com/a.png", deletionUrl: "  ").canDeleteFromServer)
        #expect(HistoryItem(fileUrl: "https://example.com/a.png", deletionUrl: "https://example.com/delete/a").canDeleteFromServer)
        #expect(HistoryItem(fileUrl: "https://example.com/a.png", s3Key: "2026/a.png").canDeleteFromServer)
    }

    @Test func resolvesTheUploader() {
        let uploader = CustomUploader(name: "zipline", requestURL: "https://share.example.com/api", headers: nil, formData: nil, fileFormName: "file", responseURL: "{{url}}")
        let custom = HistoryItem(fileUrl: "https://share.example.com/a.png", uploaderId: uploader.id)
        let imgur = HistoryItem(fileUrl: "https://i.imgur.com/abc.png", deletionUrl: "https://api.imgur.com/3/image/xyz")
        let unknown = HistoryItem(fileUrl: "https://example.com/a.png")
        #expect(custom.uploader == .custom(uploader.id))
        #expect(custom.uploaderName(among: [uploader]) == "zipline")
        #expect(custom.uploaderName(among: []) == nil)
        #expect(imgur.uploader == .imgur)
        #expect(imgur.uploaderName(among: []) == "Imgur")
        #expect(unknown.uploader == .unknown)
        #expect(HistoryItem(fileUrl: "https://notimgur.com/a.png").uploader == .unknown)
    }
}

struct HistoryFilterTests {
    let zipline = UUID()
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    var history: [HistoryItem] {
        [
            HistoryItem(fileUrl: "https://share.example.com/u/dashboard.png", uploaderId: zipline, date: date),
            HistoryItem(fileUrl: "https://i.imgur.com/clip.mp4", deletionUrl: "https://api.imgur.com/3/image/a", date: date),
            HistoryItem(fileUrl: "https://files.example.com/report.pdf", localPath: "/Users/me/Pictures/ishare-report.pdf", date: date),
        ]
    }

    func name(_ item: HistoryItem) -> String? {
        item.uploaderId == zipline ? "Zipline" : item.uploader == .imgur ? "Imgur" : nil
    }

    func dateTexts(_: Date) -> [String] {
        ["15 January 2027", "Friday"]
    }

    func apply(_ filter: HistoryFilter) -> [String] {
        filter.apply(to: history, uploaderName: name, dateTexts: dateTexts).compactMap(\.fileUrl)
    }

    @Test func matchesEverythingWithoutCriteria() {
        #expect(apply(HistoryFilter()).count == 3)
        #expect(!HistoryFilter().isActive)
    }

    @Test func searchesURLFileNameUploaderAndDate() {
        #expect(apply(HistoryFilter(query: "dashboard")) == ["https://share.example.com/u/dashboard.png"])
        #expect(apply(HistoryFilter(query: "ZIPLINE")) == ["https://share.example.com/u/dashboard.png"])
        #expect(apply(HistoryFilter(query: "ishare-report")) == ["https://files.example.com/report.pdf"])
        #expect(apply(HistoryFilter(query: "imgur.com")) == ["https://i.imgur.com/clip.mp4"])
        #expect(apply(HistoryFilter(query: "january")).count == 3)
        #expect(apply(HistoryFilter(query: "friday imgur")) == ["https://i.imgur.com/clip.mp4"])
        #expect(apply(HistoryFilter(query: "nothing-like-this")).isEmpty)
    }

    @Test func filtersByUploaderAndType() {
        #expect(apply(HistoryFilter(uploader: .uploader(.custom(zipline)))) == ["https://share.example.com/u/dashboard.png"])
        #expect(apply(HistoryFilter(uploader: .uploader(.imgur))) == ["https://i.imgur.com/clip.mp4"])
        #expect(apply(HistoryFilter(kind: .images)) == ["https://share.example.com/u/dashboard.png"])
        #expect(apply(HistoryFilter(kind: .videos)) == ["https://i.imgur.com/clip.mp4"])
        #expect(apply(HistoryFilter(kind: .other)) == ["https://files.example.com/report.pdf"])
        #expect(apply(HistoryFilter(uploader: .uploader(.imgur), kind: .images)).isEmpty)
        #expect(HistoryFilter(kind: .videos).isActive)
    }

    @Test func listsDistinctUploadersInOrder() {
        #expect((history + history).distinctUploaders() == [.custom(zipline), .imgur, .unknown])
    }
}
