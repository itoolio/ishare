import AppKit
import SwiftUI

enum PermissionKind {
    case screenRecording
    case accessibility

    var settingsURL: URL {
        switch self {
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }

    var title: String {
        switch self {
        case .screenRecording: "Allow screen recording"
        case .accessibility: "Allow ishare to scroll for you"
        }
    }

    var instructions: String {
        switch self {
        case .screenRecording: "Drag ishare into the Screen & System Audio Recording list, then turn it on."
        case .accessibility: "Drag ishare into the Accessibility list, then turn it on."
        }
    }

    var isGranted: Bool {
        switch self {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .accessibility: CGPreflightPostEventAccess()
        }
    }

    func request() {
        switch self {
        case .screenRecording: CGRequestScreenCaptureAccess()
        case .accessibility: _ = CGRequestPostEventAccess()
        }
    }
}

@MainActor
final class PermissionGuideModel: ObservableObject {
    let kind: PermissionKind
    @Published var granted = false
    var onClose: () -> Void = {}

    init(kind: PermissionKind) {
        self.kind = kind
        granted = kind.isGranted
    }

    func refresh() {
        granted = kind.isGranted
    }
}

struct PermissionGuideView: View {
    @ObservedObject var model: PermissionGuideModel
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: model.granted ? "checkmark.seal.fill" : "lock.shield")
                    .foregroundStyle(model.granted ? Color.green : Color.accentColor)
                Text(model.granted ? "Permission granted".localized() : model.kind.title.localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .adaptiveGlassCapsule(interactive: true)
            }
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 56, height: 56)
                    .scaleEffect(hovering ? 1.06 : 1)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .onHover { hovering = $0 }
                    .onDrag {
                        NSItemProvider(object: Bundle.main.bundleURL as NSURL)
                    }
                    .help("Drag into System Settings".localized())
                    .accessibilityIdentifier("permission.dragIcon")
                Text(model.granted ? "Relaunch ishare to start capturing.".localized() : model.kind.instructions.localized())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Open System Settings".localized()) {
                    NSWorkspace.shared.open(model.kind.settingsURL)
                }
                Spacer()
                Button("Relaunch".localized()) {
                    PermissionGuide.relaunch()
                }
                .adaptiveGlassButtonStyle(prominent: model.granted)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 330)
        .adaptiveGlass(cornerRadius: 18)
    }
}

@MainActor
enum PermissionGuide {
    private static var panel: NSPanel?
    private static var timer: Timer?
    private static var model: PermissionGuideModel?

    static func show(_ kind: PermissionKind) {
        kind.request()
        NSWorkspace.shared.open(kind.settingsURL)
        guard panel == nil else { return }
        let model = PermissionGuideModel(kind: kind)
        model.onClose = { close() }
        let hosting = NSHostingView(rootView: PermissionGuideView(model: model))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = HUDPanel(
            contentRect: CGRect(x: screen.maxX - size.width - 24, y: screen.minY + 24, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        self.model = model
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                PermissionGuide.model?.refresh()
            }
        }
    }

    static func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
