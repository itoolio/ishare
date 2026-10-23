import Combine
import Foundation
import ishareCore

struct UploadStatisticsSample: Codable, Equatable, Sendable {
    var date: Date
    var duration: TimeInterval
    var bytes: Int64
    var succeeded: Bool
    var error: String?
}

struct UploadStatisticsTotals: Codable, Equatable, Sendable {
    var successes = 0
    var failures = 0
    var bytes: Int64 = 0
    var successDuration: TimeInterval = 0
    var lastSuccess: Date?
    var lastFailure: Date?
    var lastError: String?

    mutating func add(_ sample: UploadStatisticsSample) {
        if sample.succeeded {
            successes += 1
            bytes += sample.bytes
            successDuration += sample.duration
            lastSuccess = max(lastSuccess ?? sample.date, sample.date)
        } else {
            failures += 1
            if lastFailure.map({ sample.date >= $0 }) ?? true {
                lastFailure = sample.date
                lastError = sample.error
            }
        }
    }
}

struct UploaderStatisticsLedger: Codable, Equatable, Sendable {
    static let sampleLimit = 500

    var name: String
    var totals = UploadStatisticsTotals()
    var samples: [UploadStatisticsSample] = []

    mutating func record(_ sample: UploadStatisticsSample, limit: Int = sampleLimit) {
        totals.add(sample)
        samples.append(sample)
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    func summary(in window: UploadStatisticsWindow, now: Date = Date()) -> UploadStatisticsSummary {
        switch window {
        case .allTime:
            return UploadStatisticsSummary(totals: totals, durations: samples.filter(\.succeeded).map(\.duration))
        case .last30Days:
            let start = now.addingTimeInterval(-window.length)
            let recent = samples.filter { $0.date >= start && $0.date <= now }
            return UploadStatisticsSummary(samples: recent)
        }
    }
}

enum UploadStatisticsWindow: String, CaseIterable, Identifiable, Sendable {
    case allTime
    case last30Days

    var id: Self { self }

    var length: TimeInterval {
        switch self {
        case .allTime: .infinity
        case .last30Days: 30 * 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .allTime: "All Time".localized()
        case .last30Days: "Last 30 Days".localized()
        }
    }
}

struct UploadStatisticsSummary: Equatable, Sendable {
    var uploads: Int
    var failures: Int
    var bytes: Int64
    var averageDuration: TimeInterval?
    var p95Duration: TimeInterval?
    var lastSuccess: Date?
    var lastFailure: Date?
    var lastError: String?

    var attempts: Int { uploads + failures }

    var failureRate: Double? {
        attempts == 0 ? nil : Double(failures) / Double(attempts)
    }

    init(totals: UploadStatisticsTotals, durations: [TimeInterval]) {
        uploads = totals.successes
        failures = totals.failures
        bytes = totals.bytes
        averageDuration = totals.successes == 0 ? nil : totals.successDuration / Double(totals.successes)
        p95Duration = UploadStatisticsMath.percentile(0.95, of: durations)
        lastSuccess = totals.lastSuccess
        lastFailure = totals.lastFailure
        lastError = totals.lastError
    }

    init(samples: [UploadStatisticsSample]) {
        var totals = UploadStatisticsTotals()
        samples.forEach { totals.add($0) }
        self.init(totals: totals, durations: samples.filter(\.succeeded).map(\.duration))
    }
}

enum UploadStatisticsMath {
    static func percentile(_ fraction: Double, of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((min(max(fraction, 0), 1) * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

struct UploadStatisticsDatabase: Codable, Equatable, Sendable {
    static let ledgerLimit = 64

    var ledgers: [String: UploaderStatisticsLedger] = [:]

    mutating func record(_ sample: UploadStatisticsSample, uploader key: String, name: String) {
        var ledger = ledgers[key] ?? UploaderStatisticsLedger(name: name)
        ledger.name = name
        ledger.record(sample)
        ledgers[key] = ledger
        trimLedgers()
    }

    mutating func reset(_ key: String? = nil) {
        if let key {
            ledgers[key] = nil
        } else {
            ledgers.removeAll()
        }
    }

    private mutating func trimLedgers() {
        guard ledgers.count > Self.ledgerLimit else { return }
        let stalest = ledgers.sorted { lastActivity($0.value) < lastActivity($1.value) }.prefix(ledgers.count - Self.ledgerLimit)
        stalest.forEach { ledgers[$0.key] = nil }
    }

    private func lastActivity(_ ledger: UploaderStatisticsLedger) -> Date {
        ledger.samples.last?.date ?? .distantPast
    }

    var sortedKeys: [String] {
        ledgers.keys.sorted { (ledgers[$0]?.name ?? $0).localizedStandardCompare(ledgers[$1]?.name ?? $1) == .orderedAscending }
    }
}

enum UploadStatisticsCSV {
    static let header = [
        "uploader", "window", "uploads", "failures", "failure_rate", "total_bytes",
        "average_duration_seconds", "p95_duration_seconds", "last_success", "last_failure", "last_error",
    ]

    static func render(_ database: UploadStatisticsDatabase, now: Date = Date()) -> String {
        let rows = database.sortedKeys.flatMap { key -> [[String]] in
            guard let ledger = database.ledgers[key] else { return [] }
            return UploadStatisticsWindow.allCases.map { window in
                row(name: ledger.name, window: window, summary: ledger.summary(in: window, now: now))
            }
        }
        return ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func row(name: String, window: UploadStatisticsWindow, summary: UploadStatisticsSummary) -> [String] {
        [
            name, window.rawValue, String(summary.uploads), String(summary.failures),
            summary.failureRate.map { String(format: "%.4f", $0) } ?? "",
            String(summary.bytes),
            summary.averageDuration.map { String(format: "%.3f", $0) } ?? "",
            summary.p95Duration.map { String(format: "%.3f", $0) } ?? "",
            summary.lastSuccess.map(timestamp) ?? "",
            summary.lastFailure.map(timestamp) ?? "",
            summary.lastError ?? "",
        ]
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { [",", "\"", "\n", "\r"].contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

@MainActor
final class UploadStatisticsStore: ObservableObject {
    static let shared = UploadStatisticsStore(fileURL: UploadStatisticsStore.isPersistent ? defaultFileURL : nil)

    nonisolated static var isPersistent: Bool {
        !RuntimeEnvironment.isRunningTests && !ScreenshotMode.isActive
    }

    static var defaultFileURL: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "ishare/UploadStatistics.json", directoryHint: .notDirectory)
    }

    @Published private(set) var database: UploadStatisticsDatabase
    let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        database = fileURL.flatMap(Self.load) ?? UploadStatisticsDatabase()
    }

    func record(_ sample: UploadStatisticsSample, uploader key: String, name: String) {
        database.record(sample, uploader: key, name: name)
        persist()
    }

    func reset(_ key: String? = nil) {
        database.reset(key)
        persist()
    }

    func ledger(for key: String) -> UploaderStatisticsLedger? {
        database.ledgers[key]
    }

    var csv: String {
        UploadStatisticsCSV.render(database)
    }

    private static func load(from url: URL) -> UploadStatisticsDatabase? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(UploadStatisticsDatabase.self, from: data)
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(database).write(to: fileURL, options: .atomic)
        } catch {
            Log.upload.error("Couldn't save upload statistics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension UploadTarget {
    var statisticsKey: String {
        switch self {
        case .imgur: "imgur"
        case let .custom(uploader): uploader.id.uuidString
        case .localNetwork: "localNetwork"
        }
    }
}

@MainActor
enum UploadStatistics {
    static var store: UploadStatisticsStore = .shared
    static var clock: () -> Date = Date.init

    static func recordingUpload(
        fileURL: URL, to target: UploadTarget, linkChoice: LinkChoice? = nil,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> UploadOutcome {
        let started = ContinuousClock.now
        do {
            let outcome = try await UploadService.upload(fileURL: fileURL, to: target, linkChoice: linkChoice, progress: progress)
            record(target: target, fileURL: fileURL, elapsed: ContinuousClock.now - started, error: nil)
            return outcome
        } catch {
            record(target: target, fileURL: fileURL, elapsed: ContinuousClock.now - started, error: error)
            throw error
        }
    }

    static func record(target: UploadTarget, fileURL: URL, elapsed: Duration, error: (any Error)?) {
        if let failure = error as? UploadFailure, failure == .cancelled { return }
        let sample = UploadStatisticsSample(
            date: clock(),
            duration: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            bytes: fileSize(of: fileURL),
            succeeded: error == nil,
            error: error?.localizedDescription
        )
        store.record(sample, uploader: target.statisticsKey, name: target.displayName)
        ReviewPrompt.uploadFinished(succeeded: error == nil)
    }

    static func fileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
