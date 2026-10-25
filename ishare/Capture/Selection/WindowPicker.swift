import AppKit
import ishareCore
import ScreenCaptureKit

@MainActor
final class WindowPicker {
    enum Outcome: @unchecked Sendable {
        case window(SCWindow)
        case switchToRegion
        case cancelled
    }

    struct Candidate {
        let window: SCWindow
        let frame: CGRect
        let appName: String
        let title: String?
        let icon: NSImage?
    }

    private static var active: WindowPicker?
    private var panels: [SelectionPanel] = []
    private var views: [WindowPickerView] = []
    private var continuation: CheckedContinuation<Outcome, Never>?
    private(set) var candidates: [Candidate] = []
    private(set) var hovered: Candidate?

    static func pick(from windows: [SCWindow]) async -> Outcome {
        active?.finish(.cancelled)
        let picker = WindowPicker()
        picker.candidates = windows.map { window in
            let app = window.owningApplication
            let runningApp = app.flatMap { NSRunningApplication(processIdentifier: $0.processID) }
            return Candidate(
                window: window,
                frame: window.frame,
                appName: app?.applicationName ?? "",
                title: window.title,
                icon: runningApp?.icon
            )
        }
        active = picker
        let outcome = await picker.run()
        active = nil
        return outcome
    }

    private func run() async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                let panel = SelectionPanel(screen: screen)
                let view = WindowPickerView(screen: screen, picker: self)
                panel.contentView = view
                panel.orderFrontRegardless()
                panels.append(panel)
                views.append(view)
            }
            let keyPanel = panels.first { $0.screen == NSScreen.underMouse } ?? panels.first
            keyPanel?.makeKey()
            if let view = keyPanel?.contentView {
                keyPanel?.makeFirstResponder(view)
            }
            updateHover(at: NSEvent.mouseLocation)
        }
    }

    func updateHover(at cocoaLocation: CGPoint) {
        let quartzPoint = ScreenGeometry.cocoaPointToQuartz(cocoaLocation, primaryScreenHeight: NSScreen.primaryHeight)
        let index = ScreenGeometry.topmostWindowIndex(at: quartzPoint, frames: candidates.map(\.frame))
        let candidate = index.map { candidates[$0] }
        guard candidate?.window.windowID != hovered?.window.windowID else { return }
        hovered = candidate
        views.forEach { $0.needsDisplay = true }
    }

    func confirm() {
        if let hovered {
            finish(.window(hovered.window))
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    func switchToRegion() {
        finish(.switchToRegion)
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: outcome)
    }
}

final class WindowPickerView: NSView {
    private let screen: NSScreen
    private weak var picker: WindowPicker?

    init(screen: NSScreen, picker: WindowPicker) {
        self.screen = screen
        self.picker = picker
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
                owner: self, userInfo: nil
            ))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func cursorUpdate(with _: NSEvent) {
        SelectionStyle.cameraCursor.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: SelectionStyle.cameraCursor)
    }

    override func mouseEntered(with _: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with _: NSEvent) {
        picker?.updateHover(at: NSEvent.mouseLocation)
        SelectionStyle.cameraCursor.set()
    }

    override func mouseUp(with _: NSEvent) {
        picker?.updateHover(at: NSEvent.mouseLocation)
        picker?.confirm()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.escape:
            picker?.cancel()
        case KeyCode.space:
            if !event.isARepeat {
                picker?.switchToRegion()
            }
        case KeyCode.returnKey, KeyCode.enter:
            picker?.confirm()
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
        guard let candidate = picker?.hovered else { return }
        let global = ScreenGeometry.quartzToCocoa(candidate.frame, primaryScreenHeight: NSScreen.primaryHeight)
        let local = global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        guard local.intersects(bounds) else { return }

        let accent = SelectionStyle.accentColor
        accent.withAlphaComponent(0.22).setFill()
        let fill = NSBezierPath(roundedRect: local, xRadius: 10, yRadius: 10)
        fill.fill()
        accent.setStroke()
        fill.lineWidth = 3
        fill.stroke()

        let label = [candidate.appName, candidate.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        let visible = local.intersection(bounds)
        drawBadge(label: label, icon: candidate.icon, in: visible)
    }

    private func drawBadge(label: String, icon: NSImage?, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let truncated = label.count > 60 ? String(label.prefix(57)) + "…" : label
        let text = NSAttributedString(string: truncated, attributes: attributes)
        let textSize = text.size()
        let iconSize: CGFloat = icon == nil ? 0 : 22
        let width = textSize.width + iconSize + (icon == nil ? 20 : 28)
        let height: CGFloat = 34
        let frame = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: frame, xRadius: height / 2, yRadius: height / 2).fill()
        var x = frame.minX + 10
        if let icon {
            icon.draw(in: CGRect(x: x, y: frame.midY - iconSize / 2, width: iconSize, height: iconSize))
            x += iconSize + 8
        }
        text.draw(at: CGPoint(x: x, y: frame.midY - textSize.height / 2))
    }
}
