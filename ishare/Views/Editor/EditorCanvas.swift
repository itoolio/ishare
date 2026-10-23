import AppKit
import ishareCore
import SwiftUI

struct EditorCanvas: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var viewport: EditorViewport

    enum Interaction {
        case drawing
        case moving(Set<UUID>)
        case editingHandle(Annotation, EditHandle)
        case resizingCrop(CGRect, ResizeHandle)
        case movingCrop(CGRect)
        case newCrop
        case panning(CGSize)
    }

    static let handleSize: CGFloat = 9
    static let handleTolerance: CGFloat = 10

    @State private var interaction: Interaction?
    @State private var dragPoints: [CGPoint] = []
    @State private var moveOffset: CGVector = .zero
    @State private var liveAnnotation: Annotation?
    @State private var spaceHeld = false
    @State private var pinchStartZoom: CGFloat?
    @State private var hoverSnapTarget: CGRect?
    @State private var drawingSnapTarget: CGRect?
    @StateObject private var effectPreview = LiveEffectPreview()
    @FocusState private var textFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let transform = viewport.transform
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    draw(in: &context, transform: transform)
                }
                .background(CanvasEventMonitor(onScroll: handleScroll, onSpace: handleSpace))
                .contentShape(Rectangle())
                .gesture(canvasGesture(transform: transform))
                .simultaneousGesture(pinchGesture)
                .onContinuousHover { phase in
                    if case let .active(location) = phase {
                        viewport.pointerLocation = location
                        cursor(at: location, transform: transform).set()
                        updateHoverSnapTarget(at: location, transform: transform)
                    } else {
                        viewport.pointerLocation = nil
                        hoverSnapTarget = nil
                        NSCursor.arrow.set()
                    }
                }
                .accessibilityIdentifier("editor.canvas")

                if let edit = document.editingText {
                    textEditor(for: edit, transform: transform)
                }
            }
            .clipped()
            .onAppear { syncViewport(size: geometry.size) }
            .onChange(of: geometry.size) { _, size in syncViewport(size: size) }
            .onChange(of: document.visibleRect) { _, rect in viewport.update(visibleRect: rect) }
        }
    }

    private func syncViewport(size: CGSize) {
        viewport.update(visibleRect: document.visibleRect)
        viewport.update(containerSize: size)
    }

    private func textEditor(for edit: EditorDocument.TextEdit, transform: CanvasTransform) -> some View {
        let origin = transform.toView(edit.origin)
        return TextField(
            "Text".localized(),
            text: Binding(
                get: { document.editingText?.text ?? "" },
                set: { document.editingText?.text = $0 }
            ), axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: max(10, document.fontSize * transform.scale), weight: .semibold))
        .foregroundStyle(Color(nsColor: editingTextColor.nsColor))
        .frame(minWidth: 120, alignment: .leading)
        .fixedSize()
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1))
        .offset(x: origin.x - 4, y: origin.y - 4)
        .focused($textFocused)
        .onSubmit { document.commitText() }
        .onAppear { textFocused = true }
    }

    private var editingTextColor: RGBAColor {
        guard let id = document.editingText?.replacing, let annotation = document.annotations.first(where: { $0.id == id }) else {
            return document.textBackground ? document.color.contrastingText : document.color
        }
        if case .callout = annotation.shape {
            return annotation.color.contrastingText
        }
        return annotation.textBackground ? annotation.color.contrastingText : annotation.color
    }

    private func draw(in context: inout GraphicsContext, transform: CanvasTransform) {
        if document.straightenAngle != 0 {
            drawStraightenPreview(in: &context, transform: transform)
            return
        }
        let content = transform.contentRect
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 12, y: 4))
        shadowed.fill(Path(content), with: .color(.black))

        var clipped = context
        clipped.clip(to: Path(content))
        let backdrop = effectPreview.background ?? document.effectedBase
        clipped.draw(Image(decorative: backdrop, scale: 1), in: transform.toView(document.imageBounds))
        if let tile = effectPreview.tile {
            clipped.draw(Image(decorative: tile.image, scale: 1), in: transform.toView(tile.rect))
        }
        let annotations = visibleAnnotations
        for annotation in annotations where annotation.isMagnifier {
            guard case let .magnify(rect) = annotation.shape,
                let crop = AnnotationRenderer.magnifiedSource(for: rect, in: backdrop)
            else { continue }
            let lensRect = transform.toView(rect)
            var lens = clipped
            lens.clip(to: Path(ellipseIn: lensRect))
            lens.draw(Image(decorative: crop, scale: 1), in: lensRect)
        }
        clipped.withCGContext { cg in
            cg.concatenate(transform.cgTransform)
            AnnotationRenderer.draw(annotations, in: cg, source: nil, canvasSize: document.imageSize)
        }
        if let snapOutline = interaction == nil ? hoverSnapTarget : drawingSnapTarget {
            drawSnapOutline(snapOutline, in: &context, transform: transform)
        }
        if document.isCropping {
            drawCropOverlay(in: &context, transform: transform)
        } else {
            let selected = selectedAnnotations
            for annotation in selected {
                drawSelection(of: annotation, showsHandles: selected.count == 1 && !annotation.locked, in: &context, transform: transform)
            }
        }
    }

    private func drawSnapOutline(_ rect: CGRect, in context: inout GraphicsContext, transform: CanvasTransform) {
        let path = Path(roundedRect: transform.toView(rect).insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3)
        context.fill(path, with: .color(.accentColor.opacity(0.07)))
        context.stroke(path, with: .color(.accentColor.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func drawStraightenPreview(in context: inout GraphicsContext, transform: CanvasTransform) {
        let content = transform.contentRect
        let imageRect = transform.toView(document.imageBounds)
        let center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        var clipped = context
        clipped.clip(to: Path(content))
        var rotated = clipped
        rotated.translateBy(x: center.x, y: center.y)
        rotated.rotate(by: .degrees(document.straightenAngle))
        rotated.translateBy(x: -center.x, y: -center.y)
        rotated.draw(Image(decorative: document.effectedBase, scale: 1), in: imageRect)
        rotated.withCGContext { cg in
            cg.concatenate(transform.cgTransform)
            AnnotationRenderer.draw(visibleAnnotations, in: cg, source: nil, canvasSize: document.imageSize)
        }
        let output = StraightenGeometry.outputSize(for: document.imageSize, degrees: document.straightenAngle)
        let kept = CGRect(
            x: center.x - output.width * transform.scale / 2, y: center.y - output.height * transform.scale / 2, width: output.width * transform.scale,
            height: output.height * transform.scale)
        var outside = Path(content.union(imageRect))
        outside.addRect(kept)
        clipped.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        var grid = Path()
        for (start, end) in CropGeometry.thirds(of: kept) {
            grid.move(to: start)
            grid.addLine(to: end)
        }
        clipped.stroke(grid, with: .color(.white.opacity(0.45)), lineWidth: 0.75)
        clipped.stroke(Path(kept), with: .color(.white), lineWidth: 1.5)
    }

    private var snapsShapes: Bool {
        document.smartShapesActive && !NSEvent.modifierFlags.contains(.command)
    }

    private func updateHoverSnapTarget(at location: CGPoint, transform: CanvasTransform) {
        guard interaction == nil, snapsShapes, !spaceHeld else {
            hoverSnapTarget = nil
            return
        }
        hoverSnapTarget = SmartShapes.candidate(at: transform.toImage(location), in: document.snapTargets, tolerance: transform.toImage(SmartShapes.snapDistance))
    }

    private func snapped(from start: CGPoint, to end: CGPoint) -> (start: CGPoint, end: CGPoint) {
        guard snapsShapes, !document.snapTargets.isEmpty else {
            drawingSnapTarget = nil
            return (start, end)
        }
        let threshold = viewport.transform.toImage(SmartShapes.snapDistance)
        let corners = SmartShapes.snappedCorners(from: start, to: end, targets: document.snapTargets, threshold: threshold)
        drawingSnapTarget = SmartShapes.matchedTarget(for: ScreenGeometry.rect(from: corners.start, to: corners.end), in: document.snapTargets)
        return corners
    }

    private func drawSelection(of annotation: Annotation, showsHandles: Bool, in context: inout GraphicsContext, transform: CanvasTransform) {
        let outline = transform.toView(annotation.bounds).insetBy(dx: -6, dy: -6)
        let outlineColor: Color = annotation.locked ? .secondary : .accentColor
        context.stroke(Path(outline), with: .color(outlineColor), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        guard showsHandles else { return }
        if case let .curvedArrow(start, control, end) = annotation.shape {
            var guide = Path()
            guide.move(to: transform.toView(start))
            guide.addLine(to: transform.toView(ArrowGeometry.midpoint(from: start, control: control, to: end)))
            guide.addLine(to: transform.toView(end))
            context.stroke(guide, with: .color(.accentColor.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        for (handle, point) in annotation.editHandles {
            drawHandle(at: transform.toView(point), round: handle == .control || handle == .start || handle == .end, in: &context)
        }
    }

    private func drawHandle(at point: CGPoint, round: Bool, in context: inout GraphicsContext) {
        let size = Self.handleSize
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let path = round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2)
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: 2))
        shadowed.fill(path, with: .color(.white))
        context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
    }

    private func drawCropOverlay(in context: inout GraphicsContext, transform: CanvasTransform) {
        let crop = document.draftCrop ?? document.crop ?? document.imageBounds
        let rect = transform.toView(crop)
        var outside = Path(transform.contentRect)
        outside.addRect(rect)
        context.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        var guides = Path()
        for (start, end) in CropGeometry.thirds(of: rect) {
            guides.move(to: start)
            guides.addLine(to: end)
        }
        context.stroke(guides, with: .color(.white.opacity(0.45)), lineWidth: 0.75)
        context.stroke(Path(rect), with: .color(.white), lineWidth: 1.5)
        for handle in ResizeHandle.allCases {
            drawHandle(at: handle.point(in: rect), round: false, in: &context)
        }
        let label = Text(verbatim: "\(Int(crop.width.rounded())) × \(Int(crop.height.rounded()))")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
        let resolved = context.resolve(label)
        let size = resolved.measure(in: CGSize(width: 400, height: 40))
        let placed = CGRect(x: rect.minX + 12, y: rect.minY + 12, width: size.width + 16, height: size.height + 6)
        context.fill(Path(roundedRect: placed, cornerRadius: placed.height / 2), with: .color(.black.opacity(0.7)))
        context.draw(resolved, in: placed.insetBy(dx: 8, dy: 3))
    }

    private var selectedAnnotation: Annotation? {
        guard let id = document.selectedID else { return nil }
        return visibleAnnotations.first { $0.id == id && !$0.locked }
    }

    private var selectedAnnotations: [Annotation] {
        visibleAnnotations.filter { document.selectedIDs.contains($0.id) }
    }

    private var visibleAnnotations: [Annotation] {
        var list = document.annotations.filter { annotation in
            if annotation.hidden {
                return false
            }
            if case .text = annotation.shape, document.editingText?.replacing == annotation.id {
                return false
            }
            return true
        }.map { annotation -> Annotation in
            guard document.editingText?.replacing == annotation.id, case let .callout(tail, rect, _) = annotation.shape else { return annotation }
            var hidden = annotation
            hidden.shape = .callout(tail, rect, "")
            return hidden
        }
        if case let .moving(ids) = interaction {
            for index in list.indices where ids.contains(list[index].id) && !list[index].locked {
                list[index] = list[index].offset(by: moveOffset)
            }
        }
        if let liveAnnotation, let index = list.firstIndex(where: { $0.id == liveAnnotation.id }) {
            list[index] = liveAnnotation
        }
        if let draft = document.draft {
            list.append(draft)
        }
        return list
    }

    private func cursor(at location: CGPoint, transform: CanvasTransform) -> NSCursor {
        if spaceHeld {
            if case .panning = interaction { return .closedHand }
            return .openHand
        }
        let point = transform.toImage(location)
        let tolerance = transform.toImage(Self.handleTolerance)
        if document.isCropping {
            let crop = document.draftCrop ?? document.imageBounds
            if let handle = CropGeometry.handle(at: point, in: crop, tolerance: tolerance) {
                return resizeCursor(for: handle)
            }
            return crop.contains(point) ? .openHand : .crosshair
        }
        if let selected = selectedAnnotation, selected.editHandle(at: point, tolerance: tolerance) != nil {
            return .pointingHand
        }
        switch document.tool {
        case .select: return .arrow
        case .text: return .iBeam
        default: return .crosshair
        }
    }

    private func resizeCursor(for handle: ResizeHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition =
            switch handle {
            case .topLeft: .topLeft
            case .top: .top
            case .topRight: .topRight
            case .right: .right
            case .bottomRight: .bottomRight
            case .bottom: .bottom
            case .bottomLeft: .bottomLeft
            case .left: .left
            }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    private func handleScroll(_ delta: CGVector, at location: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            let factor = exp(delta.dy / 200)
            viewport.setZoom(viewport.effectiveZoom * factor, anchor: location)
        } else {
            viewport.pan(by: delta)
        }
    }

    private func handleSpace(_ down: Bool) -> Bool {
        guard document.editingText == nil else { return false }
        spaceHeld = down
        if down {
            NSCursor.openHand.set()
        }
        return true
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartZoom ?? viewport.effectiveZoom
                pinchStartZoom = start
                viewport.setZoom(start * value.magnification, anchor: value.startLocation)
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }

    private func canvasGesture(transform: CanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let start = transform.toImage(value.startLocation)
                let current = transform.toImage(value.location)
                if interaction == nil {
                    dragPoints = [start]
                    began(at: start, transform: transform)
                }
                if case let .panning(last) = interaction {
                    viewport.pan(by: CGVector(dx: value.translation.width - last.width, dy: value.translation.height - last.height))
                    interaction = .panning(value.translation)
                    return
                }
                dragPoints.append(current)
                changed(from: start, to: current)
            }
            .onEnded { value in
                let start = dragPoints.first ?? transform.toImage(value.startLocation)
                let end = transform.toImage(value.location)
                if interaction != nil {
                    ended(from: start, to: end, transform: transform)
                }
                interaction = nil
                dragPoints = []
            }
    }

    private func began(at point: CGPoint, transform: CanvasTransform) {
        if spaceHeld {
            interaction = .panning(.zero)
            return
        }
        if document.editingText != nil {
            document.commitText()
        }
        let tolerance = transform.toImage(Self.handleTolerance)
        if document.isCropping {
            let crop = document.draftCrop ?? document.imageBounds
            if let handle = CropGeometry.handle(at: point, in: crop, tolerance: tolerance) {
                interaction = .resizingCrop(crop, handle)
            } else if crop.contains(point) {
                interaction = .movingCrop(crop)
            } else {
                interaction = .newCrop
            }
            return
        }
        if document.tool != .text, let selected = document.selectedAnnotation, selected.isInteractive,
            let handle = selected.editHandle(at: point, tolerance: tolerance)
        {
            interaction = .editingHandle(selected, handle)
            if selected.isEffect {
                effectPreview.begin(for: selected, background: document.effectedBase(excluding: selected.id), zoom: viewport.effectiveZoom)
            }
            return
        }
        switch document.tool {
        case .select:
            beginSelecting(at: point, transform: transform)
        default:
            document.selectedID = nil
            interaction = .drawing
        }
    }

    private func beginSelecting(at point: CGPoint, transform: CanvasTransform) {
        let hit = document.annotation(at: point, tolerance: max(transform.toImage(8), document.lineWidth))
        moveOffset = .zero
        let modifiers = NSEvent.modifierFlags
        let extendsSelection = modifiers.contains(.command) || modifiers.contains(.shift)
        guard let hit else {
            if !extendsSelection {
                document.selectedIDs = []
            }
            interaction = .drawing
            return
        }
        if extendsSelection {
            document.toggleSelection(hit.id)
            interaction = .drawing
            return
        }
        if !document.selectedIDs.contains(hit.id) {
            document.selectedID = hit.id
        }
        let group = document.selectedIDs
        interaction = .moving(group)
        if group.count == 1, hit.isEffect {
            effectPreview.begin(for: hit, background: document.effectedBase(excluding: hit.id), zoom: viewport.effectiveZoom)
        }
    }

    private func changed(from start: CGPoint, to current: CGPoint) {
        switch interaction {
        case let .moving(ids):
            moveOffset = CGVector(dx: current.x - start.x, dy: current.y - start.y)
            if effectPreview.isActive, let id = ids.first, let moving = document.annotations.first(where: { $0.id == id }) {
                effectPreview.update(moving.offset(by: moveOffset))
            }
        case let .editingHandle(original, handle):
            let edited = original.editing(handle, to: current)
            liveAnnotation = edited
            effectPreview.update(edited)
        case let .resizingCrop(original, handle):
            document.draftCrop = CropGeometry.resize(original, handle: handle, to: current, ratio: document.cropRatio, bounds: document.imageBounds)
        case let .movingCrop(original):
            document.draftCrop = ScreenGeometry.moved(original, by: CGVector(dx: current.x - start.x, dy: current.y - start.y), within: document.imageBounds)
        case .newCrop:
            let anchor = CGPoint(x: min(max(start.x, 0), document.imageSize.width), y: min(max(start.y, 0), document.imageSize.height))
            let rect = CropGeometry.rect(anchor: anchor, to: current, ratio: document.cropRatio, bounds: document.imageBounds)
            if rect.width >= CropGeometry.minimumSize, rect.height >= CropGeometry.minimumSize {
                document.draftCrop = rect
            }
        case .drawing:
            switch document.tool {
            case .select, .text, .step, .cursor, .crop:
                break
            default:
                let corners = snapped(from: start, to: current)
                let draft = document.makeAnnotation(tool: document.tool, from: corners.start, to: corners.end, points: dragPoints)
                document.draft = draft
                if let draft, draft.isEffect {
                    if effectPreview.isActive {
                        effectPreview.update(draft)
                    } else {
                        effectPreview.begin(for: draft, background: document.effectedBase, zoom: viewport.effectiveZoom)
                    }
                }
            }
        case .panning, nil:
            break
        }
    }

    private func ended(from start: CGPoint, to end: CGPoint, transform: CanvasTransform) {
        switch interaction {
        case let .moving(ids):
            if hypot(moveOffset.dx, moveOffset.dy) > 0.5 {
                document.move(ids, by: moveOffset)
            }
            moveOffset = .zero
        case .editingHandle:
            if let liveAnnotation {
                document.replace(liveAnnotation)
            }
            liveAnnotation = nil
        case .resizingCrop, .movingCrop, .newCrop, .panning, nil:
            break
        case .drawing:
            finishDrawing(from: start, to: end, transform: transform)
        }
        effectPreview.end()
    }

    private func finishDrawing(from start: CGPoint, to end: CGPoint, transform: CanvasTransform) {
        switch document.tool {
        case .select, .crop:
            break
        case .text:
            let tolerance = max(transform.toImage(8), document.lineWidth)
            if let existing = document.annotation(at: end, tolerance: tolerance), case let .text(origin, text) = existing.shape {
                document.editingText = .init(origin: origin, text: text, replacing: existing.id)
            } else if let existing = document.annotation(at: end, tolerance: tolerance), case let .callout(_, rect, text) = existing.shape {
                document.editingText = .init(origin: AnnotationRenderer.calloutTextOrigin(for: rect, fontSize: existing.fontSize), text: text, replacing: existing.id)
            } else {
                document.beginText(at: end)
            }
        case .step:
            document.add(Annotation(shape: .step(end, document.nextStepNumber), color: document.color, lineWidth: document.lineWidth, fontSize: document.fontSize))
        case .cursor:
            document.add(Annotation(shape: .cursor(end), color: document.color, lineWidth: document.lineWidth, fontSize: document.fontSize))
        case .callout:
            if let draft = document.makeAnnotation(tool: .callout, from: start, to: end, points: []), document.isSubstantial(draft),
                case let .callout(_, rect, _) = draft.shape
            {
                document.add(draft)
                document.editingText = .init(origin: AnnotationRenderer.calloutTextOrigin(for: rect, fontSize: draft.fontSize), text: "", replacing: draft.id)
            }
            document.draft = nil
        default:
            let corners = snapped(from: start, to: end)
            drawingSnapTarget = nil
            if let draft = document.makeAnnotation(tool: document.tool, from: corners.start, to: corners.end, points: dragPoints), document.isSubstantial(draft) {
                document.add(draft)
                if document.tool == .stamp || document.tool == .spotlight {
                    document.selectedID = draft.id
                }
            }
            document.draft = nil
        }
    }
}
