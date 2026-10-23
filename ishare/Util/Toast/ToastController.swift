import Combine
import Defaults
import SwiftUI

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
            if animated, !MotionPreference.reducesMotion, controller.window.isVisible {
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
        model.onRequestKey = { [weak self] in
            guard let self else { return }
            dismissTask?.cancel()
            window.makeKeyAndOrderFront(nil)
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
        model.$annotation
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleDismiss() }
            .store(in: &cancellables)
        model.$replacedItem
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleDismiss() }
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
        guard !model.holdsOpen else { return }
        let undoRemaining = model.undoDeadline.map { max($0.timeIntervalSinceNow, 0) } ?? 0
        let timeout = max(Defaults[.toastTimeout], minimumTimeout, undoRemaining)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled, !model.holdsOpen else { return }

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
