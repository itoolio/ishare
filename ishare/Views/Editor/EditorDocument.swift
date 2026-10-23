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
    @Published var selectedIDs: Set<UUID> = []
    @Published var draft: Annotation?
    @Published var draftCrop: CGRect?
    @Published var editingText: TextEdit?
    @Published var arrowPath: ArrowPath = .straight
    @Published var arrowHead: ArrowHead = .filled
    @Published var doubleHeaded = false
    @Published var dashed = false
    @Published var spotlightShape: SpotlightShape = .rectangle
    @Published var dimAmount = Annotation.defaultDimAmount
    @Published var stamp: Stamp = .default
    @Published private(set) var cropAspect: CropAspect = .free

    struct TextEdit: Equatable {
        var origin: CGPoint
        var text: String
        var replacing: UUID?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var continuousChangeStart: Snapshot?
    private var toolBeforeCrop: EditorTool = .select

    init(image: CGImage, fileURL: URL?) {
        base = image
        self.fileURL = fileURL
        effectedBase = image
        let longest = CGFloat(max(image.width, image.height))
        lineWidth = max(4, (longest / 220).rounded())
        fontSize = max(18, (longest / 50).rounded())
    }

    var imageSize: CGSize { CGSize(width: base.width, height: base.height) }
    var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }
    var isCropping: Bool { tool == .crop }
    var visibleRect: CGRect { isCropping ? imageBounds : crop ?? imageBounds }
    var defaultStampSize: CGFloat { max(48, (CGFloat(max(base.width, base.height)) / 12).rounded()) }
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
        selectedIDs.formIntersection(annotations.map(\.id))
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
        if isCropping {
            draftCrop = crop ?? imageBounds
        }
        selectedID = nil
    }

    func beginContinuousChange() {
        if continuousChangeStart == nil {
            continuousChangeStart = snapshot
        }
    }

    func endContinuousChange() {
        guard let start = continuousChangeStart else { return }
        continuousChangeStart = nil
        guard !snapshot.matches(start) else { return }
        undoStack.append(start)
        redoStack.removeAll()
    }

    func updateAnnotations(where predicate: (Annotation) -> Bool, _ change: (inout Annotation) -> Void) {
        var updated = annotations
        for index in updated.indices where predicate(updated[index]) {
            change(&updated[index])
        }
        if continuousChangeStart != nil {
            annotations = updated
        } else {
            commit { annotations = updated }
        }
    }

    func updateSelection(_ change: (inout Annotation) -> Void) {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs
        updateAnnotations(where: { ids.contains($0.id) }, change)
    }

    var selectedID: UUID? {
        get { selectedIDs.count == 1 ? selectedIDs.first : nil }
        set { selectedIDs = newValue.map { [$0] } ?? [] }
    }

    var selectedAnnotation: Annotation? {
        selectedID.flatMap { id in annotations.first { $0.id == id } }
    }

    var selectedAnnotations: [Annotation] {
        annotations.filter { selectedIDs.contains($0.id) }
    }

    var selectionBounds: CGRect? {
        let bounds = selectedAnnotations.filter { !$0.hidden }.map(\.bounds)
        guard let first = bounds.first else { return nil }
        return bounds.dropFirst().reduce(first) { $0.union($1) }
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func setDimAmount(_ amount: Double) {
        dimAmount = amount
        updateAnnotations(where: \.isSpotlight) { $0.dimAmount = amount }
    }

    func select(tool newTool: EditorTool) {
        commitText()
        guard newTool != tool else { return }
        if isCropping {
            applyPendingCrop()
        }
        if newTool == .crop {
            toolBeforeCrop = tool
            draftCrop = crop ?? imageBounds
            selectedID = nil
        }
        tool = newTool
    }

    func applyPendingCrop() {
        guard isCropping else { return }
        if let draftCrop {
            applyCrop(draftCrop.integral == imageBounds ? nil : draftCrop)
        }
        draftCrop = nil
        tool = toolBeforeCrop
    }

    func cancelCropping() {
        guard isCropping else { return }
        draftCrop = nil
        tool = toolBeforeCrop
    }

    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        guard isCropping else { return }
        draftCrop = CropGeometry.fit(draftCrop ?? imageBounds, ratio: aspect.ratio(for: imageSize), bounds: imageBounds)
    }

    var cropRatio: CGFloat? {
        cropAspect.ratio(for: imageSize)
    }

    func commitPendingEdits() {
        commitText()
        applyPendingCrop()
    }

    enum Transform {
        case rotateLeft
        case rotateRight
        case flipHorizontal
        case flipVertical
    }

    func apply(_ transform: Transform) {
        commitText()
        guard let flattened = render() else { return }
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
        effectedBase = AnnotationRenderer.applyingEffects(annotations, to: base)
    }

    func effectedBase(excluding id: UUID) -> CGImage {
        AnnotationRenderer.applyingEffects(annotations.filter { $0.id != id }, to: base)
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

    func replaceAnnotations(with list: [Annotation]) {
        commit { annotations = list }
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
        let removable = Set(selectedAnnotations.filter { !$0.locked }.map(\.id))
        guard !removable.isEmpty else { return }
        delete(removable)
    }

    func delete(_ ids: Set<UUID>) {
        commit { annotations.removeAll { ids.contains($0.id) } }
        selectedIDs.subtract(ids)
    }

    func applyCrop(_ rect: CGRect?) {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let clamped = rect.map { ScreenGeometry.clamp($0.integral, to: bounds) }
        commit { crop = clamped.flatMap { ScreenGeometry.isMeaningfulSelection($0) ? $0 : nil } }
    }

    func resetCrop() {
        commit { crop = nil }
        if isCropping {
            draftCrop = imageBounds
        }
    }

    func annotation(at point: CGPoint, tolerance: CGFloat? = nil) -> Annotation? {
        let resolved = tolerance ?? max(8, lineWidth)
        let hits = annotations.reversed().filter { $0.isInteractive && $0.hitTest(point, tolerance: resolved) }
        return hits.first { !$0.isSpotlight } ?? hits.first
    }

    func move(_ id: UUID, by delta: CGVector) {
        move([id], by: delta)
    }

    func move(_ ids: Set<UUID>, by delta: CGVector) {
        commit {
            for index in annotations.indices where ids.contains(annotations[index].id) && !annotations[index].locked {
                annotations[index] = annotations[index].offset(by: delta)
            }
        }
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
        case .arrow: arrowPath == .curved ? .curvedArrow(start, ArrowGeometry.defaultControl(from: start, to: end), end) : .arrow(start, end)
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
        case .stamp: .stamp(stampRect(from: start, to: end), stamp)
        case .select, .text, .step, .crop, .cursor: nil
        }
        return shape.map {
            var annotation = Annotation(shape: $0, color: color, lineWidth: lineWidth, fontSize: fontSize, filled: filled && tool.supportsFill)
            annotation.arrowHead = arrowHead
            annotation.doubleHeaded = doubleHeaded
            annotation.dashed = dashed && annotation.supportsDash
            annotation.spotlightShape = spotlightShape
            annotation.dimAmount = dimAmount
            return annotation
        }
    }

    func stampRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        guard hypot(end.x - start.x, end.y - start.y) > 6 else {
            let size = defaultStampSize
            return CGRect(x: end.x - size / 2, y: end.y - size / 2, width: size, height: size)
        }
        return ScreenGeometry.squareRect(from: start, to: end)
    }

    func isSubstantial(_ annotation: Annotation) -> Bool {
        switch annotation.shape {
        case let .arrow(start, end), let .line(start, end), let .curvedArrow(start, _, end):
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
        AnnotationRenderer.render(base: base, annotations: annotations.filter { !$0.hidden }, crop: crop)
    }
}
