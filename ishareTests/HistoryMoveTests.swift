import Foundation
import Testing
@testable import ishare

struct HistoryMoveTests {
    let old = HistoryItem(
        fileUrl: "https://old.example/a.png", deletionUrl: "https://old.example/delete/a", localPath: "/tmp/a.png", date: Date(timeIntervalSince1970: 100),
        altText: "A cat", title: "Cat", keepForever: true)

    @Test func replacesTheOldEntryInPlaceAndKeepsItsDetails() throws {
        let newer = HistoryItem(fileUrl: "https://new.example/a.png", date: Date(timeIntervalSince1970: 500))
        let other = HistoryItem(fileUrl: "https://old.example/b.png", date: Date(timeIntervalSince1970: 50))
        let updated = try #require(HistoryMove.replacing(old, withUploadAt: "https://new.example/a.png", in: [newer, old, other]))
        #expect(updated.map(\.fileUrl) == ["https://new.example/a.png", "https://old.example/b.png"])
        #expect(updated[0].date == Date(timeIntervalSince1970: 100))
        #expect(updated[0].title == "Cat")
        #expect(updated[0].altText == "A cat")
        #expect(updated[0].keepForever == true)
        #expect(updated[0].localPath == "/tmp/a.png")
    }

    @Test func leavesHistoryAloneWhenTheNewUploadIsMissing() {
        #expect(HistoryMove.replacing(old, withUploadAt: "https://new.example/a.png", in: [old]) == nil)
        #expect(HistoryMove.replacing(old, withUploadAt: nil, in: [old]) == nil)
    }

    @Test func skipsItemsAlreadyOnTheTargetOrWithoutAFile() {
        let id = UUID()
        let onTarget = HistoryItem(fileUrl: "https://x/a.png", uploaderId: id)
        let noFile = HistoryItem(localPath: "/nonexistent/file.png")
        let movable = HistoryItem(fileUrl: "https://x/b.png")
        #expect(HistoryMove.movable([onTarget, noFile, movable], to: .custom(id)) == [movable])
    }
}
