import BezelNotification
import Defaults
import Foundation
import Network

struct QueuedUpload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let fileName: String
    let destination: UploadDestination
    let destinationName: String
    let localPath: String?
    let createdAt: Date
    var attempts: Int
    var lastError: String?
    var nextAttemptAt: Date
    var isPaused: Bool
}

@MainActor
final class UploadQueue: ObservableObject {
    typealias Perform = @MainActor (URL, UploadDestination) async throws -> UploadOutcome
    typealias Completion = @MainActor (QueuedUpload, UploadOutcome) -> Void

    static let maxAttempts = 8
    static let metadataName = "item.json"

    static let shared = UploadQueue(
        directory: defaultDirectory,
        perform: { fileURL, destination in
            guard let target = UploadCoordinator.target(for: destination) else { throw UploadFailure.missingUploader }
            return try await UploadService.upload(fileURL: fileURL, to: target)
        },
        onSuccess: { item, outcome in
            UploadCoordinator.record(outcome, localFileURL: item.localPath.map { URL(fileURLWithPath: $0) })
            UploadCoordinator.deliver(outcome.url)
            BezelNotification.show(messageText: "Queued upload finished".localized(), icon: ToastIcon)
        }
    )

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "ishare/UploadQueue", directoryHint: .isDirectory)
    }

    @Published private(set) var items: [QueuedUpload] = []
    let directory: URL
    private let perform: Perform
    private let onSuccess: Completion
    private var isProcessing = false
    private var schedulerTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    init(directory: URL, perform: @escaping Perform, onSuccess: @escaping Completion) {
        self.directory = directory
        self.perform = perform
        self.onSuccess = onSuccess
        load()
    }

    static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        min(30 * pow(2, Double(max(attempts - 1, 0))), 3600)
    }

    func fileURL(for item: QueuedUpload) -> URL {
        itemDirectory(item.id).appending(path: item.fileName, directoryHint: .notDirectory)
    }

    private func itemDirectory(_ id: UUID) -> URL {
        directory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func load() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: Self.metadataName)) else { return nil }
            return try? decoder.decode(QueuedUpload.self, from: data)
        }
        .filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func enqueue(fileURL: URL, target: UploadTarget, localPath: String?, error: any Error, now: Date = .init()) throws -> QueuedUpload {
        let item = QueuedUpload(
            id: UUID(), fileName: fileURL.lastPathComponent, destination: target.destination, destinationName: target.displayName,
            localPath: localPath, createdAt: now, attempts: 1, lastError: error.localizedDescription,
            nextAttemptAt: now.addingTimeInterval(Self.backoff(afterAttempts: 1)), isPaused: false
        )
        try FileManager.default.createDirectory(at: itemDirectory(item.id), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fileURL, to: self.fileURL(for: item))
        try persist(item)
        items.append(item)
        scheduleNext()
        return item
    }

    func discard(_ id: UUID) {
        try? FileManager.default.removeItem(at: itemDirectory(id))
        items.removeAll { $0.id == id }
    }

    func discardAll() {
        items.map(\.id).forEach(discard)
    }

    func retry(_ id: UUID, now: Date = .init()) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        await attempt(item, now: now)
        scheduleNext()
    }

    func retryDue(now: Date = .init(), includeWaiting: Bool = false) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer {
            isProcessing = false
            scheduleNext()
        }
        let due = items.filter { !$0.isPaused && (includeWaiting || $0.nextAttemptAt <= now) }
        for item in due {
            await attempt(item, now: now)
        }
    }

    func retryAll() async {
        for index in items.indices {
            items[index].isPaused = false
        }
        await retryDue(includeWaiting: true)
    }

    private func attempt(_ item: QueuedUpload, now: Date) async {
        do {
            let outcome = try await perform(fileURL(for: item), item.destination)
            discard(item.id)
            onSuccess(item, outcome)
        } catch {
            var updated = item
            updated.attempts += 1
            updated.lastError = error.localizedDescription
            updated.nextAttemptAt = now.addingTimeInterval(Self.backoff(afterAttempts: updated.attempts))
            let retryable = (error as? UploadFailure)?.isRetryable ?? false
            updated.isPaused = !retryable || updated.attempts >= Self.maxAttempts
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index] = updated
            try? persist(updated)
        }
    }

    private func persist(_ item: QueuedUpload) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        try data.write(to: itemDirectory(item.id).appending(path: Self.metadataName), options: .atomic)
    }

    func start() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                self?.networkChanged(available: available)
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.adrian.ishare.upload-queue.network"))
        pathMonitor = monitor
        scheduleNext()
        Task { await retryDue() }
    }

    private func networkChanged(available: Bool) {
        let becameAvailable = available && !isNetworkAvailable
        isNetworkAvailable = available
        guard becameAvailable, !items.isEmpty else { return }
        Task { await retryDue(includeWaiting: true) }
    }

    private func scheduleNext() {
        schedulerTask?.cancel()
        guard pathMonitor != nil, let next = items.filter({ !$0.isPaused }).map(\.nextAttemptAt).min() else { return }
        let delay = max(next.timeIntervalSinceNow, 1)
        schedulerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.retryDue()
        }
    }
}
