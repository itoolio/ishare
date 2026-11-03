import Foundation
import Testing
@testable import ishareCore

struct WatchFolderChainTests {
    @Test func acceptsATypicalChain() {
        let chain = [
            WatchFolderAction(kind: .rename), WatchFolderAction(kind: .optimize), WatchFolderAction(kind: .upload), WatchFolderAction(kind: .copyLink),
            WatchFolderAction(kind: .moveToTrash),
        ]
        #expect(WatchFolderChain.issues(in: chain).isEmpty)
    }

    @Test func reportsMisorderedOrIncompleteSteps() {
        #expect(WatchFolderChain.issues(in: []) == [.empty])
        #expect(WatchFolderChain.issues(in: [WatchFolderAction(kind: .copyLink), WatchFolderAction(kind: .upload)]) == [.copyLinkBeforeUpload])
        #expect(WatchFolderChain.issues(in: [WatchFolderAction(kind: .moveToTrash), WatchFolderAction(kind: .upload)]) == [.stepAfterMove])
        #expect(WatchFolderChain.issues(in: [WatchFolderAction(kind: .moveToFolder)]) == [.missingFolder])
        #expect(WatchFolderChain.issues(in: [WatchFolderAction(kind: .rename, template: " ")]) == [.emptyTemplate])
    }

    @Test func fillsRenameTemplates() {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let utc = TimeZone(identifier: "UTC")!
        let original = URL(fileURLWithPath: "/tmp/Screen Shot.png")
        #expect(WatchFolderChain.renamed("{{date}}-{{name}}", original: original, date: date, counter: 3, timeZone: utc) == "2026-10-26-Screen Shot.png")
        #expect(WatchFolderChain.renamed("shot-{{counter}}-{{time}}", original: original, date: date, counter: 7, timeZone: utc) == "shot-7-07-33-20.png")
        #expect(WatchFolderChain.renamed("a/b:c", original: original, date: date, counter: 1, timeZone: utc) == "a-b-c.png")
        #expect(WatchFolderChain.renamed("   ", original: original, date: date, counter: 1, timeZone: utc) == "Screen Shot.png")
    }

    @Test func migratesTheSingleUploadSetting() {
        #expect(WatchFolderChain.migrated(uploadsFiles: true).map(\.kind) == [.upload])
        #expect(WatchFolderChain.migrated(uploadsFiles: false).isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let chain = [WatchFolderAction(kind: .convert, format: "webp"), WatchFolderAction(kind: .upload, uploader: "Stub")]
        let decoded = try JSONDecoder().decode([WatchFolderAction].self, from: try JSONEncoder().encode(chain))
        #expect(decoded == chain)
    }
}
