import Defaults
import SwiftUI

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    var onDone: () -> Void
    var onDiscard: () -> Void
    var onCopy: () -> Void
    var onUpload: () -> Void

    @State private var dragStart: CGPoint?
    @State private var dragPoints: [CGPoint] = []
    @State private var moveOffset: CGVector = .zero
    @State private var movingID: UUID?
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            GeometryReader { geometry in
                canvasArea(in: geometry.size)
            }
            .background(Color.black.opacity(0.18))
            bottomBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(.background)
        .onDeleteCommand {
            if document.editingText == nil {
                document.deleteSelection()
            }
        }
        .onExitCommand {
            if document.editingText != nil {
                document.commitText()
            } else {
                document.selectedID = nil
            }
        }
    }

    private var toolbar: some View {
        AdaptiveGlassContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        document.commitText()
                        document.tool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 28)
                            .foregroundStyle(document.tool == tool ? Color.white : Color.primary)
                            .background {
                                if document.tool == tool {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.title.localized()) (\(String(tool.shortcut).uppercased()))")
                    .keyboardShortcut(document.editingText == nil ? KeyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: []) : nil)
                    .accessibilityIdentifier("editor.tool.\(tool.rawValue)")
                }
            }
            .padding(5)
            .adaptiveGlass(cornerRadius: 12)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(RGBAColor.palette, id: \.self) { swatch in
                    Button {
                        document.color = swatch
                        recolorSelection(swatch)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: swatch.nsColor))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(document.color == swatch ? 0.9 : 0.15), lineWidth: document.color == swatch ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: document.color.nsColor) },
                    set: { document.color = RGBAColor(NSColor($0)) }
                ))
                .labelsHidden()
                .frame(width: 28)
            }
            Divider().frame(height: 20)
            if document.tool.supportsFill {
                Toggle(isOn: $document.filled) {
                    Image(systemName: "paintbrush.pointed.fill")
                }
                .toggleStyle(.button)
                .help("Fill".localized())
            }
            if document.tool == .text {
                Toggle(isOn: $document.textBackground) {
                    Image(systemName: "character.textbox")
                }
                .toggleStyle(.button)
                .help("Text background".localized())
            }
            if document.tool.usesFont || document.tool == .cursor {
                Label("Size".localized(), systemImage: "textformat.size")
                    .labelStyle(.iconOnly)
                Slider(value: $document.fontSize, in: 12 ... 160)
                    .frame(width: 110)
            } else {
                Label("Width".localized(), systemImage: "lineweight")
                    .labelStyle(.iconOnly)
                Slider(value: $document.lineWidth, in: 1 ... 40)
                    .frame(width: 110)
            }
            Divider().frame(height: 20)
            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.canUndo)
                .help("Undo".localized())
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.canRedo)
                .help("Redo".localized())
            Menu {
                Button("Rotate Left".localized()) { document.apply(.rotateLeft) }
                Button("Rotate Right".localized()) { document.apply(.rotateRight) }
                Divider()
                Button("Flip Horizontally".localized()) { document.apply(.flipHorizontal) }
                Button("Flip Vertically".localized()) { document.apply(.flipVertical) }
                if document.crop != nil {
                    Divider()
                    Button("Reset Crop".localized()) { document.resetCrop() }
                }
            } label: {
                Image(systemName: "rotate.right")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Transform".localized())
            Spacer()
            Button(role: .destructive, action: onDiscard) {
                Label("Discard".localized(), systemImage: "trash")
            }
            .accessibilityIdentifier("editor.discard")
            Button(action: onCopy) {
                Label("Copy".localized(), systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            Button(action: onUpload) {
                Label("Upload".localized(), systemImage: "icloud.and.arrow.up")
            }
            .keyboardShortcut("u", modifiers: .command)
            Button(action: {
                document.commitText()
                onDone()
            }) {
                Label("Done".localized(), systemImage: "checkmark")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .adaptiveGlassButtonStyle(prominent: true)
            .accessibilityIdentifier("editor.done")
        }
        .controlSize(.regular)
    }

    private func recolorSelection(_ color: RGBAColor) {
        guard let id = document.selectedID, var annotation = document.annotations.first(where: { $0.id == id }) else { return }
        annotation.color = color
        document.replace(annotation)
    }

    private func fitRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        let available = CGSize(width: max(1, container.width - 40), height: max(1, container.height - 40))
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2
        let naturalScale = 1 / screenScale
        let scale = min(naturalScale, available.width / imageSize.width, available.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func canvasArea(in container: CGSize) -> some View {
        let fit = fitRect(for: document.imageSize, in: container)
        let scale = fit.width / document.imageSize.width
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                context.draw(Image(decorative: document.effectedBase, scale: 1), in: CGRect(origin: .zero, size: size))
                let annotations = visibleAnnotations
                for annotation in annotations where annotation.isSpotlight || annotation.isMagnifier {
                    guard annotation.isMagnifier, case let .magnify(rect) = annotation.shape,
                          let crop = AnnotationRenderer.magnifiedSource(for: rect, in: document.effectedBase)
                    else { continue }
                    let scaled = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
                    var lens = context
                    lens.clip(to: Path(ellipseIn: scaled))
                    lens.draw(Image(decorative: crop, scale: 1), in: scaled)
                }
                context.withCGContext { cg in
                    cg.scaleBy(x: scale, y: scale)
                    AnnotationRenderer.draw(annotations, in: cg, source: nil, canvasSize: document.imageSize)
                    if let selected = selectedAnnotation {
                        cg.setStrokeColor(NSColor.controlAccentColor.cgColor)
                        cg.setLineWidth(2 / scale)
                        cg.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
                        cg.stroke(selected.bounds.insetBy(dx: -6 / scale, dy: -6 / scale))
                    }
                }
                drawCrop(in: &context, size: size, scale: scale)
            }
            .frame(width: fit.width, height: fit.height)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .contentShape(Rectangle())
            .gesture(canvasGesture(scale: scale))
            .onContinuousHover { phase in
                if case .active = phase {
                    cursor(for: document.tool).set()
                } else {
                    NSCursor.arrow.set()
                }
            }

            if let edit = document.editingText {
                TextField("Text".localized(), text: Binding(
                    get: { document.editingText?.text ?? "" },
                    set: { document.editingText?.text = $0 }
                ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: max(10, document.fontSize * scale), weight: .semibold))
                    .foregroundStyle(Color(nsColor: editingTextColor.nsColor))
                    .frame(minWidth: 120, alignment: .leading)
                    .fixedSize()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1))
                    .offset(x: edit.origin.x * scale - 4, y: edit.origin.y * scale - 4)
                    .focused($textFocused)
                    .onSubmit { document.commitText() }
                    .onAppear { textFocused = true }
            }
        }
        .frame(width: fit.width, height: fit.height, alignment: .topLeading)
        .position(x: fit.midX, y: fit.midY)
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

    private func cursor(for tool: EditorTool) -> NSCursor {
        switch tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
    }

    private var selectedAnnotation: Annotation? {
        guard let id = document.selectedID, var annotation = document.annotations.first(where: { $0.id == id }) else { return nil }
        if movingID == id {
            annotation = annotation.offset(by: moveOffset)
        }
        return annotation
    }

    private var visibleAnnotations: [Annotation] {
        var list = document.annotations.filter { annotation in
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
        if let movingID, let index = list.firstIndex(where: { $0.id == movingID }) {
            list[index] = list[index].offset(by: moveOffset)
        }
        if let draft = document.draft {
            list.append(draft)
        }
        return list
    }

    private func drawCrop(in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        guard let crop = document.draftCrop ?? document.crop else { return }
        let rect = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
        var outside = Path(CGRect(origin: .zero, size: size))
        outside.addRect(rect)
        context.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        context.stroke(Path(rect), with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }

    private func canvasGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                let current = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                if dragStart == nil {
                    dragStart = start
                    dragPoints = [start]
                    began(at: start)
                }
                dragPoints.append(current)
                changed(from: start, to: current)
            }
            .onEnded { value in
                let start = dragStart ?? CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                let end = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                ended(from: start, to: end)
                dragStart = nil
                dragPoints = []
            }
    }

    private func began(at point: CGPoint) {
        if document.editingText != nil {
            document.commitText()
        }
        switch document.tool {
        case .select:
            document.selectedID = document.annotation(at: point)?.id
            movingID = document.selectedID
            moveOffset = .zero
        default:
            document.selectedID = nil
        }
    }

    private func changed(from start: CGPoint, to current: CGPoint) {
        switch document.tool {
        case .select:
            if movingID != nil {
                moveOffset = CGVector(dx: current.x - start.x, dy: current.y - start.y)
            }
        case .crop:
            document.draftCrop = ScreenGeometry.clamp(ScreenGeometry.rect(from: start, to: current), to: CGRect(origin: .zero, size: document.imageSize))
        case .text, .step, .cursor:
            break
        default:
            document.draft = document.makeAnnotation(tool: document.tool, from: start, to: current, points: dragPoints)
        }
    }

    private func ended(from start: CGPoint, to end: CGPoint) {
        switch document.tool {
        case .select:
            if let movingID, hypot(moveOffset.dx, moveOffset.dy) > 0.5 {
                document.move(movingID, by: moveOffset)
            }
            movingID = nil
            moveOffset = .zero
        case .crop:
            document.applyCrop(document.draftCrop)
            document.draftCrop = nil
        case .text:
            if let existing = document.annotation(at: end), case let .text(origin, text) = existing.shape {
                document.editingText = .init(origin: origin, text: text, replacing: existing.id)
            } else if let existing = document.annotation(at: end), case let .callout(_, rect, text) = existing.shape {
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
            if let draft = document.makeAnnotation(tool: document.tool, from: start, to: end, points: dragPoints), document.isSubstantial(draft) {
                document.add(draft)
            }
            document.draft = nil
        }
    }
}
