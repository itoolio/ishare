import AppKit
import Defaults
import ishareCore

final class RegionSelectionView: NSView {
    let screen: NSScreen
    let session: SelectionSession
    var backdrop: CGImage? {
        didSet { needsDisplay = true }
    }
    var awaitsBackdrop: Bool {
        didSet { needsDisplay = true }
    }
    var liveSample: LiveMagnifierSampler.Sample? {
        didSet { needsDisplay = true }
    }
    private let onFinish: (RegionSelector.Selection) -> Void

    var anchor: CGPoint?
    var current: CGPoint = .zero
    var selection: CGRect?
    var isFixedPlaced = false
    private var isMovingSelection = false
    private var lastDragPoint: CGPoint = .zero
    private var constrainsToSquare = false
    var mouseLocation: CGPoint?
    var isMeasureModifierHeld = false
    var isMeasuring = false
    private var measurementStart: CGPoint?
    var measurement: SelectionMeasurement?
    private var draggedRegionID: Int?
    var hoveredToolbarItem: SelectionToolbar.Item?

    init(screen: NSScreen, backdrop: CGImage?, session: SelectionSession, onFinish: @escaping (RegionSelector.Selection) -> Void) {
        self.screen = screen
        self.backdrop = backdrop
        self.session = session
        awaitsBackdrop = session.options.awaitsBackdrops && backdrop == nil && session.freezeMode == .frozen
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

    var options: RegionSelector.Options {
        session.options
    }

    var showsPosition: Bool {
        Defaults[.showMagnifier]
    }

    var magnifierSource: SelectionMagnifierSource {
        SelectionFreezePolicy.magnifierSource(
            enabled: showsPosition, mode: session.freezeMode,
            hasBackdrop: backdrop != nil, awaitingBackdrop: awaitsBackdrop, liveSamplingAvailable: options.liveSampler?.isAvailable == true
        )
    }

    var hasMagnifier: Bool {
        switch session.freezeMode {
        case .frozen: options.awaitsBackdrops || options.allowsFreezeToggle || !options.backdrops.isEmpty
        case .live: options.liveSampler?.isAvailable == true
        }
    }

    var scale: CGFloat {
        guard let backdrop else { return screen.backingScaleFactor }
        return CGFloat(backdrop.width) / max(1, bounds.width)
    }

    var displayID: CGDirectDisplayID? {
        screen.displayID
    }

    var lastRegion: CGRect? {
        guard let displayID = screen.displayID, let stored = options.lastRegions[displayID] else { return nil }
        let rect = ScreenGeometry.clamp(ScreenGeometry.flippedVertically(stored, containerHeight: bounds.height), to: bounds)
        return ScreenGeometry.isMeaningfulSelection(rect) ? rect : nil
    }

    var fixedPointSize: CGSize? {
        session.constraint.fixedSize?.pointSize(scale: scale)
    }

    var fixedPreview: CGRect? {
        guard let size = fixedPointSize, !isFixedPlaced, let location = mouseLocation else { return nil }
        return SelectionConstraintMath.fixedRect(size: size, centeredAt: location, within: bounds, scale: scale)
    }

    var toolbar: SelectionToolbar {
        SelectionToolbar(session: session, bounds: bounds, topInset: max(screen.frame.maxY - screen.visibleFrame.maxY, 0) + 10)
    }

    var showsToolbar: Bool {
        anchor == nil && !isMeasuring && draggedRegionID == nil && (mouseLocation != nil || NSScreen.underMouse == screen)
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
        hoveredToolbarItem = nil
        if let hovered = session.hoveredRegionID, session.regions.regions.contains(where: { $0.id == hovered && $0.displayID == displayID }) {
            session.hoveredRegionID = nil
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        mouseLocation = location
        isMeasureModifierHeld = event.modifierFlags.contains(.option)
        hoveredToolbarItem = showsToolbar ? toolbar.item(at: location) : nil
        updateHoveredRegion(at: location)
        requestLiveSample(at: location)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsToolbar, let item = toolbar.item(at: point) {
            activate(item)
            return
        }
        if event.modifierFlags.contains(.option) {
            beginMeasuring(at: point)
            return
        }
        measurement = nil
        lastDragPoint = point
        if let displayID, let region = session.regions.region(at: point, displayID: displayID) {
            draggedRegionID = region.id
            return
        }
        if let size = fixedPointSize {
            anchor = nil
            isFixedPlaced = true
            selection = SelectionConstraintMath.fixedRect(size: size, centeredAt: point, within: bounds, scale: scale)
            needsDisplay = true
            if event.clickCount >= 2, let selection {
                finishSelection(selection, keepModifierHeld: event.modifierFlags.contains(.command))
            }
            return
        }
        anchor = point
        current = point
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        mouseLocation = point
        requestLiveSample(at: point)
        if isMeasuring {
            updateMeasurement(to: point, locksAxis: event.modifierFlags.contains(.shift))
            return
        }
        if let draggedRegionID {
            session.moveRegion(id: draggedRegionID, by: CGVector(dx: point.x - lastDragPoint.x, dy: point.y - lastDragPoint.y), within: bounds)
            lastDragPoint = point
            return
        }
        if let size = fixedPointSize, isFixedPlaced {
            selection = SelectionConstraintMath.fixedRect(size: size, centeredAt: point, within: bounds, scale: scale)
        } else if isMovingSelection, let rect = selection {
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

    override func mouseUp(with event: NSEvent) {
        if isMeasuring {
            isMeasuring = false
            needsDisplay = true
            return
        }
        if draggedRegionID != nil {
            draggedRegionID = nil
            needsDisplay = true
            return
        }
        if isFixedPlaced {
            if let rect = selection, session.keepsSelection(keepModifierHeld: event.modifierFlags.contains(.command)) {
                keep(rect)
            }
            return
        }
        guard let rect = selection, ScreenGeometry.isMeaningfulSelection(rect) else {
            anchor = nil
            selection = nil
            needsDisplay = true
            return
        }
        finishSelection(rect, keepModifierHeld: event.modifierFlags.contains(.command))
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
        if session.isEnteringSize, handleSizeEntry(event) {
            return
        }
        switch event.keyCode {
        case KeyCode.escape:
            if measurement != nil, !isMeasuring {
                measurement = nil
                needsDisplay = true
            } else {
                onFinish(.single(.cancelled))
            }
        case KeyCode.space:
            if anchor != nil {
                isMovingSelection = true
            } else if options.allowsWindowMode, !event.isARepeat {
                onFinish(.single(.switchToWindow))
            }
        case KeyCode.returnKey, KeyCode.enter:
            confirm()
        case KeyCode.tab:
            if !event.isARepeat {
                session.toggleFreezeMode()
            }
        case KeyCode.delete, KeyCode.forwardDelete:
            if let hovered = session.hoveredRegionID {
                session.removeRegion(id: hovered)
            }
        case KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down:
            nudge(keyCode: event.keyCode, step: event.modifierFlags.contains(.shift) ? 10 : 1)
        default:
            if !event.isARepeat, handleCharacter(event.charactersIgnoringModifiers?.lowercased()) {
                return
            }
            super.keyDown(with: event)
        }
    }

    private func handleCharacter(_ character: String?) -> Bool {
        switch character {
        case "l":
            return selectLastRegion()
        case "g":
            Defaults[.showSelectionGuides].toggle()
        case "z":
            Defaults[.showMagnifier].toggle()
        case "a":
            session.cycleAspect()
            constraintChanged()
        case "f":
            session.cycleFixedSize()
            constraintChanged()
        case "s":
            session.beginSizeEntry()
        case "+", "=":
            guard options.allowsMultipleRegions else { return false }
            session.keepsRegions.toggle()
        default:
            return false
        }
        needsDisplay = true
        return true
    }

    private func handleSizeEntry(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case KeyCode.escape:
            session.cancelSizeEntry()
        case KeyCode.returnKey, KeyCode.enter:
            if session.commitSizeEntry() {
                constraintChanged()
            } else {
                NSSound.beep()
            }
        case KeyCode.delete:
            session.deleteBackwardInSizeEntry()
        default:
            guard let characters = event.characters, !characters.isEmpty else { return false }
            if !session.typeIntoSizeEntry(characters) {
                NSSound.beep()
            }
        }
        return true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == KeyCode.space {
            isMovingSelection = false
        }
    }

    private func activate(_ item: SelectionToolbar.Item) {
        switch item {
        case .ratio:
            session.cycleAspect()
            constraintChanged()
        case .size:
            session.cycleFixedSize()
            constraintChanged()
        case .customSize:
            session.beginSizeEntry()
        case .keepRegions:
            session.keepsRegions.toggle()
        case .freeze:
            session.toggleFreezeMode()
        }
        needsDisplay = true
    }

    private func constraintChanged() {
        if session.constraint.fixedSize != nil || isFixedPlaced {
            anchor = nil
            selection = nil
            isFixedPlaced = false
        } else if anchor != nil {
            updateSelection()
        }
        needsDisplay = true
    }

    private func confirm() {
        if !session.regions.isEmpty {
            let placed = selection.flatMap { ScreenGeometry.isMeaningfulSelection($0) ? $0 : nil }
            let pendingRegion = placed.flatMap { rect in displayID.map { SelectionRegion(id: 0, displayID: $0, rect: finalized(rect)) } }
            let areas = session.areas(including: pendingRegion)
            switch areas.count {
            case 0: onFinish(.single(.cancelled))
            case 1: onFinish(.single(.region(areas[0].screen, areas[0].rect)))
            default: onFinish(.regions(areas))
            }
            return
        }
        if let pending = pendingSelection {
            finishSelection(pending, keepModifierHeld: false, keeping: false)
        } else {
            onFinish(.single(.fullScreen(screen)))
        }
    }

    private var pendingSelection: CGRect? {
        if let rect = selection, ScreenGeometry.isMeaningfulSelection(rect) {
            return rect
        }
        if let preview = fixedPreview, ScreenGeometry.isMeaningfulSelection(preview) {
            return preview
        }
        return nil
    }

    func finalized(_ rect: CGRect) -> CGRect {
        session.constraint.fixedSize != nil ? SelectionConstraintMath.alignedToPixels(rect, scale: scale) : rect.integral
    }

    private func finishSelection(_ rect: CGRect, keepModifierHeld: Bool, keeping: Bool = true) {
        if keeping, session.keepsSelection(keepModifierHeld: keepModifierHeld) {
            keep(rect)
            return
        }
        onFinish(.single(.region(screen, ScreenGeometry.flippedVertically(finalized(rect), containerHeight: bounds.height))))
    }

    private func keep(_ rect: CGRect) {
        if let displayID {
            session.addRegion(finalized(rect), displayID: displayID)
        }
        anchor = nil
        selection = nil
        isFixedPlaced = false
        if let location = mouseLocation {
            updateHoveredRegion(at: location)
        }
        needsDisplay = true
    }

    private func updateHoveredRegion(at location: CGPoint) {
        guard let displayID else { return }
        session.hoveredRegionID = session.regions.region(at: location, displayID: displayID)?.id
    }

    private func requestLiveSample(at location: CGPoint) {
        guard magnifierSource == .liveSample, let sampler = options.liveSampler, let displayID else { return }
        sampler.request(.init(displayID: displayID, pixel: DisplayCoordinates.pixel(for: location, in: bounds, scale: scale), scale: scale))
    }

    private func selectLastRegion() -> Bool {
        guard let lastRegion else { return false }
        if selection == lastRegion {
            finishSelection(lastRegion, keepModifierHeld: false)
            return true
        }
        isMeasuring = false
        measurement = nil
        isFixedPlaced = false
        anchor = CGPoint(x: lastRegion.minX, y: lastRegion.minY)
        current = CGPoint(x: lastRegion.maxX, y: lastRegion.maxY)
        selection = lastRegion
        needsDisplay = true
        return true
    }

    private func beginMeasuring(at point: CGPoint) {
        anchor = nil
        selection = nil
        isFixedPlaced = false
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
        if isFixedPlaced, let rect = selection {
            selection = ScreenGeometry.moved(rect, by: delta, within: bounds)
        } else if anchor != nil {
            current = clampToBounds(CGPoint(x: current.x + delta.dx, y: current.y + delta.dy))
            updateSelection()
        } else if let location = mouseLocation {
            let moved = clampToBounds(CGPoint(x: location.x + delta.dx, y: location.y + delta.dy))
            mouseLocation = moved
            let global = CGPoint(x: moved.x + screen.frame.minX, y: moved.y + screen.frame.minY)
            CGWarpMouseCursorPosition(ScreenGeometry.cocoaPointToQuartz(global, primaryScreenHeight: NSScreen.primaryHeight))
            requestLiveSample(at: moved)
        }
        needsDisplay = true
    }

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func updateSelection() {
        guard let anchor else { return }
        let rect: CGRect
        if constrainsToSquare {
            rect = ScreenGeometry.squareRect(from: anchor, to: current)
        } else if let ratio = session.constraint.aspectRatio {
            rect = SelectionConstraintMath.aspectRect(from: anchor, to: current, ratio: ratio, within: bounds)
        } else {
            rect = ScreenGeometry.rect(from: anchor, to: current)
        }
        selection = ScreenGeometry.clamp(rect, to: bounds)
    }
}
