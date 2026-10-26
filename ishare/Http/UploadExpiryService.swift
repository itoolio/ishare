import AppKit
import Defaults
import Foundation
import ishareCore

@MainActor
struct UploadExpiryRunner {
    typealias Update = @MainActor (HistoryItem, (HistoryItem) -> HistoryItem?) -> Void

    var history: @MainActor () -> [HistoryItem]
    var update: Update
    var delete: @MainActor (HistoryItem) async throws -> Void
    var keepsExpiredItems: Bool
    var clock: MaintenanceClock

    func run() async -> UploadExpirySummary {
        let now = clock.now()
        let due = history().filter { UploadExpiry.isDue($0.expiryState, now: now) }
        var summary = UploadExpirySummary()
        for item in due {
            do {
                try await delete(item)
                summary.deleted += 1
                let keeps = keepsExpiredItems
                update(item) { current in
                    keeps ? current.applying(UploadExpiry.expired(current.expiryState, now: now)) : nil
                }
            } catch {
                summary.failed += 1
                summary.errors.append(error.localizedDescription)
                let message = error.localizedDescription
                update(item) { current in
                    current.applying(UploadExpiry.failed(current.expiryState, error: message, now: now))
                }
            }
        }
        return summary
    }
}

@MainActor
enum UploadExpiryService {
    static let checkInterval: TimeInterval = 3600

    static var clock = MaintenanceClock.system
    private static var timer: Timer?
    private static var isRunning = false

    static func liveRunner() -> UploadExpiryRunner {
        UploadExpiryRunner(
            history: { Defaults[.uploadHistory] },
            update: { item, transform in
                let key = item.storageKey
                var removed: [HistoryItem] = []
                updateUploadHistory { current in
                    guard current.storageKey == key else { return current }
                    let next = transform(current)
                    if next == nil {
                        removed.append(current)
                    }
                    return next
                }
                if !removed.isEmpty {
                    HistorySync.shared.recordDeletion(of: removed)
                }
            },
            delete: { item in try await deleteFromServer(item, uploaders: CustomUploader.allCases) },
            keepsExpiredItems: Defaults[.keepsExpiredUploadsInHistory],
            clock: clock
        )
    }

    static func deleteFromServer(_ item: HistoryItem, uploaders: [CustomUploader]) async throws {
        if let id = item.uploaderId {
            guard let uploader = uploaders.first(where: { $0.id == id }) else { throw UploadFailure.missingUploader }
            try await UploadTarget.custom(uploader).uploader.delete(item)
        } else {
            try await UploadCoordinator.delete(item)
        }
    }

    @discardableResult
    static func runNow(runner: UploadExpiryRunner? = nil) async -> UploadExpirySummary {
        guard !isRunning else { return UploadExpirySummary() }
        isRunning = true
        defer { isRunning = false }
        let summary = await (runner ?? liveRunner()).run()
        Defaults[.uploadExpiryLastRun] = clock.now()
        if !summary.isEmpty {
            Log.upload.info("Auto-delete removed \(summary.deleted) uploads, \(summary.failed) failed")
            announce(summary)
        }
        return summary
    }

    static func summaryMessage(_ summary: UploadExpirySummary) -> String {
        var parts: [String] = []
        if summary.deleted > 0 {
            parts.append(String(format: "Deleted %d expired uploads from the server.".localized(), summary.deleted))
        }
        if summary.failed > 0 {
            parts.append(String(format: "%d expired uploads couldn't be deleted. ishare will try again later.".localized(), summary.failed))
        }
        return parts.joined(separator: " ")
    }

    static func announce(_ summary: UploadExpirySummary) {
        let title = "Expired Uploads".localized()
        let body = summaryMessage(summary)
        Task { @MainActor in
            await MaintenanceNotifications.post(title: title, body: body, category: nil, fallbackSymbol: summary.failed > 0 ? "exclamationmark.triangle.fill" : "trash")
        }
    }

    static func start() {
        Task { await runNow() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            Task { @MainActor in await runNow() }
        }
        timer?.tolerance = 600
    }

    static func systemDidWake() {
        Task { await runNow() }
    }
}
