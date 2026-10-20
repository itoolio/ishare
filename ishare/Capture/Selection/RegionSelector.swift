import AppKit

@MainActor
final class RegionSelector {
    enum Outcome: @unchecked Sendable {
        case region(NSScreen, CGRect)
        case fullScreen(NSScreen)
        case switchToWindow
        case cancelled
    }

    struct Options {
        var backdrops: [CGDirectDisplayID: CGImage] = [:]
        var showsMagnifier = true
        var allowsWindowMode = true
        var hint: String?
    }

    private static var active: RegionSelector?
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<Outcome, Never>?

    static func select(options: Options = Options()) async -> Outcome {
        active?.finish(.cancelled)
        let selector = RegionSelector()
        active = selector
        let outcome = await selector.run(options: options)
        active = nil
        return outcome
    }

    private func run(options: Options) async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                let panel = SelectionPanel(screen: screen)
                let view = RegionSelectionView(
                    screen: screen,
                    backdrop: screen.displayID.flatMap { options.backdrops[$0] },
                    options: options
                ) { [weak self] outcome in
                    self?.finish(outcome)
                }
                panel.contentView = view
                panel.orderFrontRegardless()
                panels.append(panel)
            }
            let keyPanel = panels.first { $0.screen == NSScreen.underMouse } ?? panels.first
            keyPanel?.makeKey()
            if let view = keyPanel?.contentView {
                keyPanel?.makeFirstResponder(view)
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: outcome)
    }
}

final class RegionSelectionView: NSView {
    private let screen: NSScreen
    private let backdrop: CGImage?
    private let options: RegionSelector.Options
    private let onFinish: (RegionSelector.Outcome) -> Void

    private var anchor: CGPoint?
    private var current: CGPoint = .zero
    private var selection: CGRect?
    private var isMovingSelection = false
    private var lastDragPoint: CGPoint = .zero
    private var constrainsToSquare = false
    private var mouseLocation: CGPoint?

    init(screen: NSScreen, backdrop: CGImage?, options: RegionSelector.Options, onFinish: @escaping (RegionSelector.Outcome) -> Void) {
        self.screen = screen
        self.backdrop = backdrop
        self.options = options
        self.onFinish = onFinish
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        let tracking = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        )
        addTrackingArea(tracking)
        let location = window?.mouseLocationOutsideOfEventStream ?? convertFromScreen(NSEvent.mouseLocation)
        if bounds.contains(location) {
            mouseLocation = location
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    private var scale: CGFloat {
        guard let backdrop else { return screen.backingScaleFactor }
        return CGFloat(backdrop.width) / max(1, bounds.width)
    }

    private func convertFromScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseEntered(with _: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func mouseExited(with _: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        anchor = point
        current = point
        lastDragPoint = point
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        mouseLocation = point
        if isMovingSelection, let rect = selection {
            let delta = CGVector(dx: point.x - lastDragPoint.x, dy: point.y - lastDragPoint.y)
            let moved = ScreenGeometry.moved(rect, by: delta, within: bounds)
            let applied = CGVector(dx: moved.minX - rect.minX, dy: moved.minY - rect.minY)
            anchor = anchor.map { CGPoint(x: $0.x + applied.dx, y: $0.y + applied.dy) }
            current = CGPoint(x: current.x + applied.dx, y: current.y + applied.dy)
            selection = moved
        } else {
            current = point
            updateSelection()
        }
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with _: NSEvent) {
        guard let rect = selection, ScreenGeometry.isMeaningfulSelection(rect) else {
            anchor = nil
            selection = nil
            needsDisplay = true
            return
        }
        onFinish(.region(screen, ScreenGeometry.flippedVertically(rect.integral, containerHeight: bounds.height)))
    }

    override func flagsChanged(with event: NSEvent) {
        constrainsToSquare = event.modifierFlags.contains(.shift)
        if anchor != nil {
            updateSelection()
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.escape:
            onFinish(.cancelled)
        case KeyCode.space:
            if anchor != nil {
                isMovingSelection = true
            } else if options.allowsWindowMode, !event.isARepeat {
                onFinish(.switchToWindow)
            }
        case KeyCode.returnKey, KeyCode.enter:
            if let rect = selection, ScreenGeometry.isMeaningfulSelection(rect) {
                onFinish(.region(screen, ScreenGeometry.flippedVertically(rect.integral, containerHeight: bounds.height)))
            } else {
                onFinish(.fullScreen(screen))
            }
        case KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down:
            nudge(keyCode: event.keyCode, step: event.modifierFlags.contains(.shift) ? 10 : 1)
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == KeyCode.space {
            isMovingSelection = false
        }
    }

    private func nudge(keyCode: UInt16, step: CGFloat) {
        let delta: CGVector = switch keyCode {
        case KeyCode.left: CGVector(dx: -step, dy: 0)
        case KeyCode.right: CGVector(dx: step, dy: 0)
        case KeyCode.up: CGVector(dx: 0, dy: step)
        default: CGVector(dx: 0, dy: -step)
        }
        if anchor != nil {
            current = clampToBounds(CGPoint(x: current.x + delta.dx, y: current.y + delta.dy))
            updateSelection()
        } else if let location = mouseLocation {
            let moved = clampToBounds(CGPoint(x: location.x + delta.dx, y: location.y + delta.dy))
            mouseLocation = moved
            let global = CGPoint(x: moved.x + screen.frame.minX, y: moved.y + screen.frame.minY)
            CGWarpMouseCursorPosition(ScreenGeometry.cocoaPointToQuartz(global, primaryScreenHeight: NSScreen.primaryHeight))
        }
        needsDisplay = true
    }

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func updateSelection() {
        guard let anchor else { return }
        let rect = constrainsToSquare ? ScreenGeometry.squareRect(from: anchor, to: current) : ScreenGeometry.rect(from: anchor, to: current)
        selection = ScreenGeometry.clamp(rect, to: bounds)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let backdrop {
            context.interpolationQuality = .high
            context.draw(backdrop, in: bounds)
        }
        let dimPath = NSBezierPath(rect: bounds)
        if let selection, !selection.isEmpty {
            dimPath.append(NSBezierPath(rect: selection))
            dimPath.windingRule = .evenOdd
        }
        SelectionStyle.dimColor.setFill()
        dimPath.fill()

        if let selection, !selection.isEmpty {
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            SelectionStyle.borderColor.setStroke()
            border.stroke()
            let pixelSize = CGSize(width: (selection.width * scale).rounded(), height: (selection.height * scale).rounded())
            SelectionStyle.drawPill(
                "\(Int(pixelSize.width)) × \(Int(pixelSize.height))",
                near: CGPoint(x: selection.minX, y: selection.maxY),
                in: bounds,
                above: selection.maxY + 32 < bounds.maxY
            )
        } else if let hint = options.hint, mouseLocation != nil || NSScreen.underMouse == screen {
            SelectionStyle.drawPill(hint, near: CGPoint(x: bounds.midX - 120, y: bounds.maxY - 80), in: bounds)
        }

        if let location = mouseLocation {
            if options.showsMagnifier, let backdrop {
                drawMagnifier(backdrop: backdrop, at: location, context: context)
            } else if selection == nil {
                let pixel = CGPoint(x: (location.x * scale).rounded(), y: ((bounds.height - location.y) * scale).rounded())
                SelectionStyle.drawPill("\(Int(pixel.x)), \(Int(pixel.y))", near: CGPoint(x: location.x + 14, y: location.y - 34), in: bounds)
            }
        }
    }

    private func drawMagnifier(backdrop: CGImage, at location: CGPoint, context: CGContext) {
        let sampleSize: CGFloat = 17
        let loupeSize: CGFloat = 136
        let pixelX = (location.x * scale).rounded(.down)
        let pixelY = ((bounds.height - location.y) * scale).rounded(.down)
        let source = CGRect(x: pixelX - floor(sampleSize / 2), y: pixelY - floor(sampleSize / 2), width: sampleSize, height: sampleSize)
        guard let crop = backdrop.cropping(to: source.intersection(CGRect(x: 0, y: 0, width: backdrop.width, height: backdrop.height))) else { return }

        var origin = CGPoint(x: location.x + 22, y: location.y - loupeSize - 22)
        if origin.x + loupeSize > bounds.maxX { origin.x = location.x - loupeSize - 22 }
        if origin.y < bounds.minY { origin.y = location.y + 22 }
        let frame = CGRect(origin: origin, size: CGSize(width: loupeSize, height: loupeSize))

        context.saveGState()
        let clip = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        clip.addClip()
        NSColor.black.setFill()
        frame.fill()
        context.interpolationQuality = .none
        let cell = loupeSize / sampleSize
        let drawRect = CGRect(
            x: frame.minX + (source.minX < 0 ? -source.minX * cell : 0),
            y: frame.minY + (source.maxY > CGFloat(backdrop.height) ? (source.maxY - CGFloat(backdrop.height)) * cell : 0),
            width: CGFloat(crop.width) * cell,
            height: CGFloat(crop.height) * cell
        )
        context.draw(crop, in: drawRect)
        let center = CGRect(x: frame.minX + floor(sampleSize / 2) * cell, y: frame.minY + floor(sampleSize / 2) * cell, width: cell, height: cell)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let centerPath = NSBezierPath(rect: center)
        centerPath.lineWidth = 1.5
        centerPath.stroke()
        context.restoreGState()

        let outline = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        outline.lineWidth = 2
        NSColor.white.withAlphaComponent(0.85).setStroke()
        outline.stroke()

        let pixel = CGPoint(x: (location.x * scale).rounded(), y: ((bounds.height - location.y) * scale).rounded())
        SelectionStyle.drawPill("\(Int(pixel.x)), \(Int(pixel.y))", near: CGPoint(x: frame.minX, y: frame.minY - 2), in: bounds, above: false)
    }
}
