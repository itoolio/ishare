import Defaults
import Foundation
import ishareCore
import Synchronization
import Testing
@testable import ishare

enum MaintenanceFixtures {
    static func deletable(name: String, host: String, days: Int? = nil) -> CustomUploader {
        CustomUploader(
            name: name, requestURL: "https://\(host)/upload", headers: ["Authorization": "key"], formData: nil, fileFormName: "file",
            responseURL: "{{url}}", deletionURL: "{{delete}}", deleteRequestType: .delete, autoDeleteAfterDays: days
        )
    }

    static func item(_ link: String, expiresAt: Date?, deletion: String? = "https://srv.example.com/delete/1", keepForever: Bool? = nil) -> HistoryItem {
        var item = HistoryItem(fileUrl: link, deletionUrl: deletion, date: Date(timeIntervalSince1970: 1))
        item.expiresAt = expiresAt
        item.keepForever = keepForever
        return item
    }
}

@MainActor
final class HistoryBox {
    var items: [HistoryItem]

    init(_ items: [HistoryItem]) {
        self.items = items
    }

    func update(_ item: HistoryItem, _ transform: (HistoryItem) -> HistoryItem?) {
        let key = item.storageKey
        items = items.compactMap { $0.storageKey == key ? transform($0) : $0 }
    }
}

@MainActor
struct UploadExpiryRunnerTests {
    let now = Date(timeIntervalSince1970: 5_000_000)

    func runner(_ box: HistoryBox, keeps: Bool = true, delete: @escaping @MainActor (HistoryItem) async throws -> Void) -> UploadExpiryRunner {
        UploadExpiryRunner(
            history: { box.items }, update: { item, transform in box.update(item, transform) }, delete: delete, keepsExpiredItems: keeps,
            clock: .fixed(now)
        )
    }

    @Test func deletesExpiredUploadsAndMarksThem() async {
        let box = HistoryBox([
            MaintenanceFixtures.item("https://a/1", expiresAt: now.addingTimeInterval(-1)),
            MaintenanceFixtures.item("https://a/2", expiresAt: now.addingTimeInterval(3600)),
            MaintenanceFixtures.item("https://a/3", expiresAt: now.addingTimeInterval(-1), keepForever: true),
            MaintenanceFixtures.item("https://a/4", expiresAt: nil),
        ])
        var deleted: [String] = []
        let summary = await runner(box) { deleted.append($0.fileUrl ?? "") }.run()
        #expect(deleted == ["https://a/1"])
        #expect(summary == UploadExpirySummary(deleted: 1))
        #expect(box.items[0].isExpired)
        #expect(box.items[0].expiredAt == now)
        #expect(!box.items[0].canDeleteFromServer)
        #expect(!box.items[0].hasLiveLink)
        #expect(box.items[1...].allSatisfy { !$0.isExpired })
        let again = await runner(box) { deleted.append($0.fileUrl ?? "") }.run()
        #expect(again.isEmpty)
        #expect(deleted.count == 1)
    }

    @Test func removesExpiredUploadsWhenHistoryShouldNotKeepThem() async {
        let box = HistoryBox([MaintenanceFixtures.item("https://a/1", expiresAt: now.addingTimeInterval(-1))])
        _ = await runner(box, keeps: false) { _ in }.run()
        #expect(box.items.isEmpty)
    }

    @Test func retriesFailuresWithBackoff() async {
        let box = HistoryBox([MaintenanceFixtures.item("https://a/1", expiresAt: now.addingTimeInterval(-1))])
        let summary = await runner(box) { _ in throw UploadFailure.transport("offline") }.run()
        #expect(summary.failed == 1)
        #expect(summary.errors == ["offline"])
        let item = box.items[0]
        #expect(!item.isExpired)
        #expect(item.expiryAttempts == 1)
        #expect(item.expiryError == "offline")
        #expect(item.nextExpiryAttemptAt == now.addingTimeInterval(UploadExpiry.firstRetryDelay))
        let waiting = await runner(box) { _ in Issue.record("Should wait for the backoff") }.run()
        #expect(waiting.isEmpty)
    }

    @Test func liveDeleterNeedsTheUploader() async {
        let item = HistoryItem(fileUrl: "https://a/1", uploaderId: UUID(), s3Key: "k")
        await #expect(throws: UploadFailure.missingUploader) {
            try await UploadExpiryService.deleteFromServer(item, uploaders: [])
        }
    }

    @Test func summarisesTheRun() {
        #expect(UploadExpiryService.summaryMessage(UploadExpirySummary(deleted: 2)).contains("2"))
        #expect(UploadExpiryService.summaryMessage(UploadExpirySummary(deleted: 1, failed: 3)).contains("3"))
        #expect(UploadExpiryService.summaryMessage(UploadExpirySummary()).isEmpty)
    }
}

@MainActor
struct HistoryItemExpiryTests {
    @Test func roundTripsTheExpiryState() {
        var item = MaintenanceFixtures.item("https://a/1", expiresAt: Date(timeIntervalSince1970: 10))
        let state = UploadExpiry.failed(item.expiryState, error: "x", now: Date(timeIntervalSince1970: 20))
        item = item.applying(state)
        #expect(item.expiryState == state)
        #expect(item.expiryAttempts == 1)
        let decoded = try? JSONDecoder().decode(HistoryItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        let legacy = try? JSONDecoder().decode(HistoryItem.self, from: Data(#"{"fileUrl": "https://a/1"}"#.utf8))
        #expect(legacy?.expiresAt == nil)
        #expect(legacy?.isKeptForever == false)
    }

    @Test func recordsTheExpiryForUploadersThatCanDelete() {
        let now = Date(timeIntervalSince1970: 1000)
        let uploader = MaintenanceFixtures.deletable(name: "d", host: "d.example.com", days: 7)
        let outcome = UploadOutcome(url: URL(string: "https://d.example.com/a.png")!, deletionURL: "https://d.example.com/del/a", uploaderID: uploader.id, s3Key: nil)
        let item = UploadCoordinator.historyItem(for: outcome, target: .custom(uploader), localFileURL: nil, now: now)
        #expect(item.expiresAt == now.addingTimeInterval(7 * 86400))
        var noDeletion = outcome
        noDeletion.deletionURL = nil
        #expect(UploadCoordinator.historyItem(for: noDeletion, target: .custom(uploader), localFileURL: nil, now: now).expiresAt == nil)
        #expect(UploadCoordinator.historyItem(for: outcome, target: .imgur(clientID: "c"), localFileURL: nil, now: now).expiresAt == nil)
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct UploadMaintenancePipelineTests {
        let spy = UploadEnvironmentSpy()
        let savedIndex: DuplicateIndex
        let savedPolicy: DuplicatePolicy

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            UploadCoordinator.environment = spy
            savedIndex = Defaults[.uploadHashIndex]
            savedPolicy = Defaults[.duplicateUploadPolicy]
            Defaults[.uploadHashIndex] = DuplicateIndex()
            StubURLProtocol.reset { request in
                switch request.method {
                case "DELETE":
                    StubResponse(status: 204)
                default:
                    StubResponse(
                        body: Data(#"{"url": "https://origin.example.com/files/a.png?sig=1", "delete": "https://origin.example.com/delete/a"}"#.utf8))
                }
            }
        }

        func finish() {
            UploadCoordinator.environment = LiveUploadEnvironment()
            Defaults[.uploadHashIndex] = savedIndex
            Defaults[.duplicateUploadPolicy] = savedPolicy
        }

        @Test func rewritesTheReturnedLinkAndRemembersTheOriginal() async throws {
            defer { finish() }
            var uploader = MaintenanceFixtures.deletable(name: "cdn", host: "origin.example.com")
            uploader.linkRewrite = LinkRewrite(host: "cdn.example.com", pathPrefix: "/i", stripQuery: true, rewritesDeletionURL: true)
            defer { LinkRewriting.forget(uploader.id) }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let results = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            let outcome = try #require(try results.first?.get())
            #expect(outcome.url.absoluteString == "https://cdn.example.com/i/files/a.png")
            #expect(spy.history.first?.fileUrl == "https://cdn.example.com/i/files/a.png")
            #expect(spy.history.first?.deletionUrl == "https://cdn.example.com/i/delete/a")
            #expect(LinkRewriting.lastLink(for: uploader.id)?.absoluteString == "https://origin.example.com/files/a.png?sig=1")
        }

        @Test func reusesTheExistingLinkWhenAlwaysReusing() async throws {
            defer { finish() }
            Defaults[.duplicateUploadPolicy] = .alwaysReuse
            let uploader = TestUploaders.http(name: "dup", host: "dup.example.com")
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: file)
            let copy = try Fixtures.temporaryFile(named: "copy.png", contents: TestUploaders.png)
            let results = await UploadCoordinator.upload(fileURL: copy, to: [.custom(uploader)], localFileURL: copy)
            #expect(StubURLProtocol.captured.count == 1)
            let reused = try #require(try results.first?.get())
            #expect(reused.isReused)
            #expect(reused.url.absoluteString == "https://origin.example.com/files/a.png?sig=1")
            #expect(spy.history.count == 1)
            #expect(spy.notifications == ["Already uploaded".localized()])
            #expect(spy.promoted.count == 1)
            #expect(UploadPlan.urlToDeliver(results) == reused.url)
        }

        @Test func asksAndUploadsAgainWhenTheUserSaysSo() async throws {
            defer { finish() }
            Defaults[.duplicateUploadPolicy] = .ask
            let uploader = TestUploaders.http(name: "dup", host: "dup.example.com")
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            #expect(spy.duplicatePrompts.count == 1)
            #expect(StubURLProtocol.captured.count == 2)
            spy.duplicateDecision = .reuse
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            #expect(spy.duplicatePrompts.count == 2)
            #expect(StubURLProtocol.captured.count == 2)
        }

        @Test func neverReusesWhenDisabledOrTheLinkIsGone() async throws {
            defer { finish() }
            Defaults[.duplicateUploadPolicy] = .alwaysReuse
            let uploader = TestUploaders.http(name: "dup", host: "dup.example.com")
            let other = TestUploaders.http(name: "other", host: "other.example.com")
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(other)], localFileURL: nil)
            #expect(StubURLProtocol.captured.count == 2)
            spy.history = spy.history.map { item in
                var expired = item
                expired.expiredAt = Date()
                return expired
            }
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            #expect(StubURLProtocol.captured.count == 3)
            _ = await DuplicateUploads.$policyOverride.withValue(.never) {
                await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            }
            #expect(StubURLProtocol.captured.count == 4)
            #expect(spy.notifications.isEmpty)
        }

        @Test func deletesExpiredHTTPUploadsThroughTheirDeletionURL() async throws {
            defer { finish() }
            let uploader = MaintenanceFixtures.deletable(name: "exp", host: "origin.example.com", days: 1)
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            let recorded = try #require(spy.history.first)
            let expiresAt = try #require(recorded.expiresAt)
            let box = HistoryBox(spy.history)
            let runner = UploadExpiryRunner(
                history: { box.items }, update: { item, transform in box.update(item, transform) },
                delete: { item in try await UploadExpiryService.deleteFromServer(item, uploaders: [uploader]) }, keepsExpiredItems: true,
                clock: .fixed(expiresAt.addingTimeInterval(1))
            )
            let summary = await runner.run()
            #expect(summary.deleted == 1)
            let deletion = try #require(StubURLProtocol.lastRequest)
            #expect(deletion.method == "DELETE")
            #expect(deletion.url.absoluteString == "https://origin.example.com/delete/a")
            #expect(deletion.headers["Authorization"] == "key")
            #expect(box.items.first?.isExpired == true)
        }

        @Test func queuedRetriesGoThroughTheFullPipeline() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-queue-\(UUID().uuidString)", directoryHint: .isDirectory)
            let previousOptimize = Defaults[.optimizeImagesBeforeUpload]
            let previousWebhooks = Defaults[.uploadWebhooks]
            Defaults[.optimizeImagesBeforeUpload] = true
            Defaults[.uploadWebhooks] = [UploadWebhook(url: "https://hooks.example.com/queued")]
            WebhookDispatcher.session = StubURLProtocol.makeSession()
            WebhookDispatcher.isEnabled = true
            WebhookDispatcher.altTextWait = .zero
            defer {
                WebhookDispatcher.isEnabled = false
                Defaults[.optimizeImagesBeforeUpload] = previousOptimize
                Defaults[.uploadWebhooks] = previousWebhooks
                try? FileManager.default.removeItem(at: directory)
                finish()
            }
            StubURLProtocol.reset { request in
                request.url.host() == "hooks.example.com"
                    ? StubResponse(status: 204)
                    : StubResponse(body: Data(#"{"data": {"link": "https://i.imgur.com/queued.png", "deletehash": "h"}}"#.utf8))
            }
            var succeeded: [UploadOutcome] = []
            let queue = UploadQueue(
                directory: directory,
                perform: { fileURL, item in try await UploadCoordinator.retryQueued(fileURL: fileURL, item: item) },
                onSuccess: { _, outcome in
                    succeeded.append(outcome)
                    UploadCoordinator.completeQueued(outcome)
                })
            let source = try SyntheticImages.unfilteredPNG()
            let originalSize = ImageOptimizer.fileSize(source)
            let now = Date(timeIntervalSince1970: 50000)
            let item = try queue.enqueue(fileURL: source, target: .imgur(clientID: "cid"), localPath: source.path, error: UploadFailure.transport("offline"), now: now)
            await queue.retry(item.id, now: now)
            #expect(queue.items.isEmpty)
            let outcome = try #require(succeeded.first)
            #expect(outcome.savedBytes ?? 0 > 0)
            let history = try #require(spy.history.first)
            #expect(history.fileUrl == "https://i.imgur.com/queued.png")
            #expect(history.localPath == source.path)
            #expect(history.originalSize == originalSize)
            #expect(spy.delivered.map(\.absoluteString) == ["https://i.imgur.com/queued.png"])
            let upload = try #require(StubURLProtocol.captured.first { $0.url.host() != "hooks.example.com" })
            #expect(upload.body.count < originalSize + 1024)
            var hook: CapturedRequest?
            for _ in 0 ..< 100 where hook == nil {
                try await Task.sleep(for: .milliseconds(20))
                hook = StubURLProtocol.captured.first { $0.url.host() == "hooks.example.com" }
            }
            let delivered = try #require(hook)
            let json = try #require(try JSONSerialization.jsonObject(with: delivered.body) as? [String: Any])
            #expect(json["link"] as? String == "https://i.imgur.com/queued.png")
        }
    }

    @MainActor
    @Suite
    struct UploaderHealthCheckTests {
        let now = Date(timeIntervalSince1970: 7_000_000)
        let savedFrequency: HealthCheckFrequency
        let savedRecords: [String: HealthCheckRecord]
        let savedLastCheck: Date?

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            savedFrequency = Defaults[.uploaderHealthCheckFrequency]
            savedRecords = Defaults[.uploaderHealthRecords]
            savedLastCheck = Defaults[.uploaderHealthLastCheck]
            Defaults[.uploaderHealthCheckFrequency] = .daily
            Defaults[.uploaderHealthLastCheck] = nil
            UploaderHealthCheck.clock = .fixed(now)
            UploaderHealthCheck.conditions = { .ideal }
        }

        func finish() {
            Defaults[.uploaderHealthCheckFrequency] = savedFrequency
            Defaults[.uploaderHealthRecords] = savedRecords
            Defaults[.uploaderHealthLastCheck] = savedLastCheck
            UploaderHealthCheck.clock = .system
            UploaderHealthCheck.defaultTarget = { UploadCoordinator.currentTarget() }
            UploaderHealthCheck.reportFailure = { _ in }
        }

        @Test func uploadsATinyImageAndDeletesIt() async throws {
            defer { finish() }
            StubURLProtocol.reset { request in
                request.method == "DELETE"
                    ? StubResponse(status: 204)
                    : StubResponse(body: Data(#"{"url": "https://h.example.com/p.png", "delete": "https://h.example.com/del/p"}"#.utf8))
            }
            let uploader = MaintenanceFixtures.deletable(name: "health", host: "h.example.com")
            UploaderHealthCheck.defaultTarget = { .custom(uploader) }
            let outcome = await UploaderHealthCheck.run()
            let record = try #require(outcome.record)
            #expect(record == HealthCheckRecord(date: now, succeeded: true, uploaderName: "health", method: .uploadAndDelete))
            let captured = StubURLProtocol.captured
            #expect(captured.map(\.method) == ["POST", "DELETE"])
            #expect(captured[0].body.range(of: HealthCheckProbe.tinyPNG) != nil)
            #expect(captured[1].url.absoluteString == "https://h.example.com/del/p")
            #expect(Defaults[.uploaderHealthRecords][uploader.id.uuidString] == record)
            #expect(Defaults[.uploaderHealthLastCheck] == now)
            #expect(await UploaderHealthCheck.run() == .skipped(.notDue))
        }

        @Test func reportsFailuresWithTheReason() async throws {
            defer { finish() }
            StubURLProtocol.reset { _ in StubResponse(status: 500, body: Data("down".utf8)) }
            let uploader = MaintenanceFixtures.deletable(name: "broken", host: "b.example.com")
            UploaderHealthCheck.defaultTarget = { .custom(uploader) }
            var reported: [HealthCheckRecord] = []
            UploaderHealthCheck.reportFailure = { reported.append($0) }
            let record = try #require(await UploaderHealthCheck.run().record)
            #expect(!record.succeeded)
            #expect(record.message?.contains("500") == true)
            #expect(reported == [record])
            #expect(UploaderHealthCheck.failureMessage(record).contains("500"))
            #expect(UploaderHealthBadge.description(record).contains("500"))
        }

        @Test func probesUploadersThatCantDelete() async throws {
            defer { finish() }
            StubURLProtocol.reset { _ in StubResponse(status: 405) }
            let uploader = TestUploaders.http(name: "probe", host: "p.example.com")
            UploaderHealthCheck.defaultTarget = { .custom(uploader) }
            let record = try #require(await UploaderHealthCheck.run().record)
            #expect(record.succeeded)
            #expect(record.method == .probe)
            #expect(StubURLProtocol.captured.map(\.method) == ["OPTIONS"])
            #expect(StubURLProtocol.captured.first?.url.absoluteString == "https://p.example.com/upload")
        }

        @Test func skipsOnBatteryMeteredNetworksAndWhenOff() async {
            defer { finish() }
            StubURLProtocol.reset { _ in StubResponse() }
            UploaderHealthCheck.defaultTarget = { .custom(TestUploaders.http(name: "x", host: "x.example.com")) }
            UploaderHealthCheck.conditions = { HealthCheckConditions(batteryLevel: 10, isOnBattery: true) }
            #expect(await UploaderHealthCheck.run(forced: true) == .skipped(.lowBattery))
            UploaderHealthCheck.conditions = { HealthCheckConditions(isConstrained: true) }
            #expect(await UploaderHealthCheck.run() == .skipped(.constrainedNetwork))
            UploaderHealthCheck.conditions = { .ideal }
            Defaults[.uploaderHealthCheckFrequency] = .off
            #expect(await UploaderHealthCheck.run() == .skipped(.disabled))
            UploaderHealthCheck.defaultTarget = { .localNetwork }
            #expect(await UploaderHealthCheck.run(forced: true) == .skipped(.unsupportedUploader))
            #expect(StubURLProtocol.captured.isEmpty)
        }
    }

    @MainActor
    @Suite
    struct DropboxUploadSessionTests {
        init() {
            UploadService.session = StubURLProtocol.makeSession()
            OAuthSession.now = { Date(timeIntervalSince1970: 10000) }
        }

        func signedIn() throws -> CustomUploader {
            let uploader = CustomUploader.cloud(name: "db", provider: .dropbox, configuration: CloudStorageConfiguration(folder: "ishare", clientID: "client"))
            try OAuthTokenStore.save(OAuthToken(accessToken: "access", refreshToken: "refresh", expiresAt: Date(timeIntervalSince1970: 20000)), for: uploader.id)
            return uploader
        }

        func argument(_ request: CapturedRequest) -> [String: Any] {
            let header = request.headers["Dropbox-API-Arg"] ?? "{}"
            return (try? JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any]) ?? [:]
        }

        func cursor(_ request: CapturedRequest) -> String {
            let cursor = argument(request)["cursor"] as? [String: Any] ?? [:]
            return "\(cursor["session_id"] as? String ?? "-")@\((cursor["offset"] as? NSNumber)?.intValue ?? -1)"
        }

        @Test func uploadsLargeFilesInChunksAndCorrectsTheOffset() async throws {
            let corrected = Mutex(false)
            StubURLProtocol.reset { request in
                switch request.url.path() {
                case "/2/files/upload_session/start":
                    return StubResponse(body: Data(#"{"session_id": "s1"}"#.utf8))
                case "/2/files/upload_session/append_v2":
                    let first = corrected.withLock { done in
                        defer { done = true }
                        return !done
                    }
                    guard first else { return StubResponse(body: Data("null".utf8)) }
                    return StubResponse(
                        status: 409, body: Data(#"{"error_summary": "incorrect_offset/", "error": {".tag": "incorrect_offset", "correct_offset": 6}}"#.utf8))
                case "/2/files/upload_session/finish":
                    return StubResponse(body: Data(#"{"id": "id:big", "path_lower": "/ishare/big.bin"}"#.utf8))
                case "/2/sharing/create_shared_link_with_settings":
                    return StubResponse(body: Data(#"{"url": "https://www.dropbox.com/s/big"}"#.utf8))
                default:
                    return StubResponse(status: 404)
                }
            }
            let bytes = Data((0 ..< 30).map { UInt8($0) })
            let file = try Fixtures.temporaryFile(named: "big.bin", contents: bytes)
            var uploader = CloudStorageUploader(uploader: try signedIn(), provider: .dropbox)
            uploader.dropboxSessionThreshold = 10
            uploader.dropboxChunkSize = 8
            let progress = Mutex<[Double]>([])
            let outcome = try await uploader.upload(fileURL: file) { value in progress.withLock { $0.append(value) } }
            #expect(outcome.url.absoluteString == "https://www.dropbox.com/s/big")
            #expect(outcome.s3Key == "id:big")
            let calls = StubURLProtocol.captured.filter { $0.url.host() == "content.dropboxapi.com" }
            #expect(calls.map { $0.url.lastPathComponent } == ["start", "append_v2", "append_v2", "append_v2", "finish"])
            #expect(calls[0].body == bytes[0 ..< 8])
            #expect(cursor(calls[1]) == "s1@8")
            #expect(calls[2].body == bytes[6 ..< 14])
            #expect(cursor(calls[2]) == "s1@6")
            #expect(calls[3].body == bytes[14 ..< 22])
            #expect(calls[4].body == bytes[22 ..< 30])
            let finish = argument(calls[4])
            #expect(cursor(calls[4]) == "s1@22")
            #expect((finish["commit"] as? [String: Any])?["path"] as? String == "/ishare/big.bin")
            #expect(calls.allSatisfy { $0.headers["Authorization"] == "Bearer access" })
            #expect(progress.withLock { $0.last } == 1)
            #expect(!StubURLProtocol.captured.contains { $0.url.path() == "/2/files/upload" })
        }

        @Test func keepsSmallFilesOnTheSingleRequest() async throws {
            StubURLProtocol.reset { request in
                request.url.path() == "/2/files/upload"
                    ? StubResponse(body: Data(#"{"id": "id:s", "path_lower": "/ishare/s.png"}"#.utf8))
                    : StubResponse(body: Data(#"{"url": "https://www.dropbox.com/s/s"}"#.utf8))
            }
            let file = try Fixtures.temporaryFile(named: "s.png", contents: TestUploaders.png)
            _ = try await CloudStorageUploader(uploader: try signedIn(), provider: .dropbox).upload(fileURL: file) { _ in }
            #expect(StubURLProtocol.captured.first?.url.path() == "/2/files/upload")
            #expect(!StubURLProtocol.captured.contains { $0.url.path().contains("upload_session") })
        }

        @Test func givesUpWhenTheServerKeepsRejectingTheOffset() async throws {
            StubURLProtocol.reset { request in
                switch request.url.path() {
                case "/2/files/upload_session/start":
                    StubResponse(body: Data(#"{"session_id": "s1"}"#.utf8))
                default:
                    StubResponse(status: 409, body: Data(#"{"error": {".tag": "not_found"}}"#.utf8))
                }
            }
            let file = try Fixtures.temporaryFile(named: "big.bin", contents: Data(count: 30))
            var uploader = CloudStorageUploader(uploader: try signedIn(), provider: .dropbox)
            uploader.dropboxSessionThreshold = 10
            uploader.dropboxChunkSize = 8
            await #expect(throws: UploadFailure.self) {
                _ = try await uploader.upload(fileURL: file) { _ in }
            }
        }
    }
}
