import CoreGraphics
import Foundation
import ishareCore

enum HighlightStyle: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case marker
    case underline
    case strikethrough

    var id: Self { self }

    var title: String {
        switch self {
        case .marker: "Highlight".localized()
        case .underline: "Underline".localized()
        case .strikethrough: "Strikethrough".localized()
        }
    }

    var symbol: String {
        switch self {
        case .marker: "highlighter"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        }
    }

    static func lineThickness(for rect: CGRect) -> CGFloat {
        max(2, (rect.height * 0.12).rounded())
    }

    func lineRect(in rect: CGRect) -> CGRect? {
        let rect = rect.standardized
        let thickness = Self.lineThickness(for: rect)
        switch self {
        case .marker: return nil
        case .underline: return CGRect(x: rect.minX, y: rect.maxY - thickness, width: rect.width, height: thickness)
        case .strikethrough: return CGRect(x: rect.minX, y: rect.midY - thickness / 2, width: rect.width, height: thickness)
        }
    }
}

enum HighlightTarget: String, CaseIterable, Identifiable, Sendable {
    case area
    case text

    var id: Self { self }

    var title: String {
        switch self {
        case .area: "Highlight Area".localized()
        case .text: "Highlight Text".localized()
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .text: "text.viewfinder"
        }
    }
}

enum TextHighlighting {
    static let padding: CGFloat = 2

    static func lines(from recognized: [RecognizedLine], imageSize: CGSize) -> [TextHighlightLine] {
        recognized.map { line in
            TextHighlightLine(normalizedFrame: line.boundingBox, normalizedWords: line.words.map(\.boundingBox), imageSize: imageSize)
        }
    }

    static func recognizeLines(in image: CGImage) async -> [TextHighlightLine] {
        do {
            let recognized = try await TextRecognition.lines(in: image)
            return lines(from: recognized, imageSize: CGSize(width: image.width, height: image.height))
        } catch {
            Log.app.error("Recognizing text for the highlighter failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension EditorDocument {
    var textHighlightActive: Bool {
        tool == .highlight && highlightTarget == .text
    }

    func makeHighlight(_ rect: CGRect) -> Annotation {
        var annotation = Annotation(shape: .highlight(rect), color: color, lineWidth: lineWidth, fontSize: fontSize)
        annotation.highlightStyle = highlightStyle
        return annotation
    }

    func textHighlights(from start: CGPoint, to end: CGPoint, tolerance: CGFloat) -> [Annotation] {
        guard textHighlightActive, !textLines.isEmpty else { return [] }
        return TextHighlightSelection.rects(for: textLines, from: start, to: end, tolerance: tolerance, padding: TextHighlighting.padding)
            .map(makeHighlight)
    }

    func setHighlightTarget(_ target: HighlightTarget) {
        highlightTarget = target
        prepareTextLinesIfNeeded()
    }

    func setHighlightStyle(_ style: HighlightStyle) {
        highlightStyle = style
        updateSelection { annotation in
            if case .highlight = annotation.shape {
                annotation.highlightStyle = style
            }
        }
    }
}
