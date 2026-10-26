import CoreGraphics
import Foundation

public struct RotatedRect: Hashable, Sendable {
    public var rect: CGRect
    public var angle: CGFloat

    public init(rect: CGRect, angle: CGFloat) {
        self.rect = rect.standardized
        self.angle = angle
    }

    public static func normalized(_ angle: CGFloat) -> CGFloat {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi {
            value -= 2 * .pi
        } else if value <= -.pi {
            value += 2 * .pi
        }
        return abs(value) < 1e-9 ? 0 : value
    }

    public var center: CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    public var isRotated: Bool {
        Self.normalized(angle) != 0
    }

    public var transform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle).translatedBy(x: -center.x, y: -center.y)
    }

    public func toWorld(_ point: CGPoint) -> CGPoint {
        Self.rotate(point, around: center, by: angle)
    }

    public func toLocal(_ point: CGPoint) -> CGPoint {
        Self.rotate(point, around: center, by: -angle)
    }

    public var corners: [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ].map(toWorld)
    }

    public var boundingBox: CGRect {
        guard isRotated else { return rect }
        let points = corners
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? rect.minX
        let minY = ys.min() ?? rect.minY
        return CGRect(x: minX, y: minY, width: (xs.max() ?? rect.maxX) - minX, height: (ys.max() ?? rect.maxY) - minY)
    }

    public func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(toLocal(point))
    }

    public func ellipseContains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let local = toLocal(point)
        let radiusX = rect.width / 2 + tolerance
        let radiusY = rect.height / 2 + tolerance
        guard radiusX > 0, radiusY > 0 else { return false }
        let dx = (local.x - rect.midX) / radiusX
        let dy = (local.y - rect.midY) / radiusY
        return dx * dx + dy * dy <= 1
    }

    public func replacingLocalRect(_ local: CGRect) -> RotatedRect {
        let standardized = local.standardized
        let localCenter = CGPoint(x: standardized.midX, y: standardized.midY)
        let worldCenter = toWorld(localCenter)
        return RotatedRect(
            rect: CGRect(
                x: worldCenter.x - standardized.width / 2, y: worldCenter.y - standardized.height / 2, width: standardized.width, height: standardized.height),
            angle: angle)
    }

    public func movingCenter(to point: CGPoint) -> RotatedRect {
        RotatedRect(rect: rect.offsetBy(dx: point.x - center.x, dy: point.y - center.y), angle: angle)
    }

    public static func rotate(_ point: CGPoint, around pivot: CGPoint, by angle: CGFloat) -> CGPoint {
        guard angle != 0 else { return point }
        let cosine = cos(angle)
        let sine = sin(angle)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return CGPoint(x: pivot.x + dx * cosine - dy * sine, y: pivot.y + dx * sine + dy * cosine)
    }
}
