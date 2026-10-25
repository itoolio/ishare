import Foundation
import ImageIO
import Testing
@testable import ishareCore

struct LinkRewriteTests {
    let url = URL(string: "http://uploads.example.com:8080/files/a%20b.png?token=abc#top")!

    @Test func rewritesHostSchemePrefixAndQuery() throws {
        let rewrite = LinkRewrite(host: "cdn.example.com", scheme: "https", pathPrefix: "i/", stripQuery: true)
        #expect(rewrite.apply(to: url)?.absoluteString == "https://cdn.example.com/i/files/a%20b.png#top")
    }

    @Test func keepsTheQueryAndAllowsAPortInTheHost() {
        let rewrite = LinkRewrite(host: "cdn.example.com:8443")
        #expect(rewrite.apply(to: url)?.absoluteString == "http://cdn.example.com:8443/files/a%20b.png?token=abc#top")
    }

    @Test func rendersAFullTemplate() {
        let rewrite = LinkRewrite(host: "ignored.example.com", template: "https://cdn.example.com/{{path}}?from={{host}}&name={{filename}}")
        #expect(rewrite.apply(to: url)?.absoluteString == "https://cdn.example.com/files/a%20b.png?from=uploads.example.com&name=a%20b.png")
        #expect(
            LinkRewrite(template: "https://cdn.example.com/{{ path }}{{query}}").apply(to: URL(string: "https://a.com/x.png")!)?.absoluteString == "https://cdn.example.com/x.png")
    }

    @Test func rewritesTheDeletionURLOnlyWhenAsked() {
        let rewrite = LinkRewrite(host: "cdn.example.com")
        #expect(rewrite.applyToDeletionURL("https://up.example.com/delete/1") == "https://up.example.com/delete/1")
        var both = rewrite
        both.rewritesDeletionURL = true
        #expect(both.applyToDeletionURL("https://up.example.com/delete/1") == "https://cdn.example.com/delete/1")
        #expect(both.applyToDeletionURL(nil) == nil)
        #expect(both.applyToDeletionURL("not a url") == "not a url")
    }

    @Test func validatesTheRules() {
        #expect(LinkRewrite().issues == [.emptyLinkRewrite])
        #expect(LinkRewrite(stripQuery: false).issues == [.emptyLinkRewrite])
        #expect(LinkRewrite(stripQuery: true).issues.isEmpty)
        #expect(LinkRewrite(host: "https://cdn.example.com").issues == [.invalidLinkRewriteHost])
        #expect(LinkRewrite(host: "cdn.example.com/x").issues == [.invalidLinkRewriteHost])
        #expect(LinkRewrite(host: "cdn.example.com:99999").issues == [.invalidLinkRewriteHost])
        #expect(LinkRewrite(scheme: "ftp").issues == [.invalidLinkRewriteScheme])
        #expect(LinkRewrite(template: "https://cdn.example.com/{{path}").issues == [.malformedTemplate(field: "link template")])
        #expect(LinkRewrite(template: "https://cdn.example.com/{{nope}}").issues == [.invalidLinkRewriteTemplate])
        #expect(LinkRewrite(template: "ftp://cdn.example.com/{{path}}").issues == [.invalidLinkRewriteTemplate])
        #expect(LinkRewrite(template: "https://cdn.example.com/{{path}}").issues.isEmpty)
    }

    @Test func decodesAndRoundTripsTheISCUBlock() throws {
        let json = Data(
            """
            {"name": "cdn", "requestURL": "https://up.example.com", "responseURL": "{{url}}",
             "LinkRewrite": {"Host": "cdn.example.com", "scheme": "https", "PathPrefix": "/i", "stripQuery": true, "rewriteDeletionURL": true}}
            """.utf8)
        let uploader = try CustomUploader.fromJSON(json)
        #expect(uploader.linkRewrite == LinkRewrite(host: "cdn.example.com", scheme: "https", pathPrefix: "/i", stripQuery: true, rewritesDeletionURL: true))
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
        let decoded = try CustomUploader.fromJSON(uploader.toJSON())
        #expect(decoded.linkRewrite == uploader.linkRewrite)
        #expect(decoded.renamed("x").linkRewrite == uploader.linkRewrite)
    }

    @Test func validatorReportsBrokenRewrites() throws {
        var uploader = TestUploaders.http(name: "a", host: "a.example.com")
        uploader.linkRewrite = LinkRewrite(scheme: "gopher")
        #expect(UploaderValidator.issues(for: uploader) == [.invalidLinkRewriteScheme])
    }

    @Test func decodesTheCDNExample() throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/zipline-cdn.iscu"))
        #expect(uploader.linkRewrite?.trimmedHost == "cdn.example.com")
        #expect(uploader.autoDeleteAfterDays == 30)
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }
}

struct UploadExpiryTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func computesTheExpiryDate() {
        #expect(UploadExpiry.expiryDate(uploadedAt: now, days: 7) == now.addingTimeInterval(7 * 86400))
        #expect(UploadExpiry.expiryDate(uploadedAt: now, days: nil) == nil)
        #expect(UploadExpiry.expiryDate(uploadedAt: now, days: 0) == nil)
        #expect(UploadExpiry.expiryDate(uploadedAt: now, days: 5000) == nil)
    }

    @Test func decidesWhatIsDue() {
        let past = now.addingTimeInterval(-1)
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: nil), now: now) == .none)
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: past), now: now) == .due)
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: now), now: now) == .due)
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: now.addingTimeInterval(10)), now: now) == .scheduled(now.addingTimeInterval(10)))
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: past, keepForever: true), now: now) == .keptForever)
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: past, expiredAt: past), now: now) == .alreadyExpired)
        #expect(UploadExpiry.decision(for: UploadExpiryState(expiresAt: past, attempts: 10), now: now) == .gaveUp)
        #expect(
            UploadExpiry.decision(for: UploadExpiryState(expiresAt: past, attempts: 1, nextAttemptAt: now.addingTimeInterval(5)), now: now) == .retrying(now.addingTimeInterval(5)))
    }

    @Test func backsOffAfterFailures() {
        let first = UploadExpiry.failed(UploadExpiryState(expiresAt: now), error: "offline", now: now)
        #expect(first.attempts == 1)
        #expect(first.nextAttemptAt == now.addingTimeInterval(15 * 60))
        #expect(first.lastError == "offline")
        let second = UploadExpiry.failed(first, error: "offline", now: now)
        #expect(second.nextAttemptAt == now.addingTimeInterval(30 * 60))
        #expect(UploadExpiry.retryDelay(afterAttempts: 20) == 86400)
        #expect(!UploadExpiry.isDue(second, now: now.addingTimeInterval(29 * 60)))
        #expect(UploadExpiry.isDue(second, now: now.addingTimeInterval(30 * 60)))
        let expired = UploadExpiry.expired(second, now: now)
        #expect(expired.expiredAt == now)
        #expect(expired.nextAttemptAt == nil)
    }

    @Test func picksDueIndicesAndTheNextWakeUpWithAnInjectedClock() {
        let clock = MaintenanceClock.fixed(now)
        let states = [
            UploadExpiryState(expiresAt: now.addingTimeInterval(-60)),
            UploadExpiryState(expiresAt: now.addingTimeInterval(-60), keepForever: true),
            UploadExpiryState(expiresAt: now.addingTimeInterval(3600)),
            UploadExpiryState(expiresAt: nil),
        ]
        #expect(UploadExpiry.dueIndices(states, now: clock.now()) == [0])
        #expect(UploadExpiry.nextWakeUp(Array(states.dropFirst()), now: clock.now()) == now.addingTimeInterval(3600))
        #expect(UploadExpiry.nextWakeUp(states, now: clock.now()) == now)
    }

    @Test func mapsPresets() {
        #expect(AutoDeletePreset(days: nil) == .off)
        #expect(AutoDeletePreset(days: 7) == .sevenDays)
        #expect(AutoDeletePreset(days: 14) == .custom)
        #expect(AutoDeletePreset.ninetyDays.days == 90)
        #expect(AutoDeletePreset.custom.days == nil)
    }

    @Test func onlyUploadersThatCanDeleteSupportAutoDelete() {
        var http = TestUploaders.http(name: "h", host: "h.example.com")
        http.autoDeleteAfterDays = 7
        #expect(UploaderValidator.issues(for: http) == [.autoDeleteNeedsDeletion])
        #expect(http.effectiveAutoDeleteDays == nil)
        let deletable = CustomUploader(
            name: "d", requestURL: "https://d.example.com", headers: nil, formData: nil, fileFormName: nil, responseURL: "{{url}}",
            deletionURL: "{{delete}}", autoDeleteAfterDays: 7
        )
        #expect(UploaderValidator.issues(for: deletable).isEmpty)
        #expect(deletable.effectiveAutoDeleteDays == 7)
        var folder = CustomUploader.folder(name: "f", destination: FolderDestination(path: "/tmp"))
        folder.autoDeleteAfterDays = 1
        #expect(UploaderValidator.issues(for: folder).contains(.autoDeleteNeedsDeletion))
        var s3 = deletable
        s3.autoDeleteAfterDays = 0
        #expect(UploaderValidator.issues(for: s3) == [.invalidAutoDeleteDays])
        let decoded = try? CustomUploader.fromJSON(deletable.toJSON())
        #expect(decoded?.autoDeleteAfterDays == 7)
    }

    @Test func schedulesMaintenanceRuns() {
        #expect(MaintenanceSchedule.isDue(lastRun: nil, interval: 60, now: now))
        #expect(!MaintenanceSchedule.isDue(lastRun: now.addingTimeInterval(-30), interval: 60, now: now))
        #expect(MaintenanceSchedule.isDue(lastRun: now.addingTimeInterval(-60), interval: 60, now: now))
        #expect(MaintenanceSchedule.isDue(lastRun: now.addingTimeInterval(600), interval: 60, now: now))
    }
}

struct HealthCheckPlannerTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func runsWhenOverdue() {
        #expect(!HealthCheckPlanner.isDue(frequency: .off, lastCheck: nil, now: now))
        #expect(HealthCheckPlanner.isDue(frequency: .daily, lastCheck: nil, now: now))
        #expect(!HealthCheckPlanner.isDue(frequency: .daily, lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(HealthCheckPlanner.isDue(frequency: .daily, lastCheck: now.addingTimeInterval(-86400), now: now))
        #expect(!HealthCheckPlanner.isDue(frequency: .weekly, lastCheck: now.addingTimeInterval(-86400 * 6), now: now))
        #expect(HealthCheckPlanner.nextCheck(frequency: .weekly, lastCheck: now, now: now) == now.addingTimeInterval(7 * 86400))
        #expect(HealthCheckPlanner.nextCheck(frequency: .off, lastCheck: now, now: now) == nil)
    }

    @Test func skipsOnLowBatteryAndMeteredNetworks() {
        #expect(HealthCheckPlanner.blockingCondition(.ideal) == nil)
        #expect(HealthCheckPlanner.blockingCondition(HealthCheckConditions(batteryLevel: 19, isOnBattery: true)) == .lowBattery)
        #expect(HealthCheckPlanner.blockingCondition(HealthCheckConditions(batteryLevel: 19, isOnBattery: false)) == nil)
        #expect(HealthCheckPlanner.blockingCondition(HealthCheckConditions(batteryLevel: 20, isOnBattery: true)) == nil)
        #expect(HealthCheckPlanner.blockingCondition(HealthCheckConditions(isConstrained: true)) == .constrainedNetwork)
        #expect(HealthCheckPlanner.blockingCondition(HealthCheckConditions(isExpensive: true)) == .expensiveNetwork)
    }

    @Test func forcedChecksIgnoreTheScheduleButNotTheConditions() {
        let recent = now.addingTimeInterval(-60)
        #expect(HealthCheckPlanner.skipReason(frequency: .daily, lastCheck: recent, conditions: .ideal, now: now) == .notDue)
        #expect(HealthCheckPlanner.skipReason(frequency: .off, lastCheck: nil, conditions: .ideal, now: now) == .disabled)
        #expect(HealthCheckPlanner.skipReason(frequency: .off, lastCheck: recent, conditions: .ideal, now: now, forced: true) == nil)
        #expect(
            HealthCheckPlanner.skipReason(frequency: .daily, lastCheck: nil, conditions: HealthCheckConditions(isExpensive: true), now: now, forced: true)
                == .expensiveNetwork)
    }

    @Test func probeIsAValidOnePixelPNG() throws {
        let source = try #require(CGImageSourceCreateWithData(HealthCheckProbe.tinyPNG as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1)
        #expect(image.height == 1)
    }
}

struct DuplicateIndexTests {
    let date = Date(timeIntervalSince1970: 100)

    @Test func hashesFilesInChunks() throws {
        let data = Data((0 ..< 300_000).map { UInt8($0 % 251) })
        let file = try Fixtures.temporaryFile(named: "a.bin", contents: data)
        #expect(try ContentHash.sha256(of: file, chunkSize: 4096) == ContentHash.sha256(of: data))
        #expect(try ContentHash.sha256(of: file) == ContentHash.sha256(of: data))
        #expect(ContentHash.sha256(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func findsTheNewestLiveLinkForTheSameDestination() {
        var index = DuplicateIndex()
        index.remember(hash: "h", destination: "u1", link: "https://a/1", date: date)
        index.remember(hash: "h", destination: "u1", link: "https://a/2", date: date)
        index.remember(hash: "h", destination: "u2", link: "https://b/1", date: date)
        #expect(index.links(hash: "h", destination: "u1") == ["https://a/2", "https://a/1"])
        #expect(index.existingLink(hash: "h", destination: "u1") { $0 != "https://a/2" } == "https://a/1")
        #expect(index.existingLink(hash: "h", destination: "u3") { _ in true } == nil)
        #expect(index.existingLink(hash: "x", destination: "u1") { _ in true } == nil)
        index.forget(link: "https://a/1")
        #expect(index.links(hash: "h", destination: "u1") == ["https://a/2"])
        index.prune { $0.hasPrefix("https://b") }
        #expect(index.entries.map(\.link) == ["https://b/1"])
    }

    @Test func capsTheIndex() {
        var index = DuplicateIndex()
        for number in 0 ..< 10 {
            index.remember(hash: "\(number)", destination: "u", link: "https://a/\(number)", date: date, capacity: 3)
        }
        #expect(index.entries.map(\.hash) == ["9", "8", "7"])
        index.remember(hash: "8", destination: "u", link: "https://a/8", date: date, capacity: 3)
        #expect(index.entries.map(\.hash) == ["8", "9", "7"])
    }

    @Test func policiesMapToDecisions() {
        #expect(DuplicatePolicy.ask.automaticDecision == nil)
        #expect(DuplicatePolicy.alwaysReuse.automaticDecision == .reuse)
        #expect(DuplicatePolicy.never.automaticDecision == .uploadAgain)
    }
}

struct DropboxUploadSessionTests {
    @Test func keepsSmallFilesOnTheSingleRequestPath() {
        #expect(!DropboxUploadSession.usesSession(size: 150 * 1024 * 1024))
        #expect(DropboxUploadSession.usesSession(size: 150 * 1024 * 1024 + 1))
    }

    @Test func plansStartAppendAndFinish() {
        #expect(DropboxUploadSession.plan(size: 25, chunkSize: 10) == [.start(0 ..< 10), .append(10 ..< 20), .finish(20 ..< 25)])
        #expect(DropboxUploadSession.plan(size: 20, chunkSize: 10) == [.start(0 ..< 10), .finish(10 ..< 20)])
        #expect(DropboxUploadSession.plan(size: 5, chunkSize: 10) == [.start(0 ..< 5), .finish(5 ..< 5)])
        #expect(DropboxUploadSession.nextStep(offset: 12, size: 25, chunkSize: 10, started: true) == .append(12 ..< 22))
        #expect(DropboxUploadSession.nextStep(offset: 99, size: 25, chunkSize: 10, started: true) == .finish(25 ..< 25))
    }

    @Test func readsTheCorrectOffsetFromBothErrorShapes() {
        let append = #"{"error_summary": "incorrect_offset/..", "error": {".tag": "incorrect_offset", "correct_offset": 1234}}"#
        let finish = #"{"error": {".tag": "lookup_failed", "lookup_failed": {".tag": "incorrect_offset", "correct_offset": 77}}}"#
        #expect(DropboxUploadSession.correctOffset(fromErrorBody: append) == 1234)
        #expect(DropboxUploadSession.correctOffset(fromErrorBody: finish) == 77)
        #expect(DropboxUploadSession.correctOffset(fromErrorBody: #"{"error": {".tag": "not_found"}}"#) == nil)
        #expect(DropboxUploadSession.correctOffset(fromErrorBody: "busy") == nil)
    }
}
