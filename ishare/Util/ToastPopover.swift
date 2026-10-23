import AVFoundation
import Combine
import Defaults
import SwiftUI
import UniformTypeIdentifiers

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
    var onDismiss: () -> Void = {}
    var onEdit: () -> Void = {}
    var onHoverChange: (Bool) -> Void = { _ in }
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

struct ToastCardView: View {
    static let width: CGFloat = 384

    @ObservedObject var model: ToastModel

    var body: some View {
        ToastCardContent(model: model)
            .menuAppearance(appliesToWindow: false)
    }
}

private struct ToastCardContent: View {
    @ObservedObject var model: ToastModel
    @Default(.saveToDisk) var saveToDisk
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.message?.title ?? model.fileName)
                        .font(.system(size: 13, weight: Font.Weight.semibold.emphasized(contrast)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 18)
                }
                detail
                if model.fileURL != nil {
                    actions
                }
            }
        }
        .padding(12)
        .frame(width: ToastCardView.width, alignment: .leading)
        .overlay(alignment: .topTrailing) { dismissButton }
        .adaptiveGlass(cornerRadius: 18)
        .opacity(model.isDragging ? 0.3 : 1)
        .onHover { hovering in
            model.isHovering = hovering
            model.onHoverChange(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast.card")
    }

    @ViewBuilder
    private var leading: some View {
        if let message = model.message {
            Image(systemName: message.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(message.tint)
                .frame(width: 40, height: 40)
        } else {
            thumbnail
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: model.isImage ? "photo" : "film")
                    .foregroundStyle(.secondary)
            }
            if model.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .onDrag {
            model.isDragging = true
            guard let url = model.fileURL else { return NSItemProvider() }
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = url.lastPathComponent
            return provider
        }
        .onTapGesture {
            if saveToDisk, let url = model.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            model.onDismiss()
        }
        .help("Drag to share or click to show in Finder".localized())
    }

    @ViewBuilder
    private var detail: some View {
        if let message = model.message {
            Text(message.message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        } else {
            switch model.uploadState {
            case let .uploading(progress):
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.menuAccent)
                        .controlSize(.small)
                    Text(String(format: "Uploading… %d%%".localized(), Int((progress * 100).rounded())))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("toast.progress")
            case .failed:
                Label("Upload failed".localized(), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            case .uploaded, .none:
                if let url = model.historyItem.flatMap({ $0.preferredURL?.absoluteString ?? $0.fileUrl }) {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("toast.url")
                } else {
                    Text(saveToDisk ? "Saved to disk".localized() : "Captured".localized())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ToastActionButton(symbol: "doc.on.doc", title: "Copy", identifier: "toast.copy") { copy() }
            ToastActionButton(symbol: "arrow.up.forward.app", title: "Open", iconOnly: model.canUndo, identifier: "toast.open") { open() }
                .disabled(model.historyItem == nil && !fileExists)
            if model.isImage {
                ToastActionButton(symbol: "pencil.tip.crop.circle", title: "Edit", iconOnly: model.canUndo, identifier: "toast.edit") { model.onEdit() }
            }
            ShareActionButton(items: shareItems, iconOnly: true, identifier: "toast.share")
            if hasDeleteOptions {
                deleteMenu
            }
            if model.canUndo, let item = model.historyItem {
                ToastActionButton(symbol: "arrow.uturn.backward", title: "Undo", identifier: "toast.undo") {
                    model.onDismiss()
                    Task { @MainActor in
                        await HistoryActions.undoUpload(item)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func shareItems() -> [Any] {
        if let url = model.fileURL, FileManager.default.fileExists(atPath: url.path) {
            return [url]
        }
        return model.historyItem.map(SharePicker.items(for:)) ?? []
    }

    private var deleteMenu: some View {
        Menu {
            if let item = model.historyItem {
                if item.canDeleteFromServer {
                    Button("Delete from Server…".localized(), role: .destructive) {
                        model.onDismiss()
                        HistoryActions.confirmDeleteFromServer(item)
                    }
                }
                Button("Remove from History".localized()) {
                    HistoryActions.removeFromHistory(item)
                    model.historyItem = nil
                    model.uploadState = .none
                }
            }
            if canTrashFile, let url = model.fileURL {
                Button("Move to Trash".localized(), role: .destructive) {
                    NSWorkspace.shared.recycle([url])
                    model.onDismiss()
                }
            }
        } label: {
            ToastActionLabel(symbol: "trash", title: "Delete", iconOnly: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Delete".localized())
        .accessibilityIdentifier("toast.delete")
    }

    private var dismissButton: some View {
        Button {
            model.onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(model.isHovering ? contrast.hoverFillOpacity : contrast.iconFillOpacity)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .help("Dismiss".localized())
        .accessibilityLabel("Dismiss".localized())
        .accessibilityIdentifier("toast.dismiss")
    }

    private var fileExists: Bool {
        model.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private var canTrashFile: Bool {
        saveToDisk && fileExists
    }

    private var hasDeleteOptions: Bool {
        model.historyItem != nil || canTrashFile
    }

    private func copy() {
        if let item = model.historyItem {
            HistoryActions.copyURL(item)
        } else if let url = model.fileURL {
            PostCapture.copyToClipboard(url, kind: model.kind)
        }
    }

    private func open() {
        if let item = model.historyItem {
            HistoryActions.open(item)
        } else if let url = model.fileURL {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ToastActionLabel: View {
    let symbol: String
    let title: String
    var iconOnly = false
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Group {
            if iconOnly {
                Image(systemName: symbol)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(contrast.fillOpacity)))
                    .overlay { if contrast.isHigh { Circle().strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1) } }
                    .contentShape(Circle())
            } else {
                Label(title.localized(), systemImage: symbol)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.primary.opacity(contrast.fillOpacity)))
                    .overlay { if contrast.isHigh { Capsule().strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1) } }
                    .contentShape(Capsule())
            }
        }
        .font(.system(size: 11, weight: Font.Weight.medium.emphasized(contrast)))
        .fixedSize()
    }
}

struct ToastActionButton: View {
    let symbol: String
    let title: String
    var iconOnly = false
    let identifier: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ToastActionLabel(symbol: symbol, title: title, iconOnly: iconOnly)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
        .accessibilityIdentifier(identifier)
    }
}

final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ToastController {
    static let margin: CGFloat = 16
    static let spacing: CGFloat = 10
    private static var visible: [ToastController] = []
    private static var screenFrame: CGRect?

    private let window: ToastPanel
    private let hosting: NSHostingView<ToastCardView>
    let model: ToastModel
    private var continuation: CheckedContinuation<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let minimumTimeout: Double

    private init(model: ToastModel, minimumTimeout: Double = 0) {
        self.model = model
        self.minimumTimeout = minimumTimeout
        hosting = NSHostingView(rootView: ToastCardView(model: model))
        window = ToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: ToastCardView.width, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hosting
    }

    var contentSize: NSSize {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        return NSSize(width: ToastCardView.width, height: max(size.height, 56))
    }

    static func show(model: ToastModel, minimumTimeout: Double = 0) async {
        let controller = ToastController(model: model, minimumTimeout: minimumTimeout)
        screenFrame = ToastPlacement.currentScreenFrame()
        visible.insert(controller, at: 0)
        await controller.present()
        visible.removeAll { $0 === controller }
        if visible.isEmpty {
            screenFrame = nil
        }
        relayout(animated: true)
    }

    static func showMessage(title: String, message: String, symbol: String, tint: Color) {
        Task { @MainActor in
            await show(model: ToastModel(message: ToastMessage(title: title, message: message, symbol: symbol, tint: tint)), minimumTimeout: 6)
        }
    }

    static func targetFrames(for heights: [CGFloat], in screen: CGRect, corner: ToastCorner = .topRight) -> [CGRect] {
        ToastPlacement.frames(for: heights, width: ToastCardView.width, in: screen, corner: corner, margin: margin, spacing: spacing)
    }

    static func relayout(animated: Bool) {
        let screen = screenFrame ?? ToastPlacement.currentScreenFrame()
        let frames = targetFrames(for: visible.map(\.contentSize.height), in: screen, corner: Defaults[.toastCorner])
        for (controller, frame) in zip(visible, frames) {
            if animated, controller.window.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    controller.window.animator().setFrame(frame, display: true)
                }
            } else {
                controller.window.setFrame(frame, display: true)
            }
        }
    }

    private func present() async {
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onEdit = { [weak self] in
            guard let self, let url = model.fileURL else { return }
            dismiss()
            Task { @MainActor in
                await ImageEditor.editAsNewCapture(sourceURL: url)
            }
        }
        model.onHoverChange = { [weak self] hovering in
            guard let self else { return }
            if hovering {
                dismissTask?.cancel()
            } else {
                scheduleDismiss()
            }
        }
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self != nil else { return }
                ToastController.relayout(animated: true)
            }
            .store(in: &cancellables)
        model.$uploadState
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                guard let self, state != .none, !isAwaitingUpload(state) else { return }
                scheduleDismiss()
            }
            .store(in: &cancellables)
        model.$undoDeadline
            .removeDuplicates()
            .sink { [weak self] deadline in
                self?.expireUndo(at: deadline)
            }
            .store(in: &cancellables)
        window.appearance = Defaults[.menuTheme].appearance
        window.alphaValue = 0
        Self.relayout(animated: true)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }, completionHandler: nil)
        scheduleDismiss()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func isAwaitingUpload(_ state: ToastUploadState) -> Bool {
        if case .uploading = state { return true }
        return false
    }

    private func expireUndo(at deadline: Date?) {
        undoTask?.cancel()
        guard let deadline else { return }
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
            guard let self, !Task.isCancelled else { return }
            model.undoDeadline = nil
        }
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard !model.isHovering, !model.isAwaitingUpload else { return }
        let undoRemaining = model.undoDeadline.map { max($0.timeIntervalSinceNow, 0) } ?? 0
        let timeout = max(Defaults[.toastTimeout], minimumTimeout, undoRemaining)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled, !model.isHovering, !model.isAwaitingUpload else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        undoTask?.cancel()
        cancellables.removeAll()
        guard let continuation else { return }
        self.continuation = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [window] in
            Task { @MainActor in
                window.orderOut(nil)
            }
        })
        continuation.resume()
    }
}

@MainActor
func showToast(fileURL: URL) async {
    await showToast(fileURL: fileURL, awaitingUpload: false)
}

@MainActor
func showToast(fileURL: URL, awaitingUpload: Bool) async {
    let model = makeToastModel(fileURL: fileURL, awaitingUpload: awaitingUpload)
    if awaitingUpload {
        model.followUpload()
    }
    await presentToast(model)
}

@MainActor
func beginUploadToast(fileURL: URL) -> (model: ToastModel, presentation: Task<Void, Never>) {
    let model = makeToastModel(fileURL: fileURL, awaitingUpload: true)
    model.followUpload(resolvesExplicitly: true)
    return (model, Task { @MainActor in await presentToast(model) })
}

@MainActor
private func makeToastModel(fileURL: URL, awaitingUpload: Bool) -> ToastModel {
    let isImage = HistoryItemKind(fileExtension: fileURL.pathExtension) == .image && fileURL.pathExtension.lowercased() != "gif"
    let item = awaitingUpload ? nil : uploadedItem(for: fileURL)
    return ToastModel(fileURL: fileURL, isImage: isImage, historyItem: item)
}

@MainActor
private func presentToast(_ model: ToastModel) async {
    if let fileURL = model.fileURL {
        let key = ThumbnailKey.forFile(fileURL, pointSize: 64)
        var thumbnail = ThumbnailCache.shared.cachedImage(for: key)
        if thumbnail == nil {
            thumbnail = await ThumbnailCache.shared.image(for: key)
        }
        model.thumbnail = thumbnail ?? NSWorkspace.shared.icon(forFile: fileURL.path)
    }
    await ResultPresenter.present(model)
}

@MainActor
private func uploadedItem(for fileURL: URL) -> HistoryItem? {
    if let match = Defaults[.uploadHistory].prefix(10).first(where: { $0.localPath == fileURL.path }) {
        return match
    }
    guard let recent = UploadManager.shared.recentlyCompletedItem(within: 3), recent.localPath == nil else { return nil }
    return recent
}

@MainActor
func showToast(fileURL: URL, completion: (@Sendable () -> Void)? = nil) {
    Task { @MainActor in
        await showToast(fileURL: fileURL)
        completion?()
    }
}

func videoThumbnail(for url: URL) async -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 640, height: 640)
    for seconds in [1.0, 0.0] {
        if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
            return NSImage(cgImage: result.image, size: CGSize(width: result.image.width, height: result.image.height))
        }
    }
    return nil
}
