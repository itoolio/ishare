import CoreGraphics
import Foundation

extension Annotation {
    var isInteractive: Bool {
        !locked && !hidden
    }

    var tool: EditorTool {
        switch shape {
        case .arrow, .curvedArrow: .arrow
        case .line, .curvedLine: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .highlight: .highlight
        case .pen: .pen
        case .marker: .marker
        case .text: .text
        case .callout: .callout
        case .step: .step
        case .stamp: .stamp
        case .magnify: .magnify
        case .spotlight: .spotlight
        case .blur: .blur
        case .pixelate: .pixelate
        case .eraser: .eraser
        case .cursor: .cursor
        }
    }

    var layerSymbol: String {
        if case .curvedArrow = shape { return ArrowPath.curved.symbol }
        return tool.symbol
    }
}

enum LayerLabel {
    static let maximumLength = 40

    static func label(for annotation: Annotation, in annotations: [Annotation]) -> String {
        switch annotation.shape {
        case let .text(_, string):
            return excerpt(string) ?? numbered(annotation, in: annotations)
        case let .callout(_, _, string):
            return excerpt(string) ?? numbered(annotation, in: annotations)
        case let .stamp(_, .emoji(emoji)):
            return emoji
        case let .step(_, number):
            return "\(annotation.tool.title.localized()) \(number)"
        default:
            return numbered(annotation, in: annotations)
        }
    }

    static func excerpt(_ string: String) -> String? {
        let firstLine = string.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maximumLength else { return trimmed }
        return String(trimmed.prefix(maximumLength - 1)) + "…"
    }

    static func numbered(_ annotation: Annotation, in annotations: [Annotation]) -> String {
        let sameTool = annotations.filter { $0.tool == annotation.tool }
        let ordinal = (sameTool.firstIndex { $0.id == annotation.id } ?? sameTool.count) + 1
        return "\(annotation.tool.title.localized()) \(ordinal)"
    }
}

extension EditorDocument {
    var layers: [Annotation] {
        annotations.reversed()
    }

    func label(for annotation: Annotation) -> String {
        LayerLabel.label(for: annotation, in: annotations)
    }

    func moveLayers(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = layers
        reordered.move(fromOffsets: source, toOffset: destination)
        replaceAnnotations(with: Array(reordered.reversed()))
    }

    func setLocked(_ locked: Bool, for ids: Set<UUID>) {
        updateAnnotations(where: { ids.contains($0.id) }) { $0.locked = locked }
    }

    func setHidden(_ hidden: Bool, for ids: Set<UUID>) {
        updateAnnotations(where: { ids.contains($0.id) }) { $0.hidden = hidden }
        if hidden {
            selectedIDs.subtract(ids)
        }
    }

    var templateSource: [Annotation] {
        let selected = selectedAnnotations.filter { !$0.hidden }
        return selected.isEmpty ? annotations.filter { !$0.hidden } : selected
    }

    var templateFrame: CGRect {
        crop ?? imageBounds
    }

    func insert(_ template: AnnotationTemplate) {
        commitPendingEdits()
        let inserted = renumberedSteps(template.annotations(fittedTo: templateFrame))
        guard !inserted.isEmpty else { return }
        replaceAnnotations(with: annotations + inserted)
        select(tool: .select)
        selectedIDs = Set(inserted.map(\.id))
    }

    private func renumberedSteps(_ inserted: [Annotation]) -> [Annotation] {
        let numbers = inserted.compactMap { annotation -> Int? in
            if case let .step(_, number) = annotation.shape { return number }
            return nil
        }
        guard let lowest = numbers.min() else { return inserted }
        let shift = nextStepNumber - lowest
        return inserted.map { annotation in
            guard case let .step(center, number) = annotation.shape else { return annotation }
            var copy = annotation
            copy.shape = .step(center, number + shift)
            return copy
        }
    }
}
