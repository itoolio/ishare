import AppKit
import Defaults
import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScrollingCaptureModel: ObservableObject {
    @Published var capturedHeight = 0
    @Published var frameCount = 0
    @Published var isAutomatic = false
    @Published var finished = false
    @Published var cancelled = false
}

struct ScrollingCaptureHUD: View {
    @ObservedObject var model: ScrollingCaptureModel

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isAutomatic ? "Scrolling automatically…".localized() : "Scroll the content, then click Done".localized())
                    .font(.system(size: 12, weight: .semibold))
                Text(String(format: "%d px".localized(), model.capturedHeight))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Cancel".localized()) { model.cancelled = true }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("scrolling.cancel")
            Button("Done".localized()) { model.finished = true }
                .keyboardShortcut(.defaultAction)
                .adaptiveGlassButtonStyle(prominent: true)
                .accessibilityIdentifier("scrolling.done")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 380)
        .adaptiveGlass(cornerRadius: 16)
    }
}

final class RegionBorderView: NSView {
    var dashed = true

    override func draw(_: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        if dashed {
            path.setLineDash([8, 6], count: 2, phase: 0)
        }
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

@MainActor
enum RegionOverlay {
    static func borderWindow(around rect: CGRect, dashed: Bool = true) -> NSWindow {
        let frame = rect.insetBy(dx: -4, dy: -4)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = RegionBorderView(frame: CGRect(origin: .zero, size: frame.size))
        view.dashed = dashed
        window.contentView = view
        return window
    }

    static func hudWindow<Content: View>(_ content: Content, near rect: CGRect, on screen: NSScreen) -> NSPanel {
        let hosting = NSHostingView(rootView: content)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 14)
        if origin.y < screen.visibleFrame.minY {
            origin.y = min(rect.maxY + 14, screen.visibleFrame.maxY - size.height - 8)
        }
        if origin.y + size.height > screen.visibleFrame.maxY || rect.height > screen.visibleFrame.height - size.height - 40 {
            origin.y = screen.visibleFrame.minY + 24
        }
        origin.x = min(max(screen.visibleFrame.minX + 8, origin.x), screen.visibleFrame.maxX - size.width - 8)
        let panel = HUDPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        return panel
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
enum ScrollingCapture {
    static let maximumHeight = 40000
    static let maximumFrames = 160

    static func run(content: SCShareableContent) async throws -> CapturedImage? {
        let selection = await RegionSelector.select(options: .init(showsMagnifier: false, allowsWindowMode: false, hint: "Select the area to scroll".localized()))
        guard case let .region(screen, rect) = selection,
              let display = ScreenshotEngine.display(for: screen, in: content)
        else { return nil }

        let globalRect = CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width, height: rect.height
        )
        let model = ScrollingCaptureModel()
        let canAutoScroll = Defaults[.scrollingAutoScroll] && hasPostEventAccess
        model.isAutomatic = canAutoScroll
        let border = RegionOverlay.borderWindow(around: globalRect)
        let hud = RegionOverlay.hudWindow(ScrollingCaptureHUD(model: model), near: globalRect, on: screen)
        border.orderFrontRegardless()
        hud.orderFrontRegardless()
        hud.makeKey()
        defer {
            border.orderOut(nil)
            hud.orderOut(nil)
        }

        try await Task.sleep(for: .milliseconds(150))
        let scrollPoint = CGPoint(x: display.frame.minX + rect.midX, y: display.frame.minY + rect.midY)
        var frames: [CGImage] = []
        var offsets: [Int] = []
        var lastAccepted: GrayFrame?
        var stillCount = 0

        while !model.finished, !model.cancelled {
            let image = try await ScreenshotEngine.captureDisplay(display, region: rect, in: content, showsCursor: false)
            guard let gray = GrayFrame(image: image) else { break }
            if let previous = lastAccepted {
                if let match = ScrollStitcher.verticalOffset(previous: previous, next: gray), match.offset > 0 {
                    frames.append(image)
                    offsets.append(match.offset)
                    lastAccepted = gray
                    stillCount = 0
                } else {
                    stillCount += 1
                }
            } else {
                frames.append(image)
                lastAccepted = gray
            }
            model.frameCount = frames.count
            model.capturedHeight = (frames.first?.height ?? 0) + offsets.reduce(0, +)

            if model.capturedHeight >= maximumHeight || frames.count >= maximumFrames {
                break
            }
            if canAutoScroll {
                if stillCount >= 3 {
                    break
                }
                scroll(at: scrollPoint, by: Int(rect.height * 0.6))
                try await Task.sleep(for: .milliseconds(320))
            } else {
                try await Task.sleep(for: .milliseconds(220))
            }
        }

        guard !model.cancelled, let stitched = ScrollStitcher.stitch(frames: frames, offsets: offsets) else { return nil }
        return CapturedImage(image: stitched, suffix: "scrolling")
    }

    #if APP_STORE
        nonisolated static let autoScrollsByDefault = false
    #else
        nonisolated static let autoScrollsByDefault = true
    #endif

    static var hasPostEventAccess: Bool {
        CGPreflightPostEventAccess()
    }

    static func scroll(at point: CGPoint, by points: Int) {
        let steps = 4
        let perStep = Int32(max(1, points / steps))
        for _ in 0 ..< steps {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -perStep, wheel2: 0, wheel3: 0) else { return }
            event.location = point
            event.post(tap: .cghidEventTap)
        }
    }
}
