import AppKit
import Foundation
import Testing
@testable import ishare

struct WidgetSnapshotTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func encodesCompactJSONThatRoundTrips() throws {
        let snapshot = WidgetSnapshot(items: [
            .init(id: "a1", url: URL(string: "https://img.example.com/a.png"), name: "a.png", date: date, thumbnail: "a1.jpg", isVideo: false),
            .init(id: "b2", url: URL(string: "https://img.example.com/b.mp4"), name: "b.mp4", date: nil, thumbnail: nil, isVideo: true),
        ])
        let data = try snapshot.encoded()
        let json = String(decoding: data, as: UTF8.self)
        #expect(
            json
                == #"{"items":[{"d":1800000000,"id":"a1","n":"a.png","t":"a1.jpg","u":"https://img.example.com/a.png"},{"id":"b2","n":"b.mp4","u":"https://img.example.com/b.mp4","v":true}],"version":1}"#
        )
        #expect(try WidgetSnapshot.decode(data) == snapshot)
    }

    @Test func decodesSnapshotsWithMissingOptionalFields() throws {
        let decoded = try WidgetSnapshot.decode(Data(#"{"version":1,"items":[{"id":"x"}]}"#.utf8))
        #expect(decoded.items == [.init(id: "x", url: nil, name: "", date: nil, thumbnail: nil, isVideo: false)])
    }

    @Test func keepsTheNewestUploadsAndSkipsUnusableItems() {
        var history = (0 ..< 9).map { index in
            HistoryItem(fileUrl: "https://img.example.com/\(index).png", localPath: "/tmp/\(index).png", date: date.addingTimeInterval(TimeInterval(-index)))
        }
        history.insert(HistoryItem(fileUrl: nil, localPath: nil, date: date), at: 1)
        history.insert(HistoryItem(fileUrl: "https://img.example.com/clip.mp4", date: date), at: 0)
        let snapshot = WidgetSnapshotWriter.snapshot(from: history) { $0.fileUrl?.hasSuffix("0.png") == true }
        #expect(snapshot.items.count == WidgetSnapshot.maximumItems)
        #expect(snapshot.items.first?.isVideo == true)
        #expect(snapshot.items.first?.thumbnail == nil)
        #expect(snapshot.items[1].url?.absoluteString == "https://img.example.com/0.png")
        #expect(snapshot.items[1].thumbnail == "\(snapshot.items[1].id).jpg")
        #expect(snapshot.items.map(\.name) == ["clip.mp4", "0.png", "1.png", "2.png", "3.png", "4.png"])
        #expect(Set(snapshot.items.map(\.id)).count == snapshot.items.count)
    }

    @Test func fallsBackToTheLocalFileForLocalOnlyItems() {
        let snapshot = WidgetSnapshotWriter.snapshot(from: [HistoryItem(fileUrl: nil, localPath: "/tmp/only-local.png", date: date)]) { _ in false }
        #expect(snapshot.items.first?.url == URL(fileURLWithPath: "/tmp/only-local.png"))
    }

    @Test func writesTheSnapshotAndThumbnailsAndRemovesStaleOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)", directoryHint: .isDirectory)
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 800, height: 500), hue: 0.4, title: "Widget"))
        let source = directory.appending(path: "capture.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ImageEncoder.write(image, as: .PNG, to: source)
        let thumbnails = directory.appending(path: WidgetSnapshot.thumbnailFolder)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: thumbnails.appending(path: "stale.jpg"))

        let item = HistoryItem(fileUrl: "https://img.example.com/capture.png", localPath: source.path, date: date)
        let snapshot = try WidgetSnapshotWriter.write(history: [item], to: directory)
        let thumbnailName = try #require(snapshot.items.first?.thumbnail)
        let thumbnail = try #require(NSImage(contentsOf: thumbnails.appending(path: thumbnailName)))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= CGFloat(WidgetSnapshotWriter.thumbnailPixelSize))
        #expect(!FileManager.default.fileExists(atPath: thumbnails.appending(path: "stale.jpg").path))
        let stored = try WidgetSnapshot.decode(Data(contentsOf: directory.appending(path: WidgetSnapshot.fileName)))
        #expect(stored == snapshot)
    }
}
