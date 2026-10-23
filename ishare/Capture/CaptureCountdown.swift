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
            .help("Cancel".localized())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .adaptiveGlass(cornerRadius: 14)
    }
}

@MainActor
enum CaptureCountdown {
    static func run(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        let model = CountdownModel(seconds: seconds)
        let panel = panel(for: model)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == KeyCode.escape else { return event }
            model.cancelled = true
            return nil
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            panel.orderOut(nil)
        }
        while model.remaining > 0, !model.cancelled {
            for _ in 0 ..< 10 where !model.cancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !model.cancelled {
                withAnimation { model.remaining -= 1 }
            }
        }
        panel.orderOut(nil)
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
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        return panel
    }
}
