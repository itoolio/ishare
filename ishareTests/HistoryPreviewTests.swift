import Foundation
import Testing
@testable import ishare

struct HistoryPreviewTests {
    private func localItem(named name: String) throws -> HistoryItem {
        let url = try Fixtures.temporaryFile(named: name, contents: Data([0x89, 0x50, 0x4E, 0x47]))
        return HistoryItem(fileUrl: "https://example.com/\(name)", localPath: url.path)
    }

    @Test func previewsLocalFilesInVisibleOrderAndSkipsMissingOnes() throws {
        let first = try localItem(named: "first.png")
        let missing = HistoryItem(fileUrl: "https://example.com/gone.png", localPath: "/nonexistent/gone.png")
        let second = try localItem(named: "second.png")
        let urls = HistoryPreview.urls(for: [first, missing, second])
        #expect(urls.map(\.lastPathComponent) == ["first.png", "second.png"])
    }

    @Test func startsAtTheSelectionOrTheFirstVisibleItem() throws {
        let first = try localItem(named: "a.png")
        let second = try localItem(named: "b.png")
        #expect(HistoryPreview.startURL(selected: [second], visible: [first, second])?.lastPathComponent == "b.png")
        #expect(HistoryPreview.startURL(selected: [], visible: [first, second])?.lastPathComponent == "a.png")
    }

    @Test func cachesRemoteItemsUnderAStableName() {
        let item = HistoryItem(fileUrl: "https://example.com/shot.png")
        let first = HistoryPreview.cachedRemoteURL(for: item)
        #expect(first == HistoryPreview.cachedRemoteURL(for: item))
        #expect(first?.lastPathComponent.hasSuffix("-shot.png") == true)
        #expect(HistoryPreview.cachedRemoteURL(for: HistoryItem(fileUrl: "file:///tmp/x.png")) == nil)
    }
}
