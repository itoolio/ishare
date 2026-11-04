import AppKit
import BezelNotification
import ishareCore

@MainActor
enum AnnotationFromText {
    static let instructions = """
        You place one annotation on a screenshot. You get the request and a numbered list of text found in the image.
        Answer with exactly one line in the form kind|number, where kind is one of arrow, rectangle, ellipse, highlight, step, blur or pixelate,
        and number is the item the request is about. Answer none if nothing fits.
        """

    static func prompt(for document: EditorDocument) {
        let alert = NSAlert()
        alert.messageText = "Describe an Annotation".localized()
        alert.informativeText = "For example “arrow to the Save button”, “box around Export” or “blur the email address”.".localized()
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "arrow to the Save button".localized()
        alert.accessoryView = field
        alert.addButton(withTitle: "Add".localized())
        alert.addButton(withTitle: "Cancel".localized())
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let request = field.stringValue
        Task { await add(request, to: document) }
    }

    static func add(_ request: String, to document: EditorDocument) async {
        let image = document.adjustedBase
        let size = CGSize(width: image.width, height: image.height)
        let lines = ((try? await TextRecognition.lines(in: image)) ?? []).map { line in
            (text: line.text, rect: UIElementDetector.pixelRect(fromNormalized: line.boundingBox, imageSize: size))
        }
        guard let (kind, index) = await resolve(request, labels: lines.map(\.text)) else {
            BezelNotification.show(messageText: "Couldn’t find that in the image".localized(), icon: ToastIcon)
            return
        }
        let annotation = makeAnnotation(kind, around: lines[index].rect, document: document)
        document.add(annotation)
        document.selectedID = annotation.id
    }

    static func resolve(_ request: String, labels: [String]) async -> (AnnotationCommandKind, Int)? {
        if let parsed = AnnotationCommand.parse(request), let index = AnnotationCommand.bestMatch(for: parsed.target, in: labels) {
            return (parsed.kind, index)
        }
        guard OnDeviceModel.isAvailable, !labels.isEmpty else { return nil }
        let list = labels.prefix(120).enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n")
        let reply = try? await OnDeviceModel.respond(to: "Request: \(request)\nItems:\n\(list)", instructions: instructions)
        return reply.flatMap { AnnotationCommand.parseModelReply($0.lowercased(), labelCount: min(labels.count, 120)) }
    }

    static func arrowShape(to rect: CGRect, in bounds: CGRect) -> Annotation.Shape {
        let arrow = AnnotationCommand.arrow(to: rect, in: bounds)
        return .arrow(arrow.start, arrow.end)
    }

    static func makeAnnotation(_ kind: AnnotationCommandKind, around rect: CGRect, document: EditorDocument) -> Annotation {
        let outline = AnnotationCommand.outline(around: rect, padding: max(4, document.lineWidth))
        let shape: Annotation.Shape =
            switch kind {
            case .arrow: arrowShape(to: rect, in: document.imageBounds)
            case .rectangle: .rectangle(outline)
            case .ellipse: .ellipse(outline.insetBy(dx: -outline.width * 0.1, dy: -outline.height * 0.25))
            case .highlight: .highlight(outline)
            case .step: .step(CGPoint(x: outline.minX, y: outline.minY), document.nextStepNumber)
            case .blur: .blur(outline)
            case .pixelate: .pixelate(outline)
            }
        return Annotation(shape: shape, color: document.color, lineWidth: document.lineWidth, fontSize: document.fontSize)
    }
}
