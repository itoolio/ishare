import Alamofire
import Defaults
import Foundation
import IOKit.ps
import ishareCore
import Network

enum HealthCheckOutcome: Equatable, Sendable {
    case skipped(HealthCheckSkipReason)
    case checked(HealthCheckRecord)

    var record: HealthCheckRecord? {
        if case let .checked(record) = self { record } else { nil }
    }
}

enum PowerConditions {
    static func current() -> (level: Int?, onBattery: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, false) }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let level = current.flatMap { value in maximum.map { $0 > 0 ? value * 100 / $0 : value } }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return (level, onBattery)
        }
        return (nil, false)
    }
}

@MainActor
final class NetworkConditions {
    static let shared = NetworkConditions()

    private var monitor: NWPathMonitor?
    private(set) var isConstrained = false
    private(set) var isExpensive = false

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let constrained = path.isConstrained
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isConstrained = constrained
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.adrian.ishare.health-check.network"))
        self.monitor = monitor
    }
}

@MainActor
enum UploaderHealthCheck {
    static let tickInterval: TimeInterval = 3600

    static var clock = MaintenanceClock.system
    static var conditions: @MainActor () -> HealthCheckConditions = {
        let power = PowerConditions.current()
        return HealthCheckConditions(
            batteryLevel: power.level, isOnBattery: power.onBattery, isConstrained: NetworkConditions.shared.isConstrained,
            isExpensive: NetworkConditions.shared.isExpensive
        )
    }
    static var defaultTarget: @MainActor () -> UploadTarget? = { UploadCoordinator.currentTarget() }
    static var reportFailure: @MainActor (HealthCheckRecord) -> Void = { record in
        Task { @MainActor in await announceFailure(record) }
    }
    private static var timer: Timer?
    private static var isRunning = false

    static func key(for target: UploadTarget) -> String {
        target.statisticsKey
    }

    static func record(for target: UploadTarget) -> HealthCheckRecord? {
        Defaults[.uploaderHealthRecords][key(for: target)]
    }

    static func record(forUploaderID id: UUID) -> HealthCheckRecord? {
        Defaults[.uploaderHealthRecords][id.uuidString]
    }

    static func method(for target: UploadTarget) -> HealthCheckMethod? {
        switch target {
        case .imgur:
            return .uploadAndDelete
        case .localNetwork:
            return nil
        case let .custom(uploader):
            switch uploader.kind {
            case .photos: return nil
            case .folder: return .uploadAndDelete
            case .custom: return uploader.supportsAutoDelete ? .uploadAndDelete : .probe
            default: return .uploadAndDelete
            }
        }
    }

    @discardableResult
    static func run(forced: Bool = false) async -> HealthCheckOutcome {
        guard !isRunning else { return .skipped(.notDue) }
        let now = clock.now()
        if let reason = HealthCheckPlanner.skipReason(
            frequency: Defaults[.uploaderHealthCheckFrequency], lastCheck: Defaults[.uploaderHealthLastCheck], conditions: conditions(), now: now,
            forced: forced
        ) {
            return .skipped(reason)
        }
        guard let target = defaultTarget() else { return .skipped(.noUploader) }
        guard method(for: target) != nil else { return .skipped(.unsupportedUploader) }
        isRunning = true
        defer { isRunning = false }
        let record = await check(target)
        Defaults[.uploaderHealthRecords][key(for: target)] = record
        Defaults[.uploaderHealthLastCheck] = record.date
        if !record.succeeded {
            Log.upload.error("Health check of \(target.displayName, privacy: .public) failed: \(record.message ?? "", privacy: .public)")
            reportFailure(record)
        }
        return .checked(record)
    }

    static func check(_ target: UploadTarget) async -> HealthCheckRecord {
        let method = method(for: target) ?? .upload
        do {
            if method == .probe, case let .custom(uploader) = target {
                try await probe(uploader)
                return HealthCheckRecord(date: clock.now(), succeeded: true, uploaderName: target.displayName, method: .probe)
            }
            let deleted = try await uploadAndDelete(to: target)
            return HealthCheckRecord(date: clock.now(), succeeded: true, uploaderName: target.displayName, method: deleted ? .uploadAndDelete : .upload)
        } catch {
            return HealthCheckRecord(date: clock.now(), succeeded: false, message: error.localizedDescription, uploaderName: target.displayName, method: method)
        }
    }

    static func uploadAndDelete(to target: UploadTarget) async throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-health-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: HealthCheckProbe.fileName)
        try HealthCheckProbe.tinyPNG.write(to: file)
        let outcome = try await UploadService.upload(fileURL: file, to: target)
        let item = HistoryItem(
            fileUrl: outcome.url.absoluteString, deletionUrl: outcome.deletionURL, uploaderId: outcome.uploaderID, s3Key: outcome.s3Key,
            localIdentifier: outcome.localIdentifier
        )
        guard item.hasServerReference else { return false }
        do {
            try await target.uploader.delete(item)
            return true
        } catch {
            Log.upload.error("Deleting the health check upload failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func probeRequest(for uploader: CustomUploader) -> URLRequest? {
        guard let url = URL(string: uploader.requestURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "OPTIONS"
        for (name, value) in uploader.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    static func probe(_ uploader: CustomUploader) async throws {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let request = probeRequest(for: uploader) else { throw UploadFailure.invalidSpecification([.invalidRequestURL]) }
        let response = await UploadService.session.request(request).serializingData(emptyResponseCodes: Set(100 ..< 600)).response
        guard let http = response.response else {
            throw UploadFailure.transport(response.error?.underlyingError?.localizedDescription ?? response.error?.localizedDescription ?? "No response")
        }
        guard http.statusCode < 500 else {
            throw UploadFailure.http(status: http.statusCode, body: response.data.flatMap { String(data: $0, encoding: .utf8) })
        }
    }

    static func failureMessage(_ record: HealthCheckRecord) -> String {
        String(format: "Your default uploader isn't working: %@".localized(), record.message ?? "Unknown error".localized())
    }

    static func announceFailure(_ record: HealthCheckRecord) async {
        await MaintenanceNotifications.post(
            title: record.uploaderName ?? "Uploader Health Check".localized(), body: failureMessage(record), category: ResultNotifier.healthCategory,
            fallbackSymbol: "exclamationmark.triangle.fill"
        )
    }

    static func start() {
        NetworkConditions.shared.start()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { _ in
            Task { @MainActor in await run() }
        }
        timer?.tolerance = 600
        Task {
            try? await Task.sleep(for: .seconds(30))
            await run()
        }
    }

    static func systemDidWake() {
        Task {
            try? await Task.sleep(for: .seconds(20))
            await run()
        }
    }
}
