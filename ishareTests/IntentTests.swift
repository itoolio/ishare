import AppIntents
import Defaults
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ishare

@MainActor
@Suite(.serialized)
struct IntentTests {
    let uploader = CustomUploader(
        name: "intent test", requestURL: "https://upload.example.com/api", headers: nil, formData: nil,
        fileFormName: "file", responseURL: "{{url}}"
    )

    func withUploaders<T>(_ body: () async throws -> T) async rethrows -> T {
        let saved = Defaults[.savedCustomUploaders]
        let active = Defaults[.activeCustomUploader]
        let type = Defaults[.uploadType]
        let destination = Defaults[.uploadDestination]
        let history = Defaults[.uploadHistory]
        defer {
            Defaults[.savedCustomUploaders] = saved
            Defaults[.activeCustomUploader] = active
            Defaults[.uploadType] = type
            Defaults[.uploadDestination] = destination
            Defaults[.uploadHistory] = history
        }
        Defaults[.savedCustomUploaders] = [uploader]
        return try await body()
    }

    @Test func listsImgurAndSavedUploadersAsEntities() async throws {
        try await withUploaders {
            let entities = try await UploaderQuery().suggestedEntities()
            #expect(entities.map(\.name) == ["Imgur", "intent test"])
            let matches = try await UploaderQuery().entities(matching: "INTENT")
            #expect(matches.map(\.id) == [uploader.id.uuidString])
            let lookup = try await UploaderQuery().entities(for: [UploaderEntity.imgurID])
            #expect(lookup == [.imgur])
        }
    }

    @Test func switchesTheActiveUploader() async throws {
        try await withUploaders {
            let intent = SetUploaderIntent()
            intent.uploader = UploaderEntity(uploader)
            _ = try await intent.perform()
            #expect(Defaults[.uploadType] == .CUSTOM)
            #expect(Defaults[.activeCustomUploader] == uploader.id)
            intent.uploader = .imgur
            _ = try await intent.perform()
            #expect(Defaults[.uploadType] == .IMGUR)
            #expect(Defaults[.activeCustomUploader] == nil)
        }
    }

    @Test func rejectsUnknownUploaders() async throws {
        await withUploaders {
            let intent = SetUploaderIntent()
            intent.uploader = UploaderEntity(id: UUID().uuidString, name: "gone", kind: "Custom")
            await #expect(throws: IntentError.self) {
                _ = try await intent.perform()
            }
        }
    }

    @Test func uploadsFilesThroughTheChosenUploader() async throws {
        UploadService.session = StubURLProtocol.makeSession()
        StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"url": "https://cdn.example.com/intent.png"}"#.utf8)) }
        try await withUploaders {
            let intent = UploadFileIntent()
            intent.file = IntentFile(data: Data([0x89, 0x50, 0x4E, 0x47]), filename: "shot.png", type: .png)
            intent.uploader = UploaderEntity(uploader)
            _ = try await intent.perform()
            #expect(StubURLProtocol.lastRequest?.url.absoluteString == "https://upload.example.com/api")
            #expect(Defaults[.uploadHistory].first?.fileUrl == "https://cdn.example.com/intent.png")
        }
    }

    @Test func stagesIntentFilesWithTheirExtension() throws {
        let staged = try IntentFileStaging.stage(IntentFile(data: Data("gif".utf8), filename: "clip", type: .gif))
        #expect(staged.pathExtension == "gif")
        #expect(try Data(contentsOf: staged) == Data("gif".utf8))
    }

    @Test func mapsCaptureKinds() {
        #expect(CaptureKindEnum.allCases.map(\.captureType) == [.REGION, .WINDOW, .SCREEN, .SCROLLING])
    }
}
