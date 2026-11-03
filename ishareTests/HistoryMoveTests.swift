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

struct UploadProgressHUDLayoutTests {
    @Test func sitsBelowTheMenuBarIcon() {
        let frame = UploadProgressHUDLayout.frame(
            below: CGRect(x: 1000, y: 1050, width: 30, height: 24), on: CGRect(x: 0, y: 0, width: 1440, height: 1080),
            visible: CGRect(x: 0, y: 0, width: 1440, height: 1050))
        #expect(frame.midX == 1015)
        #expect(frame.maxY == 1050 - UploadProgressHUDLayout.gap)
    }

    @Test func staysOnScreenAndFallsBackToTheTopCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 1080)
        let edge = UploadProgressHUDLayout.frame(below: CGRect(x: 1430, y: 1050, width: 10, height: 24), on: screen, visible: screen)
        #expect(edge.maxX <= screen.maxX)
        let centered = UploadProgressHUDLayout.frame(below: nil, on: screen, visible: CGRect(x: 0, y: 0, width: 1440, height: 1040))
        #expect(centered.midX == 720)
        #expect(centered.maxY == 1040 - UploadProgressHUDLayout.gap)
    }
}
