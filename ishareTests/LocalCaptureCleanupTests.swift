import Foundation
import Testing
@testable import ishare

struct LocalCaptureCleanupTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func makeFile(_ name: String, in directory: URL? = nil, capturedDaysAgo days: Double, modifiedDaysAgo: Double? = nil) throws -> URL {
        let folder = directory ?? root
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data("x".utf8).write(to: url)
        let modified = now.addingTimeInterval(-(modifiedDaysAgo ?? days) * 86400)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    func captureName(prefix: String = "ishare", daysAgo: Double, suffix: String? = nil, ext: String = "png") -> String {
        CaptureFileName.make(prefix: prefix, suffix: suffix, ext: ext, date: now.addingTimeInterval(-daysAgo * 86400))
    }

    func plan(prefixes: [String] = ["ishare"], days: Double = 30, protected: Set<String> = [], directories: [URL]? = nil) -> LocalCaptureCleanupPlan {
        LocalCaptureCleanupPlan(directories: directories ?? [root], prefixes: prefixes, cutoff: now.addingTimeInterval(-days * 86400), protectedPaths: protected)
    }

    func names(_ urls: [URL]) -> Set<String> {
        Set(urls.map(\.lastPathComponent))
    }

    @Test func readsTheCaptureDateFromIshareFileNames() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(LocalCaptureCleanup.captureDate(ofFileNamed: "ishare-1700000000.png", prefixes: ["ishare"]) == date)
        #expect(LocalCaptureCleanup.captureDate(ofFileNamed: "ishare-1700000000-window.jpg", prefixes: ["ishare"]) == date)
        #expect(LocalCaptureCleanup.captureDate(ofFileNamed: "my-shots-1700000000.mp4", prefixes: ["My Shots"]) == nil)
        #expect(LocalCaptureCleanup.captureDate(ofFileNamed: "my shots-1700000000.mp4", prefixes: ["My Shots"]) == date)
        #expect(LocalCaptureCleanup.captureDate(ofFileNamed: "ishare-1700000000.png", prefixes: [""]) == date)
    }

    @Test(arguments: [
        "ishare-1700000000.txt", "ishare-1700000000.PNG", "ishare-17.png", "ishare-1700000000x.png", "ishare1700000000.png",
        "Screenshot 2026-10-23 at 10.00.00.png", "ishare-.png", "notes-1700000000.png", "ishare-170000000000000.png",
    ])
    func ignoresNamesIshareDidNotCreate(name: String) {
        #expect(LocalCaptureCleanup.captureDate(ofFileNamed: name, prefixes: ["ishare"]) == nil)
    }

    @Test func selectsOnlyOldIshareCaptures() throws {
        try makeFile(captureName(daysAgo: 40), capturedDaysAgo: 40)
        try makeFile(captureName(daysAgo: 45, suffix: "region", ext: "mp4"), capturedDaysAgo: 45)
        try makeFile(captureName(daysAgo: 5), capturedDaysAgo: 5)
        try makeFile("vacation.png", capturedDaysAgo: 400)
        try makeFile("Screenshot 2020-01-01 at 10.00.00.png", capturedDaysAgo: 400)
        try makeFile(captureName(daysAgo: 60, ext: "txt"), capturedDaysAgo: 60)
        try makeFile(captureName(daysAgo: 60), in: root.appending(path: "nested"), capturedDaysAgo: 60)
        let selected = LocalCaptureCleanup.candidates(for: plan())
        #expect(names(selected) == [captureName(daysAgo: 40), captureName(daysAgo: 45, suffix: "region", ext: "mp4")])
    }

    @Test func keepsRecentlyModifiedFilesEvenWithAnOldName() throws {
        try makeFile(captureName(daysAgo: 90), capturedDaysAgo: 90, modifiedDaysAgo: 1)
        #expect(LocalCaptureCleanup.candidates(for: plan()).isEmpty)
    }

    @Test func keepsUploadedFilesWhenAsked() throws {
        let uploaded = try makeFile(captureName(daysAgo: 50), capturedDaysAgo: 50)
        let localOnly = try makeFile(captureName(daysAgo: 51), capturedDaysAgo: 51)
        let neverUploaded = try makeFile(captureName(daysAgo: 52), capturedDaysAgo: 52)
        let history = [
            HistoryItem(fileUrl: "https://example.com/a.png", localPath: uploaded.path),
            HistoryItem(fileUrl: nil, localPath: localOnly.path),
        ]
        let protected = LocalCaptureCleanup.protectedPaths(in: history)
        let selected = LocalCaptureCleanup.candidates(for: plan(protected: protected))
        #expect(names(selected) == [localOnly.lastPathComponent, neverUploaded.lastPathComponent])
        #expect(LocalCaptureCleanup.candidates(for: plan()).count == 3)
    }

    @Test func usesEveryConfiguredPrefixAndDeduplicatesSharedFolders() throws {
        try makeFile(captureName(prefix: "shot", daysAgo: 40), capturedDaysAgo: 40)
        try makeFile(captureName(prefix: "clip", daysAgo: 40, ext: "mov"), capturedDaysAgo: 40)
        try makeFile(captureName(prefix: "other", daysAgo: 40), capturedDaysAgo: 40)
        let selected = LocalCaptureCleanup.candidates(for: plan(prefixes: ["Shot", "clip"], directories: [root, root]))
        #expect(selected.count == 2)
        #expect(names(selected) == [captureName(prefix: "shot", daysAgo: 40), captureName(prefix: "clip", daysAgo: 40, ext: "mov")])
    }

    @Test func ignoresDirectoriesAndSymlinksThatLookLikeCaptures() throws {
        let target = try makeFile("vacation.png", in: root.appending(path: "elsewhere"), capturedDaysAgo: 400)
        try FileManager.default.createSymbolicLink(at: root.appending(path: captureName(daysAgo: 70)), withDestinationURL: target)
        try FileManager.default.createDirectory(at: root.appending(path: captureName(daysAgo: 71)), withIntermediateDirectories: true)
        #expect(LocalCaptureCleanup.candidates(for: plan()).isEmpty)
    }

    @Test func movesSelectedFilesToTheTrash() throws {
        let old = try makeFile(captureName(daysAgo: 40), capturedDaysAgo: 40)
        let keep = try makeFile("keep.png", capturedDaysAgo: 400)
        let moved = LocalCaptureCleanup.moveToTrash(LocalCaptureCleanup.candidates(for: plan()))
        #expect(moved == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
    }
}
