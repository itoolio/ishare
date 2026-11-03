import AppKit
import Defaults
import SwiftUI

enum PointerResultHUDLayout {
    static let size = CGSize(width: 236, height: 60)
    static let offset: CGFloat = 18

    static func frame(near pointer: CGPoint, in visible: CGRect) -> CGRect {
        var origin = CGPoint(x: pointer.x + offset, y: pointer.y - offset - size.height)
        if origin.x + size.width > visible.maxX { origin.x = pointer.x - offset - size.width }
        if origin.y < visible.minY { origin.y = pointer.y + offset }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}

@MainActor
final class PointerResultHUD {
    static let lifetime: Duration = .seconds(6)
    private static var current: PointerResultHUD?

    private let model: ToastModel
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var isHovered = false

    private init(model: ToastModel) {
        self.model = model
    }

    static func present(_ model: ToastModel) async {
        current?.finish()
        let hud = PointerResultHUD(model: model)
        current = hud
        await hud.run()
        if current === hud { current = nil }
    }

    private func run() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
            scheduleExpiry()
        }
    }

    private func show() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let frame = PointerResultHUDLayout.frame(near: pointer, in: screen?.visibleFrame ?? .zero)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PointerResultHUDView(model: model, act: { [weak self] action in self?.perform(action) }, hover: { [weak self] in self?.hovered($0) }))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hovered(_ inside: Bool) {
        isHovered = inside
        if inside {
            expiry?.cancel()
        } else {
            scheduleExpiry(after: .seconds(1.5))
        }
    }

    private func scheduleExpiry(after delay: Duration = lifetime) {
        expiry?.cancel()
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !isHovered else { return }
            finish()
        }
    }

    enum Action {
        case copy, edit, upload, delete
    }

    private func perform(_ action: Action) {
        guard let fileURL = model.fileURL else { return finish() }
        switch action {
        case .copy:
            if let item = model.historyItem {
                HistoryActions.copyURL(item)
            } else {
                PostCapture.copyToClipboard(fileURL, kind: .image)
            }
        case .edit:
            Task { @MainActor in _ = await ImageEditor.edit(fileURL: fileURL) }
        case .upload:
            Task { @MainActor in _ = await UploadCoordinator.upload(fileURL: fileURL, localFileURL: fileURL) }
        case .delete:
            if let item = model.historyItem {
                HistoryActions.removeFromHistory(item)
            }
            NSWorkspace.shared.recycle([fileURL])
        }
        finish()
    }

    private func finish() {
        expiry?.cancel()
        panel?.orderOut(nil)
        panel = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

struct PointerResultHUDView: View {
    @ObservedObject var model: ToastModel
    let act: (PointerResultHUD.Action) -> Void
    let hover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let thumbnail = model.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            button("doc.on.doc", "Copy", .copy)
            if model.isImage {
                button("pencil.tip.crop.circle", "Edit", .edit)
            }
            if model.historyItem == nil {
                button("arrow.up.circle", "Upload", .upload)
            }
            button("trash", "Delete", .delete)
        }
        .padding(.horizontal, 10)
        .frame(width: PointerResultHUDLayout.size.width, height: PointerResultHUDLayout.size.height)
        .adaptiveGlass(cornerRadius: 14)
        .onHover(perform: hover)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pointerHUD")
    }

    private func button(_ symbol: String, _ title: String, _ action: PointerResultHUD.Action) -> some View {
        Button {
            act(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel(title.localized())
    }
}
