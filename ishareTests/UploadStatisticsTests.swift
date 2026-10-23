import Foundation
import Testing
@testable import ishare

struct UploadStatisticsMathTests {
    @Test func percentileUsesTheNearestRank() {
        let values = (1 ... 20).map(Double.init)
        #expect(UploadStatisticsMath.percentile(0.95, of: values) == 19)
        #expect(UploadStatisticsMath.percentile(0.5, of: values) == 10)
        #expect(UploadStatisticsMath.percentile(1, of: values) == 20)
        #expect(UploadStatisticsMath.percentile(0, of: values) == 1)
    }

    @Test func percentileHandlesSmallAndUnsortedInputs() {
        #expect(UploadStatisticsMath.percentile(0.95, of: []) == nil)
        #expect(UploadStatisticsMath.percentile(0.95, of: [4]) == 4)
        #expect(UploadStatisticsMath.percentile(0.95, of: [9, 1, 5]) == 9)
        #expect(UploadStatisticsMath.percentile(0.5, of: [9, 1, 5, 3]) == 3)
    }
}

struct UploadStatisticsLedgerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86400

    func sample(daysAgo: Double, duration: Double, bytes: Int64 = 100, error: String? = nil) -> UploadStatisticsSample {
        UploadStatisticsSample(date: now.addingTimeInterval(-daysAgo * day), duration: duration, bytes: bytes, succeeded: error == nil, error: error)
    }

    @Test func summarisesAllTimeTotals() {
        var ledger = UploaderStatisticsLedger(name: "Zipline")
        ledger.record(sample(daysAgo: 40, duration: 1, bytes: 1000))
        ledger.record(sample(daysAgo: 35, duration: 0, error: "Timed out"))
        ledger.record(sample(daysAgo: 2, duration: 3, bytes: 500))
        ledger.record(sample(daysAgo: 1, duration: 2, bytes: 250))

        let summary = ledger.summary(in: .allTime, now: now)
        #expect(summary.uploads == 3)
        #expect(summary.failures == 1)
        #expect(summary.attempts == 4)
        #expect(summary.bytes == 1750)
        #expect(summary.averageDuration == 2)
        #expect(summary.p95Duration == 3)
        #expect(summary.failureRate == 0.25)
        #expect(summary.lastSuccess == now.addingTimeInterval(-day))
        #expect(summary.lastFailure == now.addingTimeInterval(-35 * day))
        #expect(summary.lastError == "Timed out")
    }

    @Test func restrictsTheRecentWindowToThirtyDays() {
        var ledger = UploaderStatisticsLedger(name: "S3")
        ledger.record(sample(daysAgo: 31, duration: 10, bytes: 9000))
        ledger.record(sample(daysAgo: 29, duration: 2, bytes: 200))
        ledger.record(sample(daysAgo: 3, duration: 0, error: "503"))
        ledger.record(sample(daysAgo: 1, duration: 4, bytes: 400))

        let recent = ledger.summary(in: .last30Days, now: now)
        #expect(recent.uploads == 2)
        #expect(recent.failures == 1)
        #expect(recent.bytes == 600)
        #expect(recent.averageDuration == 3)
        #expect(recent.p95Duration == 4)
        #expect(recent.failureRate.map { abs($0 - 1.0 / 3.0) < 0.0001 } == true)
        #expect(recent.lastError == "503")

        let allTime = ledger.summary(in: .allTime, now: now)
        #expect(allTime.uploads == 3)
        #expect(allTime.bytes == 9600)
    }

    @Test func anEmptyWindowHasNoRatesOrDurations() {
        var ledger = UploaderStatisticsLedger(name: "Old")
        ledger.record(sample(daysAgo: 90, duration: 1))
        let recent = ledger.summary(in: .last30Days, now: now)
        #expect(recent.attempts == 0)
        #expect(recent.failureRate == nil)
        #expect(recent.averageDuration == nil)
        #expect(recent.p95Duration == nil)
        #expect(recent.lastSuccess == nil)
    }

    @Test func capsTheRetainedSamplesButKeepsExactTotals() {
        var ledger = UploaderStatisticsLedger(name: "Busy")
        for index in 0 ..< 12 {
            ledger.record(sample(daysAgo: Double(12 - index), duration: Double(index)), limit: 5)
        }
        #expect(ledger.samples.count == 5)
        #expect(ledger.samples.first?.duration == 7)
        #expect(ledger.totals.successes == 12)
        #expect(ledger.summary(in: .allTime, now: now).averageDuration == 5.5)
    }

    @Test func keepsTheNewestFailureEvenWhenRecordedOutOfOrder() {
        var totals = UploadStatisticsTotals()
        totals.add(sample(daysAgo: 1, duration: 0, error: "new"))
        totals.add(sample(daysAgo: 5, duration: 0, error: "old"))
        #expect(totals.lastError == "new")
        #expect(totals.failures == 2)
    }
}

struct UploadStatisticsDatabaseTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func recordsPerUploaderAndResets() {
        var database = UploadStatisticsDatabase()
        let ok = UploadStatisticsSample(date: now, duration: 1, bytes: 10, succeeded: true)
        database.record(ok, uploader: "a", name: "Alpha")
        database.record(ok, uploader: "b", name: "Beta")
        database.record(ok, uploader: "a", name: "Alpha renamed")
        #expect(database.ledgers["a"]?.totals.successes == 2)
        #expect(database.ledgers["a"]?.name == "Alpha renamed")
        #expect(database.sortedKeys == ["a", "b"])
        database.reset("a")
        #expect(database.ledgers.keys.sorted() == ["b"])
        database.reset()
        #expect(database.ledgers.isEmpty)
    }

    @Test func dropsTheStalestUploadersBeyondTheLimit() {
        var database = UploadStatisticsDatabase()
        for index in 0 ... UploadStatisticsDatabase.ledgerLimit {
            let sample = UploadStatisticsSample(date: now.addingTimeInterval(Double(index)), duration: 1, bytes: 1, succeeded: true)
            database.record(sample, uploader: "u\(index)", name: "U\(index)")
        }
        #expect(database.ledgers.count == UploadStatisticsDatabase.ledgerLimit)
        #expect(database.ledgers["u0"] == nil)
        #expect(database.ledgers["u\(UploadStatisticsDatabase.ledgerLimit)"] != nil)
    }

    @Test func rendersCSVWithBothWindowsAndEscapedFields() {
        var database = UploadStatisticsDatabase()
        database.record(UploadStatisticsSample(date: now, duration: 1.5, bytes: 2048, succeeded: true), uploader: "a", name: "My, \"Server\"")
        database.record(UploadStatisticsSample(date: now, duration: 0, bytes: 0, succeeded: false, error: "Bad\nGateway"), uploader: "a", name: "My, \"Server\"")
        let lines = UploadStatisticsCSV.render(database, now: now).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == Substring(UploadStatisticsCSV.header.joined(separator: ",")))
        let csv = UploadStatisticsCSV.render(database, now: now)
        #expect(csv.contains("\"My, \"\"Server\"\"\",allTime,1,1,0.5000,2048,1.500,1.500,"))
        #expect(csv.contains("\"My, \"\"Server\"\"\",last30Days,1,1,0.5000,2048,1.500,1.500,"))
        #expect(csv.contains("\"Bad\nGateway\""))
        #expect(csv.hasSuffix("\n"))
    }

    @Test func roundTripsThroughJSON() throws {
        var database = UploadStatisticsDatabase()
        database.record(UploadStatisticsSample(date: now, duration: 2, bytes: 5, succeeded: true), uploader: "a", name: "A")
        let data = try JSONEncoder().encode(database)
        #expect(try JSONDecoder().decode(UploadStatisticsDatabase.self, from: data) == database)
    }
}

@MainActor
struct UploadStatisticsStoreTests {
    @Test func persistsToItsFileAndReloads() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "stats.json")
        let store = UploadStatisticsStore(fileURL: url)
        store.record(UploadStatisticsSample(date: Date(), duration: 1, bytes: 3, succeeded: true), uploader: "a", name: "A")
        let reloaded = UploadStatisticsStore(fileURL: url)
        #expect(reloaded.ledger(for: "a")?.totals.bytes == 3)
        reloaded.reset()
        #expect(UploadStatisticsStore(fileURL: url).database.ledgers.isEmpty)
    }

    @Test func theSharedStoreDoesNotPersistDuringTests() {
        #expect(UploadStatisticsStore.isPersistent == false)
        #expect(UploadStatisticsStore.shared.fileURL == nil)
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct UploadStatisticsRecordingTests {
        let spy = UploadEnvironmentSpy()
        let store = UploadStatisticsStore(fileURL: nil)

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            UploadCoordinator.environment = spy
            UploadStatistics.store = store
            StubURLProtocol.reset { request in
                switch request.url.host() {
                case "ok.example.com":
                    StubResponse(body: Data(#"{"url": "https://cdn.example.com/a.png"}"#.utf8))
                default:
                    StubResponse(status: 404, body: Data("missing".utf8))
                }
            }
        }

        func finish() {
            UploadCoordinator.environment = LiveUploadEnvironment()
            UploadStatistics.store = .shared
        }

        @Test func recordsSuccessesAndFailuresFromThePipeline() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let good = TestUploaders.http(name: "good", host: "ok.example.com")
            let bad = TestUploaders.http(name: "bad", host: "gone.example.com")
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(good), .custom(bad)], localFileURL: nil)

            let goodLedger = try #require(store.ledger(for: good.id.uuidString))
            #expect(goodLedger.name == "good")
            #expect(goodLedger.totals.successes == 1)
            #expect(goodLedger.totals.bytes == Int64(TestUploaders.png.count))
            let badLedger = try #require(store.ledger(for: bad.id.uuidString))
            #expect(badLedger.totals.failures == 1)
            #expect(badLedger.totals.lastError?.contains("404") == true)
        }
    }
}
