import AppKit
import Combine
import Defaults

@MainActor
final class EditorDocument: ObservableObject {
    struct Snapshot {
        var base: CGImage
        var annotations: [Annotation]
        var crop: CGRect?

        func matches(_ other: Snapshot) -> Bool {
            base === other.base && annotations == other.annotations && crop == other.crop
        }
    }

    @Published private(set) var base: CGImage
    let fileURL: URL?
    @Published private(set) var annotations: [Annotation] = []
    @Published private(set) var crop: CGRect?
    @Published private(set) var effectedBase: CGImage
    @Published var tool: EditorTool = .arrow
    @Published var color: RGBAColor = .red
    @Published var lineWidth: CGFloat = 6
    @Published var fontSize: CGFloat = 36
    @Published var filled = false
    @Published var textBackground = false
    @Published var selectedID: UUID?
    @Published var draft: Annotation?
    @Published var draftCrop: CGRect?
    @Published var editingText: TextEdit?

    struct TextEdit: Equatable {
        var origin: CGPoint
        var text: String
        var replacing: UUID?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(image: CGImage, fileURL: URL?) {
        base = image
        self.fileURL = fileURL
        effectedBase = image
        let longest = CGFloat(max(image.width, image.height))
        lineWidth = max(3, (longest / 400).rounded())
        fontSize = max(18, (longest / 50).rounded())
    }

    var imageSize: CGSize { CGSize(width: base.width, height: base.height) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasChanges: Bool { !annotations.isEmpty || crop != nil }
    var nextStepNumber: Int {
        (annotations.compactMap { annotation -> Int? in
            if case let .step(_, number) = annotation.shape { return number }
            return nil
        }.max() ?? 0) + 1
    }

    private var snapshot: Snapshot { Snapshot(base: base, annotations: annotations, crop: crop) }

    private func commit(_ change: () -> Void) {
        let before = snapshot
        let effectsBefore = annotations.filter(\.isEffect)
        change()
        guard !snapshot.matches(before) else { return }
        undoStack.append(before)
        redoStack.removeAll()
        if annotations.filter(\.isEffect) != effectsBefore || base !== before.base {
            refreshEffects()
        }
    }

    private func restore(_ snapshot: Snapshot) {
        let effectsBefore = annotations.filter(\.isEffect)
        let baseChanged = base !== snapshot.base
        base = snapshot.base
        annotations = snapshot.annotations
        crop = snapshot.crop
        if annotations.filter(\.isEffect) != effectsBefore || baseChanged {
            refreshEffects()
        }
        selectedID = nil
    }

    enum Transform {
        case rotateLeft
        case rotateRight
        case flipHorizontal
        case flipVertical
    }

    func apply(_ transform: Transform) {
        commitText()
        guard let flattened = AnnotationRenderer.render(base: base, annotations: annotations, crop: crop) else { return }
        let transformed: CGImage = switch transform {
        case .rotateLeft: ImageProcessing.rotated(flattened, clockwise: false)
        case .rotateRight: ImageProcessing.rotated(flattened, clockwise: true)
        case .flipHorizontal: ImageProcessing.flipped(flattened, horizontally: true)
        case .flipVertical: ImageProcessing.flipped(flattened, horizontally: false)
        }
        commit {
            base = transformed
            annotations = []
            crop = nil
        }
        selectedID = nil
    }

    private func refreshEffects() {
        effectedBase = AnnotationRenderer.applyingEffects(annotations.filter(\.isEffect), to: base)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    func add(_ annotation: Annotation) {
        commit { annotations.append(annotation) }
    }

    func replace(_ annotation: Annotation) {
        commit {
            if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
                annotations[index] = annotation
            }
        }
    }

    func deleteSelection() {
        guard let selectedID else { return }
        commit { annotations.removeAll { $0.id == selectedID } }
        self.selectedID = nil
    }

    func applyCrop(_ rect: CGRect?) {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let clamped = rect.map { ScreenGeometry.clamp($0.integral, to: bounds) }
        commit { crop = clamped.flatMap { ScreenGeometry.isMeaningfulSelection($0) ? $0 : nil } }
    }

    func resetCrop() {
        commit { crop = nil }
    }

    func annotation(at point: CGPoint) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point, tolerance: max(8, lineWidth)) }
    }

    func move(_ id: UUID, by delta: CGVector) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let moved = annotations[index].offset(by: delta)
        commit { annotations[index] = moved }
    }

    func clearAll() {
        commit {
            annotations.removeAll()
            crop = nil
        }
    }

    func beginText(at point: CGPoint) {
        editingText = TextEdit(origin: point, text: "", replacing: nil)
    }

    func commitText() {
        guard let edit = editingText else { return }
        editingText = nil
        let trimmed = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let replacing = edit.replacing, var existing = annotations.first(where: { $0.id == replacing }) {
            if case let .callout(tail, rect, _) = existing.shape {
                existing.shape = .callout(tail, rect, trimmed)
                replace(existing)
                return
            }
            if trimmed.isEmpty {
                commit { annotations.removeAll { $0.id == replacing } }
            } else {
                existing.shape = .text(edit.origin, trimmed)
                replace(existing)
            }
            return
        }
        guard !trimmed.isEmpty else { return }
        add(Annotation(shape: .text(edit.origin, trimmed), color: color, lineWidth: lineWidth, fontSize: fontSize, textBackground: textBackground))
    }

    func makeAnnotation(tool: EditorTool, from start: CGPoint, to end: CGPoint, points: [CGPoint]) -> Annotation? {
        let rect = ScreenGeometry.rect(from: start, to: end)
        let shape: Annotation.Shape? = switch tool {
        case .arrow: .arrow(start, end)
        case .line: .line(start, end)
        case .rectangle: .rectangle(rect)
        case .ellipse: .ellipse(rect)
        case .highlight: .highlight(rect)
        case .pen: .pen(points)
        case .marker: .marker(points)
        case .blur: .blur(rect)
        case .pixelate: .pixelate(rect)
        case .eraser: .eraser(rect)
        case .spotlight: .spotlight(rect)
        case .magnify: .magnify(ScreenGeometry.squareRect(from: start, to: end))
        case .callout: .callout(start, CGRect(x: end.x, y: end.y, width: max(fontSize * 5, 160), height: fontSize * 1.9), "")
        case .select, .text, .step, .crop, .cursor: nil
        }
        return shape.map { Annotation(shape: $0, color: color, lineWidth: lineWidth, fontSize: fontSize, filled: filled && tool.supportsFill) }
    }

    func isSubstantial(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case let .arrow(start, end), let .line(start, end):
            hypot(end.x - start.x, end.y - start.y) > 3
        case let .pen(points), let .marker(points):
            !points.isEmpty
        case let .callout(tail, rect, _):
            hypot(rect.minX - tail.x, rect.minY - tail.y) > 10
        default:
            ScreenGeometry.isMeaningfulSelection(annotation.bounds, minimum: 3)
        }
    }

    func render() -> CGImage? {
        AnnotationRenderer.render(base: base, annotations: annotations, crop: crop)
    }
}
