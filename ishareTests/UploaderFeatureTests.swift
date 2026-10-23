import Defaults
import Foundation
import KeyboardShortcuts
import Testing
@testable import ishare

struct S3PresignTests {
    let date = Date(timeIntervalSince1970: 1_369_353_600)

    @Test func matchesTheAWSPresignedURLExample() throws {
        let signer = SigV4Signer(accessKeyId: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1")
        let url = try #require(signer.presignedURL(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!, expires: 86400, date: date))
        #expect(url.absoluteString == "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
    }

    @Test func returnsPresignedObjectURLsInsteadOfThePublicURL() throws {
        let configuration = S3Configuration(
            endpoint: "https://s3.amazonaws.com", region: "us-east-1", bucket: "examplebucket", accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", pathStyle: false, publicURL: "https://cdn.example.com/{{key}}",
            presignedExpiry: 86400
        )
        let request = try S3RequestBuilder.upload(
            configuration: configuration, fileURL: URL(fileURLWithPath: "/tmp/test.txt"), contentType: "text/plain", payloadHash: "x",
            context: S3KeyContext(fileName: "test.txt"), date: date
        )
        #expect(request.publicURL.absoluteString.hasSuffix("X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"))
        #expect(request.publicURL.host() == "examplebucket.s3.amazonaws.com")
    }

    @Test func keepsPublicURLsWithoutExpiry() throws {
        let configuration = S3Configuration(endpoint: "https://s3.amazonaws.com", region: "us-east-1", bucket: "b", accessKeyId: "a", secretAccessKey: "s", publicURL: "https://cdn.example.com/{{key}}")
        let request = try S3RequestBuilder.upload(configuration: configuration, fileURL: URL(fileURLWithPath: "/tmp/k.png"), contentType: "image/png", payloadHash: "x", context: S3KeyContext(fileName: "k.png"))
        #expect(request.publicURL.absoluteString == "https://cdn.example.com/k.png")
    }

    @Test(arguments: [(0, false), (1, true), (604_800, true), (604_801, false), (-5, false)])
    func validatesExpiryRange(pair: (Int, Bool)) {
        let uploader = CustomUploader.s3(name: "s", configuration: S3Configuration(endpoint: "https://s3.example.com", region: "r", bucket: "b", accessKeyId: "a", secretAccessKey: "s", presignedExpiry: pair.0))
        #expect(UploaderValidator.issues(for: uploader).contains(.invalidPresignedExpiry) == !pair.1)
    }

    @Test func roundTripsExpiryThroughJSON() throws {
        let original = CustomUploader.s3(name: "s", configuration: S3Configuration(endpoint: "e", region: "r", bucket: "b", accessKeyId: "a", secretAccessKey: "s", presignedExpiry: 600))
        #expect(try CustomUploader.fromJSON(original.toJSON()).s3?.presignedExpiry == 600)
        let decoded = try CustomUploader.fromJSON(Data(#"{"name": "x", "s3": {"endpoint": "e", "bucket": "b", "accessKeyId": "a", "secretAccessKey": "s", "PresignedExpiry": 60}}"#.utf8))
        #expect(decoded.s3?.presignedExpiry == 60)
    }
}

struct ShareXImportTests {
    static let imgurStyle = """
    {
      "Version": "15.0.0",
      "Name": "Zipline",
      "DestinationType": "ImageUploader, TextUploader, FileUploader",
      "RequestMethod": "POST",
      "RequestURL": "https://zipline.example.com/api/upload",
      "Headers": {
        "Authorization": "secret-token",
        "Format": "random"
      },
      "Body": "MultipartFormData",
      "Arguments": {
        "album": "shots"
      },
      "FileFormName": "file",
      "URL": "{json:files[0]}",
      "DeletionURL": "https://zipline.example.com/api/delete/{json:id}",
      "ErrorMessage": "{json:error}"
    }
    """

    static let legacyBinary = """
    {
      "Name": "Legacy",
      "DestinationType": "ImageUploader",
      "RequestType": "PUT",
      "RequestMethod": "put",
      "RequestURL": "https://legacy.example.com/upload",
      "Parameters": { "key": "abc" },
      "Body": "Binary",
      "URL": "$json:data.link$",
      "DeletionURL": "$json:data.delete$",
    }
    """

    @Test func importsMultipartUploadersWithModernSyntax() throws {
        let uploader = try ShareXImport.uploader(from: Data(Self.imgurStyle.utf8))
        #expect(uploader.name == "Zipline")
        #expect(uploader.requestURL == "https://zipline.example.com/api/upload")
        #expect(uploader.headers == ["Authorization": "secret-token", "Format": "random"])
        #expect(uploader.formData == ["album": "shots"])
        #expect(uploader.fileFormName == "file")
        #expect(uploader.requestBodyType == .multipartFormData)
        #expect(uploader.responseURL == "{{files[0]}}")
        #expect(uploader.deletionURL == "https://zipline.example.com/api/delete/{{id}}")
        #expect(uploader.requestMethod == nil)
        #expect(uploader.isValid())
    }

    @Test func importsBinaryUploadersWithLegacySyntaxAndQueryParameters() throws {
        let uploader = try ShareXImport.uploader(from: Data(Self.legacyBinary.utf8))
        #expect(uploader.requestURL == "https://legacy.example.com/upload?key=abc")
        #expect(uploader.requestBodyType == .binary)
        #expect(uploader.requestMethod == .put)
        #expect(uploader.formData == nil)
        #expect(uploader.fileFormName == nil)
        #expect(uploader.responseURL == "{{data.link}}")
        #expect(uploader.deletionURL == "{{data.delete}}")
    }

    @Test func usesTheResponseBodyWhenNoURLIsGivenAndFallsBackToTheFileName() throws {
        let json = #"{"RequestURL": "https://paste.example.com/", "FileFormName": "f"}"#
        let uploader = try UploaderFile.decode(Data(json.utf8), fileExtension: "SXCU", fallbackName: "my paste")
        #expect(uploader.name == "my paste")
        #expect(uploader.responseURL == "{{response}}")
        #expect(uploader.fileFormName == "f")
    }

    @Test func convertsJSONPathPrefixes() throws {
        #expect(try ShareXImport.convertTemplate("{json:$.data.url}", field: "URL") == "{{data.url}}")
        #expect(try ShareXImport.convertTemplate("https://x/{json:files[0].name}?r={response}", field: "URL") == "https://x/{{files[0].name}}?r={{response}}")
    }

    @Test func rejectsUnsupportedFeatures() {
        #expect(throws: ShareXImportError.unsupportedBody("JSON")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "Body": "JSON"}"#.utf8))
        }
        #expect(throws: ShareXImportError.unsupportedSyntax(field: "URL", token: "{regex:1}")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "URL": "{regex:1}"}"#.utf8))
        }
        #expect(throws: ShareXImportError.unsupportedDestination("URLShortener")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "DestinationType": "URLShortener"}"#.utf8))
        }
        #expect(throws: ShareXImportError.unsupportedMethod("GET")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "RequestMethod": "GET"}"#.utf8))
        }
        #expect(throws: ShareXImportError.missingRequestURL) {
            try ShareXImport.uploader(from: Data(#"{"Name": "x"}"#.utf8))
        }
    }

    @Test func keepsIscuFilesOnTheIshareDecoder() throws {
        let uploader = try UploaderFile.decode(Fixtures.data("examples/zipline.iscu"), fileExtension: "iscu")
        #expect(uploader.name == "zipline")
    }

    @Test func roundTripsRequestMethodAndModificationDate() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TestUploaders.http(name: "m", host: "a.example.com")
        var modified = original
        modified.requestMethod = .patch
        modified.modifiedAt = date
        let decoded = try CustomUploader.fromJSON(modified.toJSON())
        #expect(decoded.requestMethod == .patch)
        #expect(decoded.modifiedAt == date)
        #expect(try CustomUploader.fromJSON(Data(#"{"name":"x","requestURL":"https://a.b","responseURL":"{{u}}","requestMethod":"put"}"#.utf8)).requestMethod == .put)
    }
}

@MainActor
struct S3SecretStoreTests {
    init() {
        TestSecrets.install()
    }

    func s3(secret: String, id: UUID = UUID()) -> CustomUploader {
        .s3(id: id, name: "s3", configuration: S3Configuration(endpoint: "https://s3.example.com", region: "r", bucket: "b", accessKeyId: "a", secretAccessKey: secret))
    }

    @Test func movesSecretsIntoTheStoreIdempotently() throws {
        let uploader = s3(secret: "top-secret")
        let stored = S3SecretStore.movingSecretToKeychain(uploader)
        #expect(stored.s3?.secretAccessKey == S3SecretStore.placeholder)
        #expect(S3SecretStore.secret(for: stored) == "top-secret")
        #expect(S3SecretStore.movingSecretToKeychain(stored).s3 == stored.s3)
        #expect(try S3SecretStore.resolvingSecret(stored).s3?.secretAccessKey == "top-secret")
        #expect(UploaderValidator.issues(for: stored).isEmpty)
    }

    @Test func keepsTheStoredSecretWhenAnImportLeavesItOut() {
        let id = UUID()
        _ = S3SecretStore.movingSecretToKeychain(s3(secret: "kept", id: id))
        let imported = S3SecretStore.movingSecretToKeychain(s3(secret: "", id: id))
        #expect(imported.s3?.secretAccessKey == S3SecretStore.placeholder)
        #expect(S3SecretStore.secret(for: imported) == "kept")
    }

    @Test func exportsSecretsOnlyWhenAskedTo() {
        let stored = S3SecretStore.movingSecretToKeychain(s3(secret: "abc"))
        #expect(S3SecretStore.exporting(stored, includeSecret: false).s3?.secretAccessKey == "")
        #expect(S3SecretStore.exporting(stored, includeSecret: true).s3?.secretAccessKey == "abc")
    }

    @Test func migrationMovesPlaintextSecretsAndBumpsTheVersion() throws {
        let suite = "dev.adrian.ishare.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: Migrations.versionKey)
        let key = Defaults.Key<Set<CustomUploader>?>("savedCustomUploaders", suite: defaults)
        let plain = s3(secret: "migrate-me")
        let http = TestUploaders.http(name: "h", host: "h.example.com")
        Defaults[key] = [plain, http]
        Migrations.run(defaults: defaults)
        let migrated = try #require(Defaults[key]?.first { $0.id == plain.id })
        #expect(migrated.s3?.secretAccessKey == S3SecretStore.placeholder)
        #expect(S3SecretStore.secret(for: migrated) == "migrate-me")
        #expect(defaults.integer(forKey: Migrations.versionKey) == Migrations.currentVersion)
        Migrations.moveS3SecretsToKeychain(defaults: defaults)
        #expect(Defaults[key]?.count == 2)
    }
}

@MainActor
struct SettingsArchiveTests {
    init() {
        TestSecrets.install()
    }

    func shortcutStore(_ storage: Storage) -> ShortcutStore {
        ShortcutStore(
            names: { storage.values.keys.sorted() },
            get: { storage.values[$0] ?? nil },
            set: { storage.values[$1] = $0 }
        )
    }

    final class Storage {
        var values: [String: KeyboardShortcuts.Shortcut?] = [:]
    }

    @Test func exportsAndAppliesPreferencesUploadersShortcutsAndHistory() throws {
        let sourceSuite = "dev.adrian.ishare.tests.\(UUID().uuidString)"
        let targetSuite = "dev.adrian.ishare.tests.\(UUID().uuidString)"
        let source = try #require(UserDefaults(suiteName: sourceSuite))
        let target = try #require(UserDefaults(suiteName: targetSuite))
        defer {
            source.removePersistentDomain(forName: sourceSuite)
            target.removePersistentDomain(forName: targetSuite)
        }
        source.set(false, forKey: "copyToClipboard")
        source.set(7.0, forKey: "toastTimeout")
        source.set("shots", forKey: "captureFileName")
        source.set(["com.apple.Safari"], forKey: "ignoredApps")
        source.set(Data([1, 2]), forKey: "capturePathBookmark")
        source.set("junk", forKey: "unrelatedKey")
        let uploader = S3SecretStore.movingSecretToKeychain(.s3(name: "r2", configuration: S3Configuration(endpoint: "https://r2.example.com", region: "auto", bucket: "b", accessKeyId: "a", secretAccessKey: "secret-r2")))
        Defaults[SettingsTransfer.uploadersKey(in: source)] = [uploader]
        Defaults[SettingsTransfer.historyKey(in: source)] = [HistoryItem(fileUrl: "https://x.example.com/1.png", date: Date(timeIntervalSince1970: 5))]
        let sourceShortcuts = Storage()
        let disabled: KeyboardShortcuts.Shortcut? = nil
        sourceShortcuts.values["captureRegion"] = .some(KeyboardShortcuts.Shortcut(.p, modifiers: [.command]))
        sourceShortcuts.values["recordGif"] = .some(disabled)

        let archive = SettingsTransfer.makeArchive(includeHistory: true, includeSecrets: false, defaults: source, shortcuts: shortcutStore(sourceShortcuts))
        #expect(archive.preferences["copyToClipboard"] == .bool(false))
        #expect(archive.preferences["toastTimeout"] == .double(7))
        #expect(archive.preferences["capturePathBookmark"] == nil)
        #expect(archive.preferences["unrelatedKey"] == nil)
        #expect(archive.uploaders.first?.s3?.secretAccessKey == "")
        #expect(archive.preferences["captureFileName"] == .string("shots"))
        #expect(Set(archive.preferences.keys).isSubset(of: SettingsTransfer.preferenceNames))
        #expect(archive.summary.uploaders == 1)
        #expect(archive.summary.shortcuts == 2)
        #expect(archive.summary.history == 1)
        #expect(!archive.summary.includesSecrets)

        let decoded = try SettingsTransfer.decode(SettingsTransfer.encode(archive))
        #expect(decoded == archive)

        let targetShortcuts = Storage()
        SettingsTransfer.apply(decoded, to: target, shortcuts: shortcutStore(targetShortcuts))
        #expect(target.object(forKey: "copyToClipboard") as? Bool == false)
        #expect(target.double(forKey: "toastTimeout") == 7)
        #expect(target.stringArray(forKey: "ignoredApps") == ["com.apple.Safari"])
        #expect(target.object(forKey: "unrelatedKey") == nil)
        #expect(targetShortcuts.values["captureRegion"] == .some(KeyboardShortcuts.Shortcut(.p, modifiers: [.command])))
        #expect(targetShortcuts.values.keys.contains("recordGif"))
        #expect(targetShortcuts.values["recordGif"] == .some(disabled))
        let applied = try #require(Defaults[SettingsTransfer.uploadersKey(in: target)]?.first)
        #expect(applied.id == uploader.id)
        #expect(S3SecretStore.secret(for: applied) == "secret-r2")
        #expect(Defaults[SettingsTransfer.historyKey(in: target)].map(\.fileUrl) == ["https://x.example.com/1.png"])
    }

    @Test func includesSecretsAndSkipsHistoryWhenAskedTo() throws {
        let suite = "dev.adrian.ishare.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let uploader = S3SecretStore.movingSecretToKeychain(.s3(name: "aws", configuration: S3Configuration(endpoint: "https://s3.example.com", region: "r", bucket: "b", accessKeyId: "a", secretAccessKey: "visible")))
        Defaults[SettingsTransfer.uploadersKey(in: defaults)] = [uploader]
        let archive = SettingsTransfer.makeArchive(includeHistory: false, includeSecrets: true, defaults: defaults, shortcuts: shortcutStore(Storage()))
        #expect(archive.uploaders.first?.s3?.secretAccessKey == "visible")
        #expect(archive.history == nil)
    }

    @Test func rejectsNewerAndMalformedFiles() throws {
        #expect(throws: SettingsArchiveError.unsupportedVersion(99)) {
            try SettingsTransfer.decode(Data(#"{"version": 99, "exportedAt": "2026-01-01T00:00:00Z", "preferences": {}, "uploaders": [], "shortcuts": {}, "includesSecrets": false}"#.utf8))
        }
        #expect(throws: SettingsArchiveError.self) {
            try SettingsTransfer.decode(Data("nope".utf8))
        }
    }

    @Test func convertsPropertyListValues() {
        #expect(ArchiveValue(propertyList: NSNumber(value: true)) == .bool(true))
        #expect(ArchiveValue(propertyList: NSNumber(value: 3)) == .int(3))
        #expect(ArchiveValue(propertyList: NSNumber(value: 2.5)) == .double(2.5))
        #expect(ArchiveValue(propertyList: ["a": [1, "b"]]) == .dictionary(["a": .array([.int(1), .string("b")])]))
    }
}

struct UploaderSyncMergeTests {
    let lastSync = Date(timeIntervalSince1970: 1000)
    let copyID = UUID()

    func uploader(_ name: String, id: UUID = UUID(), host: String = "a.example.com", modified: TimeInterval?) -> CustomUploader {
        var uploader = TestUploaders.http(name: name, host: host).withID(id)
        uploader.modifiedAt = modified.map(Date.init(timeIntervalSince1970:))
        return uploader
    }

    @Test func keepsBothVersionsWhenTheSameUploaderWasEditedOnBothMacs() {
        let id = UUID()
        let local = uploader("Zipline", id: id, host: "local.example.com", modified: 2000)
        let remote = uploader("Zipline", id: id, host: "remote.example.com", modified: 1500)
        let result = UploaderSyncMerge.merge(local: [local], incoming: [remote], lastSync: lastSync, copySuffix: "(from other Mac)", makeID: { copyID })
        #expect(result.conflicts.count == 1)
        #expect(Set(result.merged.map(\.id)) == [id, copyID])
        #expect(result.merged.first { $0.id == id }?.requestURL == "https://local.example.com/upload")
        let copy = result.merged.first { $0.id == copyID }
        #expect(copy?.name == "Zipline (from other Mac)")
        #expect(copy?.requestURL == "https://remote.example.com/upload")
    }

    @Test func acceptsRemoteChangesWhenNothingChangedLocally() {
        let id = UUID()
        let local = uploader("Old", id: id, modified: 500)
        let remote = uploader("New", id: id, host: "b.example.com", modified: 1500)
        let result = UploaderSyncMerge.merge(local: [local], incoming: [remote], lastSync: lastSync, copySuffix: "x")
        #expect(!result.changesIncoming)
        #expect(result.merged.map(\.name) == ["New"])
    }

    @Test func ignoresIdenticalContentAndRestoresLocallyAddedUploaders() {
        let id = UUID()
        let same = uploader("Same", id: id, modified: 2000)
        var remoteSame = same
        remoteSame.modifiedAt = Date(timeIntervalSince1970: 1800)
        let added = uploader("Added", modified: 3000)
        let result = UploaderSyncMerge.merge(local: [same, added], incoming: [remoteSame], lastSync: lastSync, copySuffix: "x")
        #expect(result.conflicts.isEmpty)
        #expect(result.restoredLocal.map(\.id) == [added.id])
        #expect(Set(result.merged.map(\.id)) == [id, added.id])
    }
}

@MainActor
struct UploadQueueTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-queue-\(UUID().uuidString)", directoryHint: .isDirectory)

    final class Box {
        var failures: [any Error] = []
        var uploaded: [(String, UploadDestination)] = []
        var succeeded: [UUID] = []
    }

    func queue(_ box: Box) -> UploadQueue {
        UploadQueue(directory: directory, perform: { url, destination in
            if !box.failures.isEmpty { throw box.failures.removeFirst() }
            box.uploaded.append((url.lastPathComponent, destination))
            return UploadOutcome(url: URL(string: "https://cdn.example.com/\(url.lastPathComponent)")!, deletionURL: nil, uploaderID: nil, s3Key: nil)
        }, onSuccess: { item, _ in box.succeeded.append(item.id) })
    }

    @Test func persistsCopiesAndRetriesSuccessfully() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let box = Box()
        let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
        let first = queue(box)
        let now = Date(timeIntervalSince1970: 10000)
        let item = try first.enqueue(fileURL: file, target: .imgur(clientID: "c"), localPath: file.path, error: UploadFailure.transport("offline"), now: now)
        try FileManager.default.removeItem(at: file)
        #expect(item.nextAttemptAt == now.addingTimeInterval(30))

        let reloaded = queue(box)
        #expect(reloaded.items.map(\.id) == [item.id])
        #expect(reloaded.items.first?.destinationName == "Imgur")
        #expect(FileManager.default.fileExists(atPath: reloaded.fileURL(for: item).path))

        await reloaded.retryDue(now: now)
        #expect(box.uploaded.isEmpty)
        await reloaded.retryDue(now: now.addingTimeInterval(31))
        #expect(box.uploaded.map(\.0) == ["shot.png"])
        #expect(box.uploaded.map(\.1) == [.builtIn(.IMGUR)])
        #expect(box.succeeded == [item.id])
        #expect(reloaded.items.isEmpty)
        #expect(queue(box).items.isEmpty)
    }

    @Test func backsOffAndPausesNonRetryableFailures() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let box = Box()
        box.failures = [UploadFailure.http(status: 503, body: nil), UploadFailure.http(status: 401, body: nil)]
        let file = try Fixtures.temporaryFile(named: "v.mp4", contents: Data([1]))
        let uploads = queue(box)
        let now = Date(timeIntervalSince1970: 0)
        let item = try uploads.enqueue(fileURL: file, target: .imgur(clientID: "c"), localPath: nil, error: UploadFailure.transport("x"), now: now)
        await uploads.retry(item.id, now: now)
        #expect(uploads.items.first?.attempts == 2)
        #expect(uploads.items.first?.nextAttemptAt == now.addingTimeInterval(60))
        #expect(uploads.items.first?.isPaused == false)
        await uploads.retry(item.id, now: now)
        #expect(uploads.items.first?.isPaused == true)
        #expect(queue(box).items.first?.attempts == 3)
        uploads.discard(item.id)
        #expect(uploads.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: item.id.uuidString).path))
    }

    @Test func capsBackoff() {
        #expect(UploadQueue.backoff(afterAttempts: 1) == 30)
        #expect(UploadQueue.backoff(afterAttempts: 3) == 120)
        #expect(UploadQueue.backoff(afterAttempts: 20) == 3600)
    }
}

@MainActor
struct WatchFolderTests {
    func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL
    }

    @Test(arguments: [
        ("shot.png", WatchFolderFilter.images, true), ("clip.mov", .images, false), ("clip.mov", .videos, true),
        ("notes.txt", .all, true), (".hidden.png", .all, false), ("download.png.crdownload", .all, false),
        ("movie.part", .all, false), ("~$doc.docx", .all, false), ("report.pdf", .images, false),
    ])
    func filtersCandidates(entry: (String, WatchFolderFilter, Bool)) {
        #expect(WatchFolderScanner.isCandidate(URL(fileURLWithPath: "/tmp/\(entry.0)"), filter: entry.1) == entry.2)
    }

    @Test func waitsUntilAFileStopsChanging() {
        var stability = WatchFolderStability()
        let url = URL(fileURLWithPath: "/tmp/a.png")
        let growing = WatchedFile(url: url, size: 10, modified: Date(timeIntervalSince1970: 1))
        let done = WatchedFile(url: url, size: 20, modified: Date(timeIntervalSince1970: 2))
        #expect(stability.observe([growing], ignoring: []).isEmpty)
        #expect(stability.observe([done], ignoring: []).isEmpty)
        #expect(stability.observe([done], ignoring: []) == [url])
        #expect(!stability.hasPending)
        #expect(stability.observe([done], ignoring: [url.path]).isEmpty)
        let empty = WatchedFile(url: URL(fileURLWithPath: "/tmp/e.png"), size: 0, modified: .distantPast)
        _ = stability.observe([empty], ignoring: [])
        #expect(stability.observe([empty], ignoring: []).isEmpty)
    }

    @Test func uploadsNewFilesOnceAndIgnoresExistingOnes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try TestUploaders.png.write(to: directory.appending(path: "existing.png"))
        var ready: [String] = []
        let monitor = WatchFolderMonitor(directory: directory, filter: .images, stabilityInterval: 0.2) { ready.append($0.lastPathComponent) }
        monitor.start()
        defer { monitor.stop() }
        try TestUploaders.png.write(to: directory.appending(path: "new.png"))
        try Data("x".utf8).write(to: directory.appending(path: "ignored.txt"))
        try Data([1]).write(to: directory.appending(path: "partial.png.download"))
        for _ in 0 ..< 50 where ready.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(ready == ["new.png"])
        monitor.scan()
        try await Task.sleep(for: .milliseconds(400))
        monitor.scan()
        #expect(ready == ["new.png"])
        #expect(monitor.handled.contains(directory.appending(path: "new.png").path))
    }
}
