import Combine
import Defaults
import SwiftUI

enum ToastUploadState: Equatable {
    case none
    case uploading(Double)
    case uploaded
    case failed
}

enum UploadUndo {
    static let duration: TimeInterval = 10

    static func deadline(for item: HistoryItem?, now: Date = Date()) -> Date? {
        guard let item, item.canDeleteFromServer, let date = item.date else { return nil }
        let deadline = date.addingTimeInterval(duration)
        return deadline > now && deadline.timeIntervalSince(now) <= duration ? deadline : nil
    }
}

struct ToastMessage: Equatable {
    let title: String
    let message: String
    let symbol: String
    let tint: Color
}

@MainActor
final class ToastModel: ObservableObject {
    let fileURL: URL?
    let isImage: Bool
    let message: ToastMessage?
    @Published var thumbnail: NSImage?
    @Published var historyItem: HistoryItem? {
        didSet { undoDeadline = UploadUndo.deadline(for: historyItem) }
    }
    @Published var uploadState: ToastUploadState = .none
    @Published var undoDeadline: Date?
    @Published var isHovering = false
    @Published var isDragging = false
    @Published private(set) var annotation: QuickAnnotateSession?
    @Published var replacedItem: HistoryItem?
    var onDismiss: () -> Void = {}
    var onEdit: () -> Void = {}
    var onHoverChange: (Bool) -> Void = { _ in }
    var onRequestKey: () -> Void = {}
    private var cancellables: Set<AnyCancellable> = []

    init(fileURL: URL, isImage: Bool, thumbnail: NSImage? = nil, historyItem: HistoryItem? = nil) {
        self.fileURL = fileURL
        self.isImage = isImage
        self.thumbnail = thumbnail
        self.historyItem = historyItem
        message = nil
        uploadState = historyItem == nil ? .none : .uploaded
        undoDeadline = UploadUndo.deadline(for: historyItem)
    }

    init(message: ToastMessage) {
        fileURL = nil
        isImage = false
        self.message = message
    }

    var fileName: String {
        fileURL?.lastPathComponent ?? message?.title ?? ""
    }

    var kind: PostCapture.Kind {
        isImage || fileURL.map { HistoryItemKind(fileExtension: $0.pathExtension) == .image } == true ? .image : .video
    }

    var isAwaitingUpload: Bool {
        if case .uploading = uploadState { return true }
        return false
    }

    var canUndo: Bool {
        undoDeadline.map { $0 > Date() } ?? false
    }

    var isAnnotating: Bool {
        annotation != nil
    }

    var canAnnotate: Bool {
        guard message == nil, isImage, !isAwaitingUpload, let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    var holdsOpen: Bool {
        isHovering || isAwaitingUpload || isAnnotating || replacedItem != nil
    }

    func beginAnnotating() {
        guard annotation == nil, canAnnotate, let fileURL, let session = QuickAnnotateSession(fileURL: fileURL) else { return }
        replacedItem = nil
        annotation = session
        onRequestKey()
    }

    func cancelAnnotating() {
        annotation = nil
    }

    func finishAnnotating() async {
        guard let session = annotation, let fileURL else { return }
        do {
            let saved = try session.save()
            annotation = nil
            guard saved else { return }
            ThumbnailCache.shared.removeImages(forFile: fileURL)
            if let refreshed = await ThumbnailCache.shared.image(for: ThumbnailKey.forFile(fileURL, pointSize: 64)) {
                thumbnail = refreshed
            }
            if let previous = historyItem {
                await replaceUpload(of: previous, with: fileURL)
            }
        } catch {
            annotation = nil
            Log.app.error("Saving quick annotations failed: \(error.localizedDescription, privacy: .public)")
            ToastController.showMessage(title: "Couldn’t save the annotations".localized(), message: error.localizedDescription, symbol: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func replaceUpload(of previous: HistoryItem, with fileURL: URL) async {
        followUpload(resolvesExplicitly: true)
        var redactedURL: URL?
        switch await Redactor.prepareUpload(of: fileURL) {
        case .unchanged:
            break
        case let .redacted(url):
            redactedURL = url
        case .failed:
            resolveUpload()
            return
        }
        let localFileURL = previous.localFileURL == nil ? nil : fileURL
        await UploadCoordinator.upload(fileURL: redactedURL ?? fileURL, target: UploadCoordinator.target(for: previous), localFileURL: localFileURL)
        if let redactedURL {
            Redactor.discard(redactedURL)
        }
        resolveUpload()
        guard let replacement = historyItem, replacement != previous else { return }
        Defaults[.uploadHistory] = UploadReplacement.history(Defaults[.uploadHistory], replacing: previous, with: replacement)
        if UploadReplacement.offersServerDeletion(of: previous, replacedBy: replacement) {
            replacedItem = previous
        }
    }

    func deleteReplacedUpload() {
        guard let replacedItem else { return }
        self.replacedItem = nil
        Task { @MainActor in
            await HistoryActions.deleteFromServer(replacedItem, announcement: "Deleted the previous upload".localized())
        }
    }

    func followUpload(_ manager: UploadManager = .shared, resolvesExplicitly: Bool = false) {
        uploadState = .uploading(0)
        manager.$activity
            .sink { [weak self] activity in
                self?.apply(activity, manager: manager, resolvesExplicitly: resolvesExplicitly)
            }
            .store(in: &cancellables)
    }

    func resolveUpload(_ manager: UploadManager = .shared) {
        guard isAwaitingUpload else { return }
        cancellables.removeAll()
        if let item = matchingCompletedItem(manager) {
            historyItem = item
            uploadState = .uploaded
        } else {
            uploadState = .failed
        }
    }

    func waitUntilSettled() async {
        for await state in $uploadState.values {
            if case .uploading = state { continue }
            return
        }
    }

    private func matchingCompletedItem(_ manager: UploadManager) -> HistoryItem? {
        guard let item = manager.recentlyCompletedItem(within: 3), item.localPath == nil || item.localPath == fileURL?.path else { return nil }
        return item
    }

    private func apply(_ activity: UploadActivity, manager: UploadManager, resolvesExplicitly: Bool) {
        guard isAwaitingUpload else { return }
        switch activity {
        case let .uploading(progress):
            uploadState = .uploading(progress)
        case .finished, .idle:
            guard !resolvesExplicitly else { return }
            if let item = matchingCompletedItem(manager) {
                historyItem = item
                uploadState = .uploaded
            } else if !manager.isUploading {
                uploadState = .failed
            }
        }
    }
}
