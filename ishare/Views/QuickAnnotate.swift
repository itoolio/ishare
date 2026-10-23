import AppKit
import Combine
import Defaults
import SwiftUI

struct QuickAnnotateGeometry: Equatable, Sendable {
    let imageSize: CGSize
    let canvasSize: CGSize

    static func canvasSize(for imageSize: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height)
        return CGSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
    }

    var fittedRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (canvasSize.width - size.width) / 2, y: (canvasSize.height - size.height) / 2, width: size.width, height: size.height)
    }

    var imagePixelsPerPoint: CGFloat {
        let fitted = fittedRect
        return fitted.width > 0 ? imageSize.width / fitted.width : 1
    }

    func toImage(_ point: CGPoint) -> CGPoint {
        let fitted = fittedRect
        let scale = imagePixelsPerPoint
        let x = (point.x - fitted.minX) * scale
        let y = (point.y - fitted.minY) * scale
        return CGPoint(x: min(max(x, 0), imageSize.width), y: min(max(y, 0), imageSize.height))
    }

    func toView(_ point: CGPoint) -> CGPoint {
        let fitted = fittedRect
        let scale = imagePixelsPerPoint
        return CGPoint(x: fitted.minX + point.x / scale, y: fitted.minY + point.y / scale)
    }

    func toView(_ length: CGFloat) -> CGFloat {
        length / imagePixelsPerPoint
    }

    var imageToView: CGAffineTransform {
        let fitted = fittedRect
        let scale = 1 / imagePixelsPerPoint
        return CGAffineTransform(translationX: fitted.minX, y: fitted.minY).scaledBy(x: scale, y: scale)
    }
}

enum QuickAnnotateTool: String, CaseIterable, Identifiable, Sendable {
    case arrow
    case rectangle
    case blur
    case text

    var id: Self { self }

    var editorTool: EditorTool {
        switch self {
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .blur: .blur
        case .text: .text
        }
    }

    var title: String { editorTool.title }
    var symbol: String { editorTool.symbol }
}

@MainActor
final class QuickAnnotateSession: ObservableObject {
    static let maxCanvasSize = CGSize(width: ToastCardView.width - 24, height: 240)

    let document: EditorDocument
    let fileURL: URL
    let geometry: QuickAnnotateGeometry
    @Published var tool: QuickAnnotateTool = .arrow
    @Published private(set) var preview: CGImage
    @Published private(set) var draft: Annotation?
    private var dragStart: CGPoint?
    private var cancellables: Set<AnyCancellable> = []

    init(image: CGImage, fileURL: URL) {
        document = EditorDocument(image: image, fileURL: fileURL)
        self.fileURL = fileURL
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvas = QuickAnnotateGeometry.canvasSize(for: imageSize, maxWidth: Self.maxCanvasSize.width, maxHeight: Self.maxCanvasSize.height)
        geometry = QuickAnnotateGeometry(imageSize: imageSize, canvasSize: canvas)
        preview = Self.previewImage(image, canvas: canvas)
        document.$effectedBase
            .dropFirst()
            .sink { [weak self] base in
                guard let self else { return }
                preview = Self.previewImage(base, canvas: geometry.canvasSize)
            }
            .store(in: &cancellables)
        document.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    convenience init?(fileURL: URL) {
        guard let image = ImageEncoder.loadImage(at: fileURL) else { return nil }
        self.init(image: image, fileURL: fileURL)
    }

    private static func previewImage(_ image: CGImage, canvas: CGSize) -> CGImage {
        ImageProcessing.resized(image, maxPixelSize: max(canvas.width, canvas.height) * 2)
    }

    var visibleAnnotations: [Annotation] {
        document.annotations.filter { !$0.isEffect && !$0.hidden } + (draft.map { [$0] } ?? [])
    }

    var hasChanges: Bool { document.hasChanges }
    var canUndo: Bool { document.canUndo }

    func select(_ tool: QuickAnnotateTool) {
        document.commitText()
        self.tool = tool
    }

    func dragChanged(from start: CGPoint, to location: CGPoint) {
        guard tool != .text else { return }
        let imageStart = geometry.toImage(start)
        dragStart = imageStart
        draft = document.makeAnnotation(tool: tool.editorTool, from: imageStart, to: geometry.toImage(location), points: [])
    }

    func dragEnded(from start: CGPoint, to location: CGPoint) {
        defer {
            draft = nil
            dragStart = nil
        }
        let imageStart = geometry.toImage(start)
        let imageEnd = geometry.toImage(location)
        if tool == .text {
            document.commitText()
            document.beginText(at: imageEnd)
            return
        }
        guard let annotation = document.makeAnnotation(tool: tool.editorTool, from: imageStart, to: imageEnd, points: []),
              document.isSubstantial(annotation)
        else { return }
        document.add(annotation)
    }

    func undo() {
        document.commitText()
        document.undo()
    }

    func render() -> CGImage? {
        document.commitPendingEdits()
        guard document.hasChanges else { return nil }
        return document.render()
    }

    func save() throws -> Bool {
        guard let rendered = render() else { return false }
        let fileType = FileType(rawValue: fileURL.pathExtension.lowercased()) ?? (fileURL.pathExtension.lowercased() == "jpeg" ? .JPG : .PNG)
        try ImageEncoder.write(rendered, as: fileType, to: fileURL)
        return true
    }
}

enum UploadReplacement {
    static func history(_ history: [HistoryItem], replacing old: HistoryItem, with new: HistoryItem) -> [HistoryItem] {
        guard old != new else { return history }
        var updated = history.filter { $0 != new }
        if let index = updated.firstIndex(of: old) {
            updated[index] = new
            return updated.enumerated().filter { $0.offset == index || $0.element != old }.map(\.element)
        }
        return [new] + updated

    }

    static func offersServerDeletion(of old: HistoryItem, replacedBy new: HistoryItem?) -> Bool {
        guard let new, new != old else { return false }
        return old.canDeleteFromServer && old.fileUrl != new.fileUrl
    }
}

struct QuickAnnotateCanvas: View {
    @ObservedObject var session: QuickAnnotateSession

    var body: some View {
        let geometry = session.geometry
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.draw(Image(decorative: session.preview, scale: 1), in: geometry.fittedRect)
                let annotations = session.visibleAnnotations
                context.withCGContext { cg in
                    cg.concatenate(geometry.imageToView)
                    AnnotationRenderer.draw(annotations, in: cg, source: nil, canvasSize: geometry.imageSize)
                }
            }
            .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
            .contentShape(Rectangle())
            .gesture(drawingGesture)
            if let edit = session.document.editingText {
                textField(for: edit)
            }
        }
        .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.crosshair.set()
            case .ended: NSCursor.arrow.set()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Annotation canvas".localized())
        .accessibilityIdentifier("toast.annotate.canvas")
    }

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                session.dragChanged(from: value.startLocation, to: value.location)
            }
            .onEnded { value in
                session.dragEnded(from: value.startLocation, to: value.location)
            }
    }

    private func textField(for edit: EditorDocument.TextEdit) -> some View {
        let origin = session.geometry.toView(edit.origin)
        let fontSize = max(10, session.geometry.toView(session.document.fontSize))
        return TextField("Text".localized(), text: Binding(
            get: { session.document.editingText?.text ?? "" },
            set: { session.document.editingText?.text = $0 }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(Color(nsColor: session.document.color.nsColor))
        .frame(minWidth: 80, maxWidth: max(80, session.geometry.canvasSize.width - origin.x - 4), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .offset(x: origin.x, y: origin.y)
        .onSubmit { session.document.commitText() }
        .accessibilityIdentifier("toast.annotate.text")
    }
}

struct QuickAnnotateToolbar: View {
    @ObservedObject var session: QuickAnnotateSession
    let onCancel: () -> Void
    let onDone: () -> Void
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(QuickAnnotateTool.allCases) { tool in
                    toolButton(tool)
                }
            }
            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(Color.primary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(contrast.fillOpacity)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canUndo)
            .opacity(session.canUndo ? 1 : 0.4)
            .helpAndAccessibilityLabel("Undo".localized())
            .accessibilityIdentifier("toast.annotate.undo")
            Spacer(minLength: 4)
            ToastActionButton(symbol: "xmark", title: "Cancel", identifier: "toast.annotate.cancel", action: onCancel)
            Button(action: onDone) {
                Label("Done".localized(), systemImage: "checkmark")
                    .font(.system(size: 11, weight: Font.Weight.semibold.emphasized(contrast)))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.menuAccent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .help("Save the annotations".localized())
            .accessibilityIdentifier("toast.annotate.done")
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func toolButton(_ tool: QuickAnnotateTool) -> some View {
        let isSelected = session.tool == tool
        return Button {
            session.select(tool)
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 26, height: 24)
                .background(Capsule().fill(isSelected ? Color.menuAccent : Color.primary.opacity(contrast.fillOpacity)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tool.title.localized())
        .accessibilityLabel(tool.title.localized())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("toast.annotate.\(tool.rawValue)")
    }
}
