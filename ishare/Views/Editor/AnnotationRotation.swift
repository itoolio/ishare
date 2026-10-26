import CoreGraphics
import Foundation
import ishareCore

extension Annotation {
    var supportsRotation: Bool {
        switch shape {
        case .rectangle, .ellipse, .highlight, .spotlight, .blur, .pixelate, .eraser, .text, .callout, .stamp: true
        default: false
        }
    }

    var rotationFrame: CGRect? {
        switch shape {
        case let .rectangle(rect), let .ellipse(rect), let .highlight(rect), let .spotlight(rect), let .blur(rect), let .pixelate(rect), let .eraser(rect),
            let .stamp(rect, _), let .callout(_, rect, _):
            rect.standardized
        case .text:
            unrotatedBounds
        default:
            nil
        }
    }

    var isRotated: Bool {
        supportsRotation && RotatedRect.normalized(rotation) != 0
    }

    var rotatedFrame: RotatedRect? {
        guard isRotated, let frame = rotationFrame else { return nil }
        return RotatedRect(rect: frame, angle: rotation)
    }

    var outline: RotatedRect {
        rotatedFrame ?? RotatedRect(rect: bounds, angle: 0)
    }

    func localPoint(_ point: CGPoint) -> CGPoint {
        rotatedFrame?.toLocal(point) ?? point
    }

    func rotatedHitTest(_ point: CGPoint, in frame: RotatedRect, tolerance: CGFloat) -> Bool {
        if frame.contains(point, tolerance: tolerance) {
            return true
        }
        guard case let .callout(tail, _, _) = shape else { return false }
        return Annotation.distance(from: point, toSegment: frame.center, tail) <= tolerance
    }

    func rotated(by angle: CGFloat) -> Annotation {
        guard supportsRotation else { return self }
        var copy = self
        copy.rotation = RotatedRect.normalized(rotation + angle)
        return copy
    }
}
