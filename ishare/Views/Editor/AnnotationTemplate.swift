import CoreGraphics
import Foundation

struct TemplateMapping: Equatable {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    var source: CGRect
    var target: CGRect

    var scaleX: CGFloat { target.width / max(.leastNonzeroMagnitude, source.width) }
    var scaleY: CGFloat { target.height / max(.leastNonzeroMagnitude, source.height) }
    var lengthScale: CGFloat { (scaleX * scaleY).squareRoot() }

    func point(_ point: CGPoint) -> CGPoint {
        CGPoint(x: target.minX + (point.x - source.minX) * scaleX, y: target.minY + (point.y - source.minY) * scaleY)
    }

    func rect(_ rect: CGRect) -> CGRect {
        CGRect(origin: point(rect.origin), size: CGSize(width: rect.width * scaleX, height: rect.height * scaleY))
    }

    func square(_ rect: CGRect) -> CGRect {
        let center = point(CGPoint(x: rect.midX, y: rect.midY))
        let size = CGSize(width: rect.width * lengthScale, height: rect.height * lengthScale)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    func anchored(_ rect: CGRect) -> CGRect {
        CGRect(origin: point(rect.origin), size: CGSize(width: rect.width * lengthScale, height: rect.height * lengthScale))
    }

    func length(_ length: CGFloat) -> CGFloat {
        length * lengthScale
    }
}

extension Annotation {
    func mapped(with mapping: TemplateMapping) -> Annotation {
        var copy = self
        let point = mapping.point
        let rect = mapping.rect
        copy.shape = switch shape {
        case let .arrow(start, end): .arrow(point(start), point(end))
        case let .line(start, end): .line(point(start), point(end))
        case let .curvedArrow(start, control, end): .curvedArrow(point(start), point(control), point(end))
        case let .rectangle(bounds): .rectangle(rect(bounds))
        case let .ellipse(bounds): .ellipse(rect(bounds))
        case let .highlight(bounds): .highlight(rect(bounds))
        case let .spotlight(bounds): .spotlight(rect(bounds))
        case let .blur(bounds): .blur(rect(bounds))
        case let .pixelate(bounds): .pixelate(rect(bounds))
        case let .eraser(bounds): .eraser(rect(bounds))
        case let .magnify(bounds): .magnify(mapping.square(bounds))
        case let .stamp(bounds, stamp): .stamp(mapping.square(bounds), stamp)
        case let .pen(points): .pen(points.map(point))
        case let .marker(points): .marker(points.map(point))
        case let .text(origin, string): .text(point(origin), string)
        case let .callout(tail, bounds, string): .callout(point(tail), mapping.anchored(bounds), string)
        case let .step(center, number): .step(point(center), number)
        case let .cursor(location): .cursor(point(location))
        }
        copy.lineWidth = mapping.length(lineWidth)
        copy.fontSize = mapping.length(fontSize)
        return copy
    }
}

extension Annotation: Codable {
    private enum CodingKeys: String, CodingKey {
        case shape, color, lineWidth, fontSize, filled, textBackground, arrowHead, doubleHeaded, dashed, spotlightShape, dimAmount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shape: try container.decode(Shape.self, forKey: .shape),
            color: try container.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .red,
            lineWidth: try container.decodeIfPresent(CGFloat.self, forKey: .lineWidth) ?? 6
        )
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? fontSize
        filled = try container.decodeIfPresent(Bool.self, forKey: .filled) ?? filled
        textBackground = try container.decodeIfPresent(Bool.self, forKey: .textBackground) ?? textBackground
        arrowHead = try container.decodeIfPresent(ArrowHead.self, forKey: .arrowHead) ?? arrowHead
        doubleHeaded = try container.decodeIfPresent(Bool.self, forKey: .doubleHeaded) ?? doubleHeaded
        dashed = try container.decodeIfPresent(Bool.self, forKey: .dashed) ?? dashed
        spotlightShape = try container.decodeIfPresent(SpotlightShape.self, forKey: .spotlightShape) ?? spotlightShape
        dimAmount = try container.decodeIfPresent(Double.self, forKey: .dimAmount) ?? dimAmount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shape, forKey: .shape)
        try container.encode(color, forKey: .color)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(filled, forKey: .filled)
        try container.encode(textBackground, forKey: .textBackground)
        try container.encode(arrowHead, forKey: .arrowHead)
        try container.encode(doubleHeaded, forKey: .doubleHeaded)
        try container.encode(dashed, forKey: .dashed)
        try container.encode(spotlightShape, forKey: .spotlightShape)
        try container.encode(dimAmount, forKey: .dimAmount)
    }
}

struct AnnotationTemplate: Codable, Identifiable, Hashable, Sendable {
    static let currentVersion = 1

    var version = AnnotationTemplate.currentVersion
    var id = UUID()
    var name: String
    var createdAt = Date()
    var referenceSize: CGSize
    var annotations: [Annotation]

    init(name: String, annotations source: [Annotation], frame: CGRect, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        referenceSize = frame.size
        let mapping = TemplateMapping(source: frame, target: TemplateMapping.unit)
        annotations = source.map { annotation in
            var normalized = annotation.mapped(with: mapping)
            normalized.locked = false
            normalized.hidden = false
            return normalized
        }
    }

    var aspectRatio: CGFloat {
        referenceSize.width / max(1, referenceSize.height)
    }

    func annotations(fittedTo frame: CGRect) -> [Annotation] {
        let mapping = TemplateMapping(source: TemplateMapping.unit, target: frame)
        return annotations.map { annotation in
            var placed = annotation.mapped(with: mapping)
            placed.id = UUID()
            return placed
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    static func decode(_ data: Data) throws -> AnnotationTemplate {
        try decoder().decode(AnnotationTemplate.self, from: data)
    }
}
