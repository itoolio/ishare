import Foundation
import ishareCore
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

@MainActor
struct ViewCountHistoryTests {
    @Test func storesTheViewCountLinkFromTheUploadResponse() throws {
        let uploader = CustomUploader(
            name: "zipline", requestURL: "https://z.example/api/upload", headers: nil, formData: nil, fileFormName: "file",
            responseURL: "{{files[0].url}}")
        var withViews = uploader
        withViews.viewCount = ViewCountSpec(url: "https://z.example/api/user/files/{{files[0].id}}", path: "views")
        let response = Data(#"{"files": [{"id": "abc", "url": "https://z.example/u/abc.png"}]}"#.utf8)
        let outcome = try HTTPUploader.outcome(from: response, uploader: withViews)
        #expect(outcome.viewCountURL == "https://z.example/api/user/files/abc")
        #expect(try HTTPUploader.outcome(from: response, uploader: uploader).viewCountURL == nil)
        let item = UploadCoordinator.historyItem(for: outcome, target: .custom(withViews), localFileURL: nil, now: Date())
        #expect(item.viewCountUrl == "https://z.example/api/user/files/abc")
    }
}

struct ScriptHookRunnerTests {
    @Test func passesTheEventFileAndLinkToTheScript() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hook-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appending(path: "out.txt")
        let script = folder.appending(path: "hook.sh")
        try "echo \"$1 $2 $3 $ISHARE_LINK\" > '\(output.path)'\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        let status = await ScriptHooks.run(script: script.path, event: .upload, file: "/tmp/a.png", link: "https://x/a.png")
        #expect(status == 3)
        #expect(try String(contentsOf: output, encoding: .utf8) == "upload /tmp/a.png https://x/a.png https://x/a.png\n")
    }
}

@MainActor
struct ImageOperationsTests {
    @Test func trimsIntoANewFileNextToTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ops-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "shot.png")
        try ImageEncoder.write(TestImages.solid(width: 40, height: 30, color: CaptureColor(red: 1, green: 1, blue: 1)), as: .PNG, to: input)
        let output = try await ImageOperations.apply(.trim, to: input)
        #expect(output == folder.appending(path: "shot-trimmed.png"))
        #expect(FileManager.default.fileExists(atPath: output.path))
        let again = try await ImageOperations.apply(.trim, to: input)
        #expect(again.lastPathComponent == "shot-trimmed-2.png")
    }

    @Test func mapsScriptingCodes() {
        #expect(ScriptingCodes.imageOperation(ScriptingCodes.fourCharCode("eFrm")) == .frame)
        #expect(ScriptingCodes.imageOperation(nil) == nil)
        #expect(ScriptingCodes.deviceFrame(nil) == .laptop)
        #expect(ScriptingCodes.deviceFrame(ScriptingCodes.fourCharCode("dPho")) == .phone)
    }
}
