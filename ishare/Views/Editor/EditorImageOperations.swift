import CoreGraphics
import Foundation

struct ImageAdjustments: Hashable, Sendable {
    static let identity = ImageAdjustments()
    static let brightnessRange: ClosedRange<Double> = -0.5 ... 0.5
    static let contrastRange: ClosedRange<Double> = 0.5 ... 1.5
    static let saturationRange: ClosedRange<Double> = 0 ... 2
    static let exposureRange: ClosedRange<Double> = -2 ... 2

    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var exposure: Double = 0

    var isIdentity: Bool { self == .identity }

    var usesColorControls: Bool {
        brightness != 0 || contrast != 1 || saturation != 1
    }
}

enum OrientationChange: Hashable, Sendable {
    case rotateLeft
    case rotateRight
    case flipHorizontal
    case flipVertical
}

struct CanvasMapping {
    var transform: CGAffineTransform
    var outputSize: CGSize
    var preservesExtents: Bool

    static func orientation(_ change: OrientationChange, size: CGSize) -> CanvasMapping {
        switch change {
        case .rotateRight:
            CanvasMapping(
                transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0), outputSize: CGSize(width: size.height, height: size.width), preservesExtents: false)
        case .rotateLeft:
            CanvasMapping(
                transform: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width), outputSize: CGSize(width: size.height, height: size.width), preservesExtents: false)
        case .flipHorizontal:
            CanvasMapping(transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0), outputSize: size, preservesExtents: false)
        case .flipVertical:
            CanvasMapping(transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height), outputSize: size, preservesExtents: false)
        }
    }

    static func straighten(degrees: Double, size: CGSize) -> CanvasMapping {
        let output = StraightenGeometry.outputSize(for: size, degrees: degrees)
        let radians = degrees * .pi / 180
        let transform = CGAffineTransform(translationX: output.width / 2, y: output.height / 2)
            .rotated(by: radians)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return CanvasMapping(transform: transform, outputSize: output, preservesExtents: true)
    }

    func map(_ point: CGPoint) -> CGPoint {
        point.applying(transform)
    }

    func map(_ rect: CGRect) -> CGRect {
        if preservesExtents {
            let center = map(CGPoint(x: rect.midX, y: rect.midY))
            return CGRect(x: center.x - rect.width / 2, y: center.y - rect.height / 2, width: rect.width, height: rect.height)
        }
        return rect.standardized.applying(transform).standardized
    }

    func mapKeepingSize(_ rect: CGRect) -> CGRect {
        let center = map(CGPoint(x: rect.midX, y: rect.midY))
        return CGRect(x: center.x - rect.width / 2, y: center.y - rect.height / 2, width: rect.width, height: rect.height)
    }
}

enum StraightenGeometry {
    static let maximumAngle: Double = 45

    static func inscribedScale(for size: CGSize, degrees: Double) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let radians = abs(degrees) * .pi / 180
        let cosine = CGFloat(cos(radians))
        let sine = CGFloat(sin(radians))
        let widthScale = size.width / (size.width * cosine + size.height * sine)
        let heightScale = size.height / (size.width * sine + size.height * cosine)
        return min(1, widthScale, heightScale)
    }

    static func outputSize(for size: CGSize, degrees: Double) -> CGSize {
        let scale = inscribedScale(for: size, degrees: degrees)
        return CGSize(width: max(1, (size.width * scale).rounded(.down)), height: max(1, (size.height * scale).rounded(.down)))
    }
}

extension Annotation {
    func mapped(by mapping: CanvasMapping) -> Annotation {
        var copy = self
        let point: (CGPoint) -> CGPoint = mapping.map
        copy.shape =
            switch shape {
            case let .arrow(start, end): .arrow(point(start), point(end))
            case let .line(start, end): .line(point(start), point(end))
            case let .curvedArrow(start, control, end): .curvedArrow(point(start), point(control), point(end))
            case let .stamp(rect, stamp): .stamp(mapping.mapKeepingSize(rect), stamp)
            case let .rectangle(rect): .rectangle(mapping.map(rect))
            case let .ellipse(rect): .ellipse(mapping.map(rect))
            case let .highlight(rect): .highlight(mapping.map(rect))
            case let .pen(points): .pen(points.map(point))
            case let .marker(points): .marker(points.map(point))
            case let .text(_, string): .text(mapping.mapKeepingSize(bounds).origin, string)
            case let .callout(tail, rect, string): .callout(point(tail), mapping.mapKeepingSize(rect), string)
            case let .step(center, number): .step(point(center), number)
            case let .magnify(rect): .magnify(mapping.map(rect))
            case let .spotlight(rect): .spotlight(mapping.map(rect))
            case let .blur(rect): .blur(mapping.map(rect))
            case let .pixelate(rect): .pixelate(mapping.map(rect))
            case let .eraser(rect): .eraser(mapping.map(rect))
            case .cursor: .cursor(mapping.mapKeepingSize(bounds).origin)
            }
        return copy
    }
}
