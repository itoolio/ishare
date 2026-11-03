import CoreGraphics
import Foundation
import ishareCore
import Testing
@testable import ishare

@MainActor
@Suite(.serialized)
struct WatchFolderChainRunnerTests {
    private func makeImage(at url: URL) throws {
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        try ImageEncoder.write(try #require(context.makeImage()), as: .PNG, to: url)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "watch-chain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func renamesConvertsAndMovesTheOriginal() async throws {
        let watched = try directory()
        let archive = try directory()
        defer {
            try? FileManager.default.removeItem(at: watched)
            try? FileManager.default.removeItem(at: archive)
        }
        let original = watched.appending(path: "Shot.png")
        try makeImage(at: original)
        var marked: [URL] = []
        let chain = [
            WatchFolderAction(kind: .rename, template: "renamed-{{name}}"), WatchFolderAction(kind: .convert, format: "jpg"),
            WatchFolderAction(kind: .moveToFolder, folderPath: archive.path),
        ]
        let outcome = await WatchFolderChainRunner.run(chain, on: original) { marked.append($0) }
        #expect(outcome.failure == nil)
        #expect(outcome.finalURL?.lastPathComponent == "renamed-Shot.png")
        #expect(outcome.finalURL?.deletingLastPathComponent().standardizedFileURL == archive.standardizedFileURL)
        #expect(marked.map(\.lastPathComponent) == ["renamed-Shot.png"])
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    @Test func stopsAtTheFirstFailingStep() async throws {
        let watched = try directory()
        defer { try? FileManager.default.removeItem(at: watched) }
        let original = watched.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: original)
        let outcome = await WatchFolderChainRunner.run(
            [WatchFolderAction(kind: .convert, format: "png"), WatchFolderAction(kind: .moveToTrash)], on: original)
        #expect(outcome.failure != nil)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func numbersFilesThatWouldCollide() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: "a.png"))
        #expect(WatchFolderChainRunner.uniqueURL(in: folder, named: "a.png").lastPathComponent == "a-2.png")
        #expect(WatchFolderChainRunner.uniqueURL(in: folder, named: "b.png").lastPathComponent == "b.png")
    }
}
