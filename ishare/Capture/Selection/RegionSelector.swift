import AppKit
import Defaults
import ishareCore

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
        var allowsWindowMode = true
        var hint: String?
        var lastRegions: [CGDirectDisplayID: CGRect] = [:]
        var awaitsBackdrops = false
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

    static var panelWindowIDs: Set<CGWindowID> {
        Set(active?.panels.map { CGWindowID($0.windowNumber) } ?? [])
    }

    static func provide(backdrops: [CGDirectDisplayID: CGImage]) {
        active?.provide(backdrops: backdrops)
    }

    private func provide(backdrops: [CGDirectDisplayID: CGImage]) {
        for panel in panels {
            guard let view = panel.contentView as? RegionSelectionView else { continue }
            if let displayID = view.displayID, let backdrop = backdrops[displayID] {
                view.backdrop = backdrop
            }
            view.awaitsBackdrop = false
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
    fileprivate var backdrop: CGImage? {
        didSet { needsDisplay = true }
    }
    fileprivate var awaitsBackdrop: Bool {
        didSet { needsDisplay = true }
    }
    private let options: RegionSelector.Options
    private let onFinish: (RegionSelector.Outcome) -> Void

    private var anchor: CGPoint?
    private var current: CGPoint = .zero
    private var selection: CGRect?
    private var isMovingSelection = false
    private var lastDragPoint: CGPoint = .zero
    private var constrainsToSquare = false
    private var mouseLocation: CGPoint?
    private var isMeasureModifierHeld = false
    private var isMeasuring = false
    private var measurementStart: CGPoint?
    private var measurement: SelectionMeasurement?

    init(screen: NSScreen, backdrop: CGImage?, options: RegionSelector.Options, onFinish: @escaping (RegionSelector.Outcome) -> Void) {
        self.screen = screen
        self.backdrop = backdrop
        awaitsBackdrop = options.awaitsBackdrops && backdrop == nil
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
        isMeasureModifierHeld = NSEvent.modifierFlags.contains(.option)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    // Z flips one preference: the magnifier where there's a frozen frame to sample, the position pill everywhere else.
    private var showsPosition: Bool {
        Defaults[.showMagnifier]
    }

    private var hasMagnifier: Bool {
        options.awaitsBackdrops || !options.backdrops.isEmpty
    }

    // Holds back the coordinates until the frozen frame arrives, so they don't flash before the magnifier replaces them.
    private var magnifierPending: Bool {
        showsPosition && awaitsBackdrop
    }

    private var scale: CGFloat {
        guard let backdrop else { return screen.backingScaleFactor }
        return CGFloat(backdrop.width) / max(1, bounds.width)
    }

    fileprivate var displayID: CGDirectDisplayID? {
        screen.displayID
    }

    private var lastRegion: CGRect? {
        guard let displayID = screen.displayID, let stored = options.lastRegions[displayID] else { return nil }
        let rect = ScreenGeometry.clamp(ScreenGeometry.flippedVertically(stored, containerHeight: bounds.height), to: bounds)
        return ScreenGeometry.isMeaningfulSelection(rect) ? rect : nil
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
        isMeasureModifierHeld = event.modifierFlags.contains(.option)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) {
            beginMeasuring(at: point)
            return
        }
        measurement = nil
        anchor = point
        current = point
        lastDragPoint = point
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        mouseLocation = point
        if isMeasuring {
            updateMeasurement(to: point, locksAxis: event.modifierFlags.contains(.shift))
            return
        }
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
        if isMeasuring {
            isMeasuring = false
            needsDisplay = true
            return
        }
        guard let rect = selection, ScreenGeometry.isMeaningfulSelection(rect) else {
            anchor = nil
            selection = nil
            needsDisplay = true
            return
        }
        finishSelection(rect)
    }

    override func flagsChanged(with event: NSEvent) {
        constrainsToSquare = event.modifierFlags.contains(.shift)
        isMeasureModifierHeld = event.modifierFlags.contains(.option)
        if isMeasuring, let end = measurement?.end {
            updateMeasurement(to: mouseLocation ?? end, locksAxis: constrainsToSquare)
        }
        if anchor != nil {
            updateSelection()
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.escape:
            if measurement != nil, !isMeasuring {
                measurement = nil
                needsDisplay = true
            } else {
                onFinish(.cancelled)
            }
        case KeyCode.space:
            if anchor != nil {
                isMovingSelection = true
            } else if options.allowsWindowMode, !event.isARepeat {
                onFinish(.switchToWindow)
            }
        case KeyCode.returnKey, KeyCode.enter:
            if let rect = selection, ScreenGeometry.isMeaningfulSelection(rect) {
                finishSelection(rect)
            } else {
                onFinish(.fullScreen(screen))
            }
        case KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down:
            nudge(keyCode: event.keyCode, step: event.modifierFlags.contains(.shift) ? 10 : 1)
        default:
            let character = event.charactersIgnoringModifiers?.lowercased()
            if character == "l", !event.isARepeat, selectLastRegion() {
                return
            }
            if character == "g", !event.isARepeat {
                Defaults[.showSelectionGuides].toggle()
                needsDisplay = true
                return
            }
            if character == "z", !event.isARepeat {
                Defaults[.showMagnifier].toggle()
                needsDisplay = true
                return
            }
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == KeyCode.space {
            isMovingSelection = false
        }
    }

    private func finishSelection(_ rect: CGRect) {
        onFinish(.region(screen, ScreenGeometry.flippedVertically(rect.integral, containerHeight: bounds.height)))
    }

    private func selectLastRegion() -> Bool {
        guard let lastRegion else { return false }
        if selection == lastRegion {
            finishSelection(lastRegion)
            return true
        }
        isMeasuring = false
        measurement = nil
        anchor = CGPoint(x: lastRegion.minX, y: lastRegion.minY)
        current = CGPoint(x: lastRegion.maxX, y: lastRegion.maxY)
        selection = lastRegion
        needsDisplay = true
        return true
    }

    private func beginMeasuring(at point: CGPoint) {
        anchor = nil
        selection = nil
        isMeasuring = true
        measurementStart = point
        measurement = SelectionMeasurement(start: point, end: point)
        needsDisplay = true
    }

    private func updateMeasurement(to point: CGPoint, locksAxis: Bool) {
        guard let start = measurementStart else { return }
        let raw = SelectionMeasurement(start: start, end: point)
        measurement = locksAxis ? raw.lockedToAxis() : raw
        needsDisplay = true
    }

    private func nudge(keyCode: UInt16, step: CGFloat) {
        let delta: CGVector =
            switch keyCode {
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

    private var hudText: String {
        var parts = ["Drag to select".localized()]
        if options.allowsWindowMode {
            parts.append("Space for windows".localized())
        }
        parts.append("⌥ drag to measure".localized())
        if lastRegion != nil {
            parts.append("L for last region".localized())
        }
        parts.append("G for guides".localized())
        parts.append(hasMagnifier ? "Z for zoom and position".localized() : "Z for position".localized())
        parts.append("Return for full screen".localized())
        return parts.joined(separator: "  ·  ")
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let backdrop {
            context.interpolationQuality = .high
            context.draw(backdrop, in: bounds)
        }
        drawDimming()

        let isOnThisScreen = mouseLocation != nil || NSScreen.underMouse == screen
        if let selection, !selection.isEmpty {
            drawSelection(selection)
        } else {
            if let lastRegion, Defaults[.showLastRegionOutline] {
                drawLastRegionGhost(lastRegion)
            }
            if isOnThisScreen, measurement == nil {
                if let hint = options.hint {
                    SelectionStyle.drawPill(hint, near: CGPoint(x: bounds.midX - 120, y: bounds.maxY - 80), in: bounds)
                }
                SelectionStyle.drawPill(hudText, centeredAt: CGPoint(x: bounds.midX, y: bounds.minY + 56), in: bounds)
            }
        }

        if let measurement {
            drawMeasurement(measurement)
        }

        guard let location = mouseLocation else { return }
        let isMeasuringGuides = isMeasureModifierHeld || isMeasuring
        if isMeasuringGuides || Defaults[.showSelectionGuides] {
            drawGuides(at: location, labelled: isMeasuringGuides)
        }
        if showsPosition, let backdrop {
            drawMagnifier(backdrop: backdrop, at: location, context: context)
        } else if showsPosition, selection == nil, !isMeasureModifierHeld, !magnifierPending {
            SelectionStyle.drawPill(DisplayCoordinates.label(for: location, in: bounds), near: CGPoint(x: location.x + 14, y: location.y - 34), in: bounds)
        }
    }

    private func drawDimming() {
        let dimPath = NSBezierPath(rect: bounds)
        if let selection, !selection.isEmpty {
            dimPath.append(NSBezierPath(rect: selection))
            dimPath.windingRule = .evenOdd
        }
        SelectionStyle.dimColor.setFill()
        dimPath.fill()
    }

    private func drawSelection(_ selection: CGRect) {
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
    }

    private func drawLastRegionGhost(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = 1
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.stroke()
    }

    private func drawGuides(at location: CGPoint, labelled: Bool) {
        let x = location.x.rounded(.down) + 0.5
        let y = location.y.rounded(.down) + 0.5
        let guides = NSBezierPath()
        guides.move(to: CGPoint(x: bounds.minX, y: y))
        guides.line(to: CGPoint(x: bounds.maxX, y: y))
        guides.move(to: CGPoint(x: x, y: bounds.minY))
        guides.line(to: CGPoint(x: x, y: bounds.maxY))
        guides.lineWidth = 1
        NSColor.black.withAlphaComponent(0.45).setStroke()
        guides.stroke()
        guides.setLineDash([4, 4], count: 2, phase: 0)
        SelectionStyle.accentColor.setStroke()
        guides.stroke()
        if labelled, !showsPosition || backdrop == nil, !magnifierPending {
            SelectionStyle.drawPill(DisplayCoordinates.label(for: location, in: bounds), near: CGPoint(x: location.x + 8, y: location.y + 4), in: bounds)
        }
    }

    private func drawMeasurement(_ measurement: SelectionMeasurement) {
        let line = NSBezierPath()
        line.move(to: measurement.start)
        line.line(to: measurement.end)
        line.lineCapStyle = .round
        line.lineWidth = 3
        NSColor.black.withAlphaComponent(0.5).setStroke()
        line.stroke()
        line.lineWidth = 1.5
        SelectionStyle.accentColor.setStroke()
        line.stroke()
        for point in [measurement.start, measurement.end] {
            let dot = NSBezierPath(ovalIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            NSColor.white.setFill()
            dot.fill()
            SelectionStyle.accentColor.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
        let midpoint = CGPoint(x: (measurement.start.x + measurement.end.x) / 2, y: (measurement.start.y + measurement.end.y) / 2)
        SelectionStyle.drawPill(measurement.label(scale: scale), centeredAt: CGPoint(x: midpoint.x, y: midpoint.y + 18), in: bounds)
    }

    private func drawMagnifier(backdrop: CGImage, at location: CGPoint, context: CGContext) {
        let samples = CGFloat(MagnifierLayout.sampleCount)
        let half = floor(samples / 2)
        let side = MagnifierLayout.loupeSide
        let cell = side / samples
        let card = MagnifierLayout.cardFrame(for: location, in: bounds)
        let loupe = CGRect(x: card.minX, y: card.maxY - side, width: side, height: side)
        let pixel = DisplayCoordinates.pixel(for: location, in: bounds, scale: scale)
        let imageBounds = CGRect(x: 0, y: 0, width: backdrop.width, height: backdrop.height)
        let source = CGRect(x: pixel.x - half, y: pixel.y - half, width: samples, height: samples)
        let visible = source.intersection(imageBounds)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)

        context.saveGState()
        NSColor(white: 0.08, alpha: 0.94).setFill()
        cardPath.fill()
        cardPath.addClip()
        if !visible.isNull, let crop = backdrop.cropping(to: visible) {
            context.interpolationQuality = .none
            let drawRect = CGRect(
                x: loupe.minX + (visible.minX - source.minX) * cell,
                y: loupe.minY + (source.maxY - visible.maxY) * cell,
                width: visible.width * cell,
                height: visible.height * cell
            )
            context.draw(crop, in: drawRect)
        }
        drawLoupeGrid(in: loupe, cell: cell, samples: Int(samples))
        let center = CGRect(x: loupe.minX + half * cell, y: loupe.minY + half * cell, width: cell, height: cell)
        let centerPath = NSBezierPath(rect: center.insetBy(dx: -0.5, dy: -0.5))
        centerPath.lineWidth = 2.5
        NSColor.black.withAlphaComponent(0.8).setStroke()
        centerPath.stroke()
        centerPath.lineWidth = 1.2
        NSColor.white.setStroke()
        centerPath.stroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: card.minX, y: loupe.minY))
        divider.line(to: CGPoint(x: card.maxX, y: loupe.minY))
        divider.lineWidth = 1
        NSColor.white.withAlphaComponent(0.25).setStroke()
        divider.stroke()
        context.restoreGState()

        let outline = NSBezierPath(roundedRect: card.insetBy(dx: 0.75, dy: 0.75), xRadius: 14, yRadius: 14)
        outline.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.8).setStroke()
        outline.stroke()

        let info = CGRect(x: card.minX, y: card.minY, width: card.width, height: MagnifierLayout.infoHeight)
        drawMagnifierInfo(in: info, location: location, color: ImageProcessing.pixelColor(of: backdrop, at: pixel))
    }

    private func drawLoupeGrid(in loupe: CGRect, cell: CGFloat, samples: Int) {
        let grid = NSBezierPath()
        for index in 1 ..< samples {
            let offset = CGFloat(index) * cell
            grid.move(to: CGPoint(x: loupe.minX + offset, y: loupe.minY))
            grid.line(to: CGPoint(x: loupe.minX + offset, y: loupe.maxY))
            grid.move(to: CGPoint(x: loupe.minX, y: loupe.minY + offset))
            grid.line(to: CGPoint(x: loupe.maxX, y: loupe.minY + offset))
        }
        grid.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.18).setStroke()
        grid.stroke()
    }

    private func drawMagnifierInfo(in info: CGRect, location: CGPoint, color: CaptureColor?) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let primary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.75)]
        let coordinates = NSAttributedString(string: DisplayCoordinates.label(for: location, in: bounds), attributes: primary)
        let coordinatesSize = coordinates.size()
        coordinates.draw(at: CGPoint(x: info.minX + 12, y: info.midY - coordinatesSize.height / 2))

        guard let color else { return }
        let hex = NSAttributedString(string: color.hex, attributes: secondary)
        let hexSize = hex.size()
        let hexOrigin = CGPoint(x: info.maxX - 12 - hexSize.width, y: info.midY - hexSize.height / 2)
        hex.draw(at: hexOrigin)
        let swatch = CGRect(x: hexOrigin.x - 20, y: info.midY - 7, width: 14, height: 14)
        let swatchPath = NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3)
        NSColor(cgColor: color.cgColor)?.setFill()
        swatchPath.fill()
        swatchPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.6).setStroke()
        swatchPath.stroke()
    }
}
