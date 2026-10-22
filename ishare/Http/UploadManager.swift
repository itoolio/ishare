import AppKit
import Combine
import Defaults
import Foundation

enum UploadActivity: Equatable, Sendable {
    case idle
    case uploading(progress: Double)
    case finished(succeeded: Bool)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }
}

struct UploadTracker: Equatable {
    private(set) var activeUploads = 0
    private(set) var progress: Double = 0
    private var acknowledgedItem: HistoryItem?

    var isActive: Bool { activeUploads > 0 }

    mutating func begin(newestHistoryItem: HistoryItem?) {
        if activeUploads == 0 {
            acknowledgedItem = newestHistoryItem
            progress = 0
        }
        activeUploads += 1
    }

    mutating func update(progress fraction: Double) {
        progress = min(max(fraction, 0), 1)
    }

    mutating func complete(newestHistoryItem: HistoryItem?) -> Bool {
        activeUploads = max(0, activeUploads - 1)
        guard let newestHistoryItem, newestHistoryItem != acknowledgedItem else { return false }
        acknowledgedItem = newestHistoryItem
        return true
    }

    var activity: UploadActivity {
        .uploading(progress: progress)
    }
}

@MainActor
final class UploadManager: ObservableObject {
    static let shared = UploadManager()
    static let resultDisplayDuration: Duration = .seconds(1.4)

    @Published private(set) var activity: UploadActivity = .idle
    @Published private(set) var lastCompletedItem: HistoryItem?
    private(set) var lastCompletedAt: Date?
    private var tracker = UploadTracker()
    private var resetTask: Task<Void, Never>?

    private init() {}

    var isUploading: Bool { tracker.isActive }

    func begin() {
        resetTask?.cancel()
        tracker.begin(newestHistoryItem: Defaults[.uploadHistory].first)
        activity = tracker.activity
    }

    func updateProgress(fraction: Double) {
        guard tracker.isActive else { return }
        tracker.update(progress: fraction)
        activity = tracker.activity
    }

    func uploadCompleted(succeeded reported: Bool? = nil) {
        let newest = Defaults[.uploadHistory].first
        let inferred = tracker.complete(newestHistoryItem: newest)
        let succeeded = reported ?? inferred
        if succeeded {
            lastCompletedItem = newest
            lastCompletedAt = Date()
            SoundPlayer.play(.uploadComplete)
        }
        guard !tracker.isActive else {
            activity = tracker.activity
            return
        }
        activity = .finished(succeeded: succeeded)
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resultDisplayDuration)
            guard let self, !Task.isCancelled, !tracker.isActive else { return }
            activity = .idle
        }
    }

    func recentlyCompletedItem(within interval: TimeInterval = 10) -> HistoryItem? {
        guard let lastCompletedAt, Date().timeIntervalSince(lastCompletedAt) <= interval else { return nil }
        return lastCompletedItem
    }
}
