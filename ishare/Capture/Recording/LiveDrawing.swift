import AppKit
import Defaults
import SwiftUI

enum LiveDrawingTool: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case pen
    case highlighter
    case arrow

    var id: Self { self }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .pen, .arrow: 4
        case .highlighter: 18
        }
    }

    var opacity: Double {
        self == .highlighter ? 0.35 : 1
    }
}

enum LiveDrawingFade: Double, CaseIterable, Identifiable, Sendable {
    case never = 0
    case seconds2 = 2
    case seconds3 = 3
    case seconds5 = 5
    case seconds10 = 10

    var id: Self { self }

    var title: String {
        switch self {
        case .never: "Keep until cleared"
        case .seconds2: "After 2 seconds"
        case .seconds3: "After 3 seconds"
        case .seconds5: "After 5 seconds"
        case .seconds10: "After 10 seconds"
        }
    }
}

struct LiveDrawingMark: Identifiable, Hashable, Sendable {
    let id: UUID
    var tool: LiveDrawingTool
    var color: CaptureColor
    var points: [CGPoint]
    var finishedAt: Double?

    init(id: UUID = UUID(), tool: LiveDrawingTool, color: CaptureColor, points: [CGPoint], finishedAt: Double? = nil) {
        self.id = id
        self.tool = tool
        self.color = color
        self.points = points
        self.finishedAt = finishedAt
    }
}

struct LiveDrawingBoard: Sendable {
    static let fadeDuration: Double = 0.6
    static let minimumPointSpacing: CGFloat = 0.75

    var fadeDelay: Double
    private(set) var marks: [LiveDrawingMark] = []

    init(fadeDelay: Double) {
        self.fadeDelay = max(0, fadeDelay)
    }

    var isEmpty: Bool { marks.isEmpty }

    mutating func begin(at point: CGPoint, tool: LiveDrawingTool, color: CaptureColor) {
        marks.append(LiveDrawingMark(tool: tool, color: color, points: [point]))
    }

    mutating func extend(to point: CGPoint) {
        guard let index = marks.indices.last, marks[index].finishedAt == nil else { return }
        if marks[index].tool == .arrow {
            marks[index].points = [marks[index].points[0], point]
            return
        }
        guard let last = marks[index].points.last, last.distance(to: point) >= Self.minimumPointSpacing else { return }
        marks[index].points.append(point)
    }

    mutating func finish(at time: Double) {
        guard let index = marks.indices.last, marks[index].finishedAt == nil else { return }
        marks[index].finishedAt = time
    }

    mutating func undo() {
        _ = marks.popLast()
    }

    mutating func clear() {
        marks.removeAll()
    }

    func opacity(of mark: LiveDrawingMark, at time: Double) -> Double {
        guard fadeDelay > 0, let finishedAt = mark.finishedAt else { return 1 }
        let fading = time - finishedAt - fadeDelay
        guard fading > 0 else { return 1 }
        return max(0, 1 - fading / Self.fadeDuration)
    }

    mutating func prune(at time: Double) {
        let board = self
        marks.removeAll { board.opacity(of: $0, at: time) <= 0 }
    }

    func needsAnimation(at time: Double) -> Bool {
        fadeDelay > 0 && marks.contains { $0.finishedAt != nil && opacity(of: $0, at: time) > 0 }
    }

    static func arrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat, spread: CGFloat = .pi / 7) -> (CGPoint, CGPoint)? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) > 1 else { return nil }
        let angle = atan2(dy, dx)
        let left = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let right = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        return (left, right)
    }

    static func arrowHeadLength(lineWidth: CGFloat, start: CGPoint, end: CGPoint) -> CGFloat {
        min(max(14, lineWidth * 5), start.distance(to: end) * 0.5)
    }
}

final class LiveDrawingCanvasView: NSView {
    var board: () -> LiveDrawingBoard = { LiveDrawingBoard(fadeDelay: 0) }
    var onBegin: (CGPoint) -> Void = { _ in }
    var onDrag: (CGPoint) -> Void = { _ in }
    var onEnd: () -> Void = {}

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onBegin(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with _: NSEvent) {
        onEnd()
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let board = board()
        let now = RecordingClock.now
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for mark in board.marks {
            let alpha = CGFloat(mark.tool.opacity * board.opacity(of: mark, at: now))
            guard alpha > 0, let first = mark.points.first else { continue }
            context.setStrokeColor(mark.color.cgColor.copy(alpha: alpha) ?? mark.color.cgColor)
            context.setLineWidth(mark.tool.lineWidth)
            context.beginPath()
            context.move(to: first)
            if mark.points.count == 1 {
                context.addLine(to: first)
            } else {
                context.addLines(between: mark.points)
            }
            if mark.tool == .arrow, let last = mark.points.last {
                let length = LiveDrawingBoard.arrowHeadLength(lineWidth: mark.tool.lineWidth, start: first, end: last)
                if let (left, right) = LiveDrawingBoard.arrowHead(from: first, to: last, length: length) {
                    context.move(to: left)
                    context.addLine(to: last)
                    context.addLine(to: right)
                }
            }
            context.strokePath()
        }
    }
}

@MainActor
final class LiveDrawingToolbarModel: ObservableObject {
    static let palette = ["#FF3B30", "#FFCC00", "#34C759", "#0A84FF", "#FFFFFF", "#000000"]

    @Published var tool: LiveDrawingTool = Defaults[.liveDrawingTool] {
        didSet { Defaults[.liveDrawingTool] = tool }
    }

    @Published var colorHex: String = Defaults[.liveDrawingColor] {
        didSet { Defaults[.liveDrawingColor] = colorHex }
    }

    var color: CaptureColor {
        CaptureColor(hex: colorHex) ?? CaptureColor(red: 1, green: 0.23, blue: 0.19)
    }
}

struct LiveDrawingToolbar: View {
    @ObservedObject var model: LiveDrawingToolbarModel
    var onUndo: () -> Void
    var onClear: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LiveDrawingTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 18)
                }
                .adaptiveGlassButtonStyle(prominent: model.tool == tool)
                .help(tool.title.localized())
                .accessibilityLabel(Text(tool.title.localized()))
            }
            Divider().frame(height: 18)
            ForEach(LiveDrawingToolbarModel.palette, id: \.self) { hex in
                Button {
                    model.colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(cgColor: (CaptureColor(hex: hex) ?? model.color).cgColor))
                        .overlay(Circle().strokeBorder(.white.opacity(model.colorHex == hex ? 1 : 0.3), lineWidth: model.colorHex == hex ? 2.5 : 1))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(hex))
            }
            Divider().frame(height: 18)
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
            }
            .adaptiveGlassButtonStyle(prominent: false)
            .help("Undo".localized())
            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .adaptiveGlassButtonStyle(prominent: false)
            .help("Clear Drawing".localized())
            Button("Done".localized(), action: onDone)
                .adaptiveGlassButtonStyle(prominent: true)
                .help("Stop drawing (Esc)".localized())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlassCapsule()
        .accessibilityIdentifier("recording.drawing.toolbar")
    }
}

private final class LiveDrawingToolbarPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onUndo: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_: Any?) {
        onCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            onUndo()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class LiveDrawingCanvasPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LiveDrawingController {
    private static let frameInterval: Double = 1 / 30

    private var canvases: [(panel: NSPanel, view: LiveDrawingCanvasView)] = []
    private var toolbar: LiveDrawingToolbarPanel?
    private var board = LiveDrawingBoard(fadeDelay: 0)
    private var animationTimer: Timer?
    private var escapeMonitor: Any?
    private let toolbarModel = LiveDrawingToolbarModel()

    private(set) var isDrawing = false
    var onChange: (Bool) -> Void = { _ in }

    var windowIDs: [CGWindowID] {
        canvases.map { CGWindowID($0.panel.windowNumber) }.filter { $0 > 0 }
    }

    var isPrepared: Bool { !canvases.isEmpty }

    func prepare(screens: [NSScreen]) {
        tearDown()
        board = LiveDrawingBoard(fadeDelay: Defaults[.liveDrawingFadeDelay])
        canvases = screens.map(makeCanvas)
        canvases.forEach { $0.panel.orderFrontRegardless() }
    }

    func tearDown() {
        endDrawing()
        animationTimer?.invalidate()
        animationTimer = nil
        board.clear()
        canvases.forEach { $0.panel.orderOut(nil) }
        canvases.removeAll()
        toolbar?.orderOut(nil)
        toolbar = nil
    }

    func toggle() {
        isDrawing ? endDrawing() : beginDrawing()
    }

    func beginDrawing() {
        guard isPrepared, !isDrawing else { return }
        isDrawing = true
        board.fadeDelay = Defaults[.liveDrawingFadeDelay]
        canvases.forEach { $0.panel.ignoresMouseEvents = false }
        showToolbar()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.endDrawing() }
            return nil
        }
        onChange(true)
    }

    func endDrawing() {
        guard isDrawing else { return }
        isDrawing = false
        board.finish(at: RecordingClock.now)
        canvases.forEach { $0.panel.ignoresMouseEvents = true }
        toolbar?.orderOut(nil)
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
        scheduleAnimation()
        onChange(false)
    }

    private func makeCanvas(for screen: NSScreen) -> (panel: NSPanel, view: LiveDrawingCanvasView) {
        let frame = screen.frame
        let panel = LiveDrawingCanvasPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .recordingOverlay
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        let view = LiveDrawingCanvasView(frame: CGRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.board = { [weak self] in self?.board ?? LiveDrawingBoard(fadeDelay: 0) }
        view.onBegin = { [weak self] point in self?.begin(at: point) }
        view.onDrag = { [weak self] point in self?.extend(to: point) }
        view.onEnd = { [weak self] in self?.finishMark() }
        panel.contentView = view
        panel.setFrame(frame, display: false)
        return (panel, view)
    }

    private func begin(at point: CGPoint) {
        guard isDrawing else { return }
        board.begin(at: point, tool: toolbarModel.tool, color: toolbarModel.color)
        redraw()
    }

    private func extend(to point: CGPoint) {
        guard isDrawing else { return }
        board.extend(to: point)
        redraw()
    }

    private func finishMark() {
        board.finish(at: RecordingClock.now)
        redraw()
        scheduleAnimation()
    }

    private func undo() {
        board.undo()
        redraw()
    }

    private func clear() {
        board.clear()
        redraw()
    }

    private func redraw() {
        canvases.forEach { $0.view.needsDisplay = true }
    }

    private func scheduleAnimation() {
        guard animationTimer == nil, board.needsAnimation(at: RecordingClock.now) else { return }
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func animate() {
        let now = RecordingClock.now
        board.prune(at: now)
        redraw()
        if !board.needsAnimation(at: now) {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func showToolbar() {
        let screen = screenUnderPointer() ?? NSScreen.main
        guard let screen else { return }
        let toolbar = toolbar ?? makeToolbar()
        let size = toolbar.contentView?.fittingSize ?? toolbar.frame.size
        let origin = CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 16)
        toolbar.setFrame(CGRect(origin: origin, size: size), display: true)
        toolbar.makeKeyAndOrderFront(nil)
        self.toolbar = toolbar
    }

    private func makeToolbar() -> LiveDrawingToolbarPanel {
        let view = LiveDrawingToolbar(model: toolbarModel, onUndo: { [weak self] in self?.undo() }, onClear: { [weak self] in self?.clear() }, onDone: { [weak self] in self?.endDrawing() })
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let panel = LiveDrawingToolbarPanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.recordingOverlay.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.endDrawing() }
        panel.onUndo = { [weak self] in self?.undo() }
        return panel
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return canvases.map(\.panel).first { $0.frame.contains(location) }?.screen
    }
}
