import AppKit
import Defaults
import SwiftUI

enum CaptureDelay: Int, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Self { self }

    var seconds: Int { rawValue }

    var title: String {
        self == .off ? "Off".localized() : String(format: "%d s".localized(), rawValue)
    }

    static func effectiveSeconds(for type: CaptureType, explicit: Int?, setting: CaptureDelay) -> Int {
        if let explicit { return max(0, explicit) }
        switch type {
        case .SCREEN, .WINDOW: return setting.seconds
        default: return 0
        }
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var remaining: Int
    @Published var cancelled = false

    init(seconds: Int) {
        remaining = seconds
    }
}

struct CountdownHUD: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        HStack(spacing: 10) {
            Text("\(model.remaining)")
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
                .frame(minWidth: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Capturing soon".localized())
                    .font(.system(size: 12, weight: .semibold))
                Text("Press Esc to cancel".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button {
                model.cancelled = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .helpAndAccessibilityLabel("Cancel".localized())
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .adaptiveGlass(cornerRadius: 14)
    }
}

struct CountdownFocus: Equatable, Sendable {
    let ownProcessID: pid_t
    private(set) var appToRestore: pid_t?

    init(ownProcessID: pid_t, frontmost: pid_t?) {
        self.ownProcessID = ownProcessID
        appToRestore = frontmost == ownProcessID ? nil : frontmost
    }

    mutating func activated(_ processID: pid_t) -> Bool {
        guard processID != ownProcessID else { return false }
        appToRestore = processID
        return true
    }
}

@MainActor
final class CountdownKeyKeeper {
    private let panel: NSPanel
    private var focus: CountdownFocus
    private var observer: NSObjectProtocol?
    private var restored = false

    init(panel: NSPanel) {
        self.panel = panel
        focus = CountdownFocus(ownProcessID: ProcessInfo.processInfo.processIdentifier, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func start() {
        panel.orderFrontRegardless()
        panel.makeKey()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let processID else { return }
                self?.applicationActivated(processID)
            }
        }
    }

    func finish() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        panel.orderOut(nil)
        guard !restored else { return }
        restored = true
        restoreFocus()
    }

    private func applicationActivated(_ processID: pid_t) {
        guard focus.activated(processID), panel.isVisible, !panel.isKeyWindow else { return }
        panel.makeKey()
    }

    private func restoreFocus() {
        guard let processID = focus.appToRestore,
              let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated
        else { return }
        if NSApp.isActive {
            NSApp.yieldActivation(to: app)
        }
        app.activate()
    }
}

@MainActor
enum CaptureCountdown {
    static func run(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        let model = CountdownModel(seconds: seconds)
        let keeper = CountdownKeyKeeper(panel: panel(for: model))
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == KeyCode.escape else { return event }
            model.cancelled = true
            return nil
        }
        keeper.start()
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            keeper.finish()
        }
        while model.remaining > 0, !model.cancelled {
            for _ in 0 ..< 10 where !model.cancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !model.cancelled {
                withMotionAnimation { model.remaining -= 1 }
            }
        }
        keeper.finish()
        guard !model.cancelled else { return false }
        try? await Task.sleep(for: .milliseconds(120))
        return true
    }

    nonisolated static func origin(for size: CGSize, pointer: CGPoint, visibleFrame: CGRect) -> CGPoint {
        var origin = CGPoint(x: pointer.x + 18, y: pointer.y - size.height - 18)
        if origin.x + size.width > visibleFrame.maxX - 8 {
            origin.x = pointer.x - size.width - 18
        }
        if origin.y < visibleFrame.minY + 8 {
            origin.y = pointer.y + 18
        }
        origin.x = min(max(visibleFrame.minX + 8, origin.x), visibleFrame.maxX - size.width - 8)
        origin.y = min(max(visibleFrame.minY + 8, origin.y), visibleFrame.maxY - size.height - 8)
        return origin
    }

    private static func panel(for model: CountdownModel) -> NSPanel {
        let hosting = NSHostingView(rootView: CountdownHUD(model: model))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let pointer = NSEvent.mouseLocation
        let visibleFrame = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let frame = CGRect(origin: origin(for: size, pointer: pointer, visibleFrame: visibleFrame), size: size)
        let panel = HUDPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        return panel
    }
}
