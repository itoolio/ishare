import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class UploadProgressHUDModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var finished: Bool?
}

enum UploadProgressHUDLayout {
    static let size = CGSize(width: 220, height: 44)
    static let gap: CGFloat = 6

    static func frame(below anchor: CGRect?, on screen: CGRect, visible: CGRect) -> CGRect {
        let origin: CGPoint
        if let anchor {
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        } else {
            origin = CGPoint(x: screen.midX - size.width / 2, y: visible.maxY - gap - size.height)
        }
        let x = min(max(origin.x, screen.minX + gap), screen.maxX - size.width - gap)
        return CGRect(origin: CGPoint(x: x, y: origin.y), size: size)
    }
}

@MainActor
final class UploadProgressHUD {
    static let shared = UploadProgressHUD()
    static let showDelay: Duration = .milliseconds(1200)
    static let finishedDuration: Duration = .seconds(1.2)

    private let model = UploadProgressHUDModel()
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    func activate() {
        guard cancellables.isEmpty else { return }
        UploadManager.shared.$activity
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity in self?.update(activity) }
            .store(in: &cancellables)
    }

    private func update(_ activity: UploadActivity) {
        switch activity {
        case let .uploading(progress):
            hideTask?.cancel()
            model.finished = nil
            model.progress = progress
            guard panel == nil, showTask == nil, Defaults[.showsUploadProgressHUD] else { return }
            showTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.showDelay)
                guard !Task.isCancelled, let self else { return }
                showTask = nil
                if UploadManager.shared.activity.isUploading {
                    show()
                }
            }
        case let .finished(succeeded):
            showTask?.cancel()
            showTask = nil
            guard panel != nil else { return }
            model.progress = 1
            model.finished = succeeded
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.finishedDuration)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        case .idle:
            showTask?.cancel()
            showTask = nil
            hide()
        }
    }

    private func show() {
        let screen = StatusItemController.shared.buttonScreen ?? NSScreen.main
        guard let screen else { return }
        let frame = UploadProgressHUDLayout.frame(below: StatusItemController.shared.buttonScreenFrame, on: screen.frame, visible: screen.visibleFrame)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: UploadProgressHUDView(model: model))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

struct UploadProgressHUDView: View {
    @ObservedObject var model: UploadProgressHUDModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
            Text(verbatim: "\(Int((model.progress * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: UploadProgressHUDLayout.size.width, height: UploadProgressHUDLayout.size.height)
        .adaptiveGlass(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("upload.progressHUD")
    }

    private var title: String {
        switch model.finished {
        case true?: "Uploaded".localized()
        case false?: "Upload failed".localized()
        case nil: "Uploading…".localized()
        }
    }

    private var symbol: String {
        switch model.finished {
        case true?: "checkmark.circle.fill"
        case false?: "xmark.circle.fill"
        case nil: "arrow.up.circle"
        }
    }

    private var tint: Color {
        model.finished == false ? .orange : .accentColor
    }
}
