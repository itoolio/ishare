import Foundation
import ishareCore
import Testing
@testable import ishare

struct LocalDestinationDecodingTests {
    @Test func decodesFolderUploaders() throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/folder.iscu"))
        #expect(uploader.kind == .folder)
        #expect(uploader.folder?.subfolderTemplate == "{{date}}")
        #expect(uploader.folder?.publicURL == "https://example.com/screenshots/{{path}}")
        #expect(uploader.folder?.folderURL?.path.hasSuffix("/Sites/screenshots") == true)
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }

    @Test func infersLocalKindsFromTheirBlocks() throws {
        let folder = try CustomUploader.fromJSON(Data(#"{"name": "f", "FOLDER": {"Path": "/tmp/shots"}}"#.utf8))
        #expect(folder.kind == .folder)
        let photos = try CustomUploader.fromJSON(Data(#"{"name": "p", "photos": {}}"#.utf8))
        #expect(photos.kind == .photos)
        #expect(photos.photos?.target == .named("ishare"))
    }

    @Test func decodesPhotosUploaders() throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/photos.iscu"))
        #expect(uploader.kind == .photos)
        #expect(uploader.photos?.albumName == "ishare")
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }

    @Test func roundTripsLocalDestinations() throws {
        let folder = CustomUploader.folder(name: "f", destination: FolderDestination(path: "/tmp/x", subfolderTemplate: "{{year}}", publicURL: "https://e.com/{{filename}}"))
        #expect(try CustomUploader.fromJSON(folder.toJSON()).folder == folder.folder)
        let photos = CustomUploader.photos(name: "p", destination: PhotosDestination(albumName: "", albumIdentifier: nil))
        let decoded = try CustomUploader.fromJSON(photos.toJSON())
        #expect(decoded.kind == .photos)
        #expect(decoded.photos?.target == .library)
    }

    @Test func mapsPhotosDestinationsToAlbumTargets() {
        #expect(PhotosDestination().target == .named("ishare"))
        #expect(PhotosDestination(albumName: " ").target == .library)
        #expect(PhotosDestination(albumName: "Trips", albumIdentifier: "ABC/L0/040").target == .existing(identifier: "ABC/L0/040", fallbackName: "Trips"))
        #expect(PhotosAlbumTarget.library.needsFullAccess == false)
        #expect(PhotosAlbumTarget.named("x").needsFullAccess)
    }

    @Test func validatesFolderUploaders() {
        #expect(UploaderValidator.issues(for: .folder(name: "f", destination: FolderDestination(path: " "))) == [.missingFolder])
        let badURL = CustomUploader.folder(name: "f", destination: FolderDestination(path: "/tmp", publicURL: "example.com/{{filename}}"))
        #expect(UploaderValidator.issues(for: badURL) == [.invalidFolderPublicURL])
        let badTemplate = CustomUploader.folder(name: "f", destination: FolderDestination(path: "/tmp", subfolderTemplate: "{{date"))
        #expect(UploaderValidator.issues(for: badTemplate) == [.malformedTemplate(field: "subfolder")])
        let noFolder = CustomUploader(name: "f", requestURL: "", headers: nil, formData: nil, fileFormName: nil, responseURL: "", uploaderType: .folder)
        #expect(UploaderValidator.issues(for: noFolder) == [.missingFolder])
    }

    @MainActor @Test func resolvesLocalUploaderTypes() {
        #expect(UploadTarget.custom(.folder(name: "f", destination: FolderDestination(path: "/tmp"))).uploader is FolderUploader)
        #expect(UploadTarget.custom(.photos(name: "p", destination: PhotosDestination())).uploader is PhotosUploader)
    }
}

struct FolderPathTests {
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func rendersSubfolderTemplates() throws {
        #expect(try FolderPaths.subfolder("{{date}}", fileName: "a.png", date: date) == "2023/11/14")
        #expect(try FolderPaths.subfolder("shots/{{year}}-{{month}}", fileName: "a.png", date: date) == "shots/2023-11")
        #expect(try FolderPaths.subfolder(nil, fileName: "a.png", date: date) == "")
        #expect(try FolderPaths.subfolder("  ", fileName: "a.png", date: date) == "")
    }

    @Test func dropsPathTraversal() {
        #expect(FolderPaths.sanitized("../../etc/./x//y/..") == "etc/x/y")
    }

    @Test func picksUniqueNames() {
        let directory = URL(fileURLWithPath: "/tmp/d", isDirectory: true)
        let taken: Set<String> = ["/tmp/d/a.png", "/tmp/d/a 2.png"]
        #expect(FolderPaths.uniqueURL(for: "a.png", in: directory) { taken.contains($0.path) }.lastPathComponent == "a 3.png")
        #expect(FolderPaths.uniqueURL(for: "b.png", in: directory) { taken.contains($0.path) }.lastPathComponent == "b.png")
        #expect(FolderPaths.uniqueURL(for: "README", in: directory) { $0.lastPathComponent == "README" }.lastPathComponent == "README 2")
    }

    @Test func rendersPublicURLs() throws {
        let file = URL(fileURLWithPath: "/tmp/d/2023/11/14/my shot.png")
        let destination = FolderDestination(path: "/tmp/d", publicURL: "https://cdn.example.com/{{path}}?name={{filename}}&dir={{subfolder}}")
        let url = try FolderPaths.resultURL(for: destination, fileURL: file, relativePath: "2023/11/14/my shot.png")
        #expect(url?.absoluteString == "https://cdn.example.com/2023/11/14/my%20shot.png?name=my%20shot.png&dir=2023/11/14")
        #expect(try FolderPaths.resultURL(for: FolderDestination(path: "/tmp/d"), fileURL: file, relativePath: "x") == file)
    }
}

@MainActor
struct FolderUploaderTests {
    func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ishare-folder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func copiesIntoTheSubfolderAndReturnsTheFileURL() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Fixtures.temporaryFile(named: "Shot.PNG", contents: TestUploaders.png)
        let destination = FolderDestination(path: root.path, subfolderTemplate: "{{date}}")
        let uploader = FolderUploader(uploader: .folder(name: "Folder", destination: destination), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let first = try await uploader.upload(fileURL: source) { _ in }
        let second = try await uploader.upload(fileURL: source) { _ in }
        #expect(first.localIdentifier == "2023/11/14/Shot.png")
        #expect(second.localIdentifier == "2023/11/14/Shot 2.png")
        #expect(first.url.isFileURL)
        #expect(first.url.standardizedFileURL.path == root.appending(path: "2023/11/14/Shot.png").standardizedFileURL.path)
        #expect(try Data(contentsOf: first.url) == TestUploaders.png)
        #expect(first.isShareable)
        #expect(first.canBeShortened == false)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func returnsThePublicURLWhenConfigured() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Fixtures.temporaryFile(named: "a b.png", contents: TestUploaders.png)
        let destination = FolderDestination(path: root.path, publicURL: "https://sync.example.com/{{filename}}")
        let outcome = try await FolderUploader(uploader: .folder(name: "Synced", destination: destination)).upload(fileURL: source) { _ in }
        #expect(outcome.url.absoluteString == "https://sync.example.com/a%20b.png")
        #expect(outcome.canBeShortened)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "a b.png").path))
    }

    @Test func deletesTheCopy() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Fixtures.temporaryFile(named: "gone.png", contents: TestUploaders.png)
        var uploader = FolderUploader(uploader: .folder(name: "Folder", destination: FolderDestination(path: root.path)))
        uploader.movesDeletedFilesToTrash = false
        let outcome = try await uploader.upload(fileURL: source) { _ in }
        let item = HistoryItem(fileUrl: outcome.url.absoluteString, uploaderId: uploader.uploader.id, localIdentifier: outcome.localIdentifier)
        #expect(item.canDeleteFromServer)
        try await uploader.delete(item)
        #expect(!FileManager.default.fileExists(atPath: outcome.url.path))
        try await uploader.delete(HistoryItem(localIdentifier: "../../\(source.lastPathComponent)"))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func rejectsInvalidSpecifications() async throws {
        let source = try Fixtures.temporaryFile(named: "x.png", contents: TestUploaders.png)
        let uploader = FolderUploader(uploader: .folder(name: "Folder", destination: FolderDestination(path: "")))
        await #expect(throws: UploadFailure.invalidSpecification([.missingFolder])) {
            try await uploader.upload(fileURL: source) { _ in }
        }
    }

    @Test func storesBookmarksPerUploader() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        defer { LocalFolderAccess.setBookmark(nil, for: id) }
        let uploader = CustomUploader.folder(id: id, name: "Folder", destination: FolderDestination(path: "/nonexistent"))
        LocalFolderAccess.setBookmark(LocalFolderAccess.makeBookmark(for: root), for: id)
        #expect(LocalFolderAccess.hasBookmark(for: id))
        #expect(try LocalFolderAccess.folderURL(for: uploader).standardizedFileURL.path == root.standardizedFileURL.path)
        LocalFolderAccess.setBookmark(nil, for: id)
        #expect(try LocalFolderAccess.folderURL(for: uploader).path == "/nonexistent")
    }
}

@MainActor
final class FakePhotoLibrary: PhotoLibraryClient {
    var grantsAccess = true
    var saved: [(URL, PhotosMediaKind, PhotosAlbumTarget)] = []
    var deleted: [String] = []
    var accessRequests: [Bool] = []

    func requestAccess(full: Bool) async -> Bool {
        accessRequests.append(full)
        return grantsAccess
    }

    func save(fileURL: URL, kind: PhotosMediaKind, to album: PhotosAlbumTarget) async throws -> String {
        saved.append((fileURL, kind, album))
        return "ASSET-\(saved.count)/L0/001"
    }

    func deleteAsset(identifier: String) async throws {
        deleted.append(identifier)
    }

    func albums() -> [PhotosAlbum] {
        []
    }
}

@MainActor
struct PhotosUploaderTests {
    let library = FakePhotoLibrary()

    @Test func savesImagesToTheAlbumWithoutALink() async throws {
        let source = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
        let uploader = PhotosUploader(uploader: .photos(name: "Photos", destination: PhotosDestination()), library: library)
        let outcome = try await uploader.upload(fileURL: source) { _ in }
        #expect(outcome.localIdentifier == "ASSET-1/L0/001")
        #expect(outcome.isShareable == false)
        #expect(outcome.deliveredURL == nil)
        #expect(outcome.historyURL == nil)
        #expect(library.saved.first?.2 == .named("ishare"))
        #expect(library.accessRequests == [true])
    }

    @Test func savesVideosToTheLibraryWithAddOnlyAccess() async throws {
        let source = try Fixtures.temporaryFile(named: "clip.mov", contents: Data([0, 1, 2]))
        let uploader = PhotosUploader(uploader: .photos(name: "Photos", destination: PhotosDestination(albumName: "")), library: library)
        _ = try await uploader.upload(fileURL: source) { _ in }
        #expect(library.saved.first?.1 == .video)
        #expect(library.saved.first?.2 == .library)
        #expect(library.accessRequests == [false])
    }

    @Test func rejectsFilesPhotosCannotHold() async throws {
        let source = try Fixtures.temporaryFile(named: "notes.txt", contents: Data("hi".utf8))
        let uploader = PhotosUploader(uploader: .photos(name: "Photos", destination: PhotosDestination()), library: library)
        await #expect(throws: UploadFailure.unsupportedFile(destination: "Photos", fileExtension: "txt")) {
            try await uploader.upload(fileURL: source) { _ in }
        }
        #expect(library.saved.isEmpty)
    }

    @Test func reportsMissingAccess() async throws {
        library.grantsAccess = false
        let source = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
        let uploader = PhotosUploader(uploader: .photos(name: "Photos", destination: PhotosDestination()), library: library)
        await #expect(throws: LocalDestinationError.photosAccessDenied) {
            try await uploader.upload(fileURL: source) { _ in }
        }
    }

    @Test func deletesTheAssetFromTheHistoryIdentifier() async throws {
        let uploader = PhotosUploader(uploader: .photos(name: "Photos", destination: PhotosDestination()), library: library)
        try await uploader.delete(HistoryItem(localIdentifier: "ASSET-9"))
        try await uploader.delete(HistoryItem())
        #expect(library.deleted == ["ASSET-9"])
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct LocalDestinationPipelineTests {
        let spy = UploadEnvironmentSpy()

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"url": "https://cdn.example.com/a.png"}"#.utf8)) }
            UploadCoordinator.environment = spy
        }

        @Test func recordsLocalIdentifiersAndDeliversTheFirstLink() async throws {
            defer { UploadCoordinator.environment = LiveUploadEnvironment() }
            let previous = PhotoLibrary.client
            let library = FakePhotoLibrary()
            PhotoLibrary.client = library
            defer { PhotoLibrary.client = previous }
            let root = FileManager.default.temporaryDirectory.appending(path: "ishare-pipeline-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let file = try Fixtures.temporaryFile(named: "p.png", contents: TestUploaders.png)
            let targets: [UploadTarget] = [
                .custom(.photos(name: "Photos", destination: PhotosDestination())),
                .custom(.folder(name: "Folder", destination: FolderDestination(path: root.path))),
                .custom(TestUploaders.http(name: "web", host: "web.example.com")),
            ]
            let results = await UploadCoordinator.upload(
                fileURL: file, primary: targets[0], additional: Array(targets.dropFirst()), shortener: .none, localFileURL: file
            )
            #expect(try results.get().localIdentifier == "ASSET-1/L0/001")
            #expect(spy.history.count == 3)
            #expect(spy.history[0].fileUrl == nil)
            #expect(spy.history[0].localIdentifier == "ASSET-1/L0/001")
            #expect(spy.history[0].canDeleteFromServer)
            #expect(spy.history[1].localIdentifier == "p.png")
            #expect(spy.history[1].fileUrl?.hasPrefix("file://") == true)
            #expect(spy.delivered.count == 1)
            #expect(spy.delivered.first?.isFileURL == true)
        }
    }
}
