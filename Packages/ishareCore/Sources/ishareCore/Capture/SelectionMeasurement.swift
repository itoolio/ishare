import CoreGraphics
import Foundation

public struct SelectionMeasurement: Hashable {
    public var start: CGPoint
    public var end: CGPoint

    public func lockedToAxis() -> SelectionMeasurement {
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let lockedEnd = dx >= dy ? CGPoint(x: end.x, y: start.y) : CGPoint(x: start.x, y: end.y)
        return SelectionMeasurement(start: start, end: lockedEnd)
    }

    public var delta: CGVector {
        CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    public var length: CGFloat {
        hypot(delta.dx, delta.dy)
    }

    func pixelLength(scale: CGFloat) -> CGFloat {
        length * scale
    }

    public func label(scale: CGFloat) -> String {
        let points = Self.format(length)
        let pixels = Self.format(pixelLength(scale: scale))
        let dx = Self.format(abs(delta.dx))
        let dy = Self.format(abs(delta.dy))
        return "\(points) pt · \(pixels) px   Δx \(dx)  Δy \(dy)"
    }

    public static func format(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

public enum DisplayCoordinates {
    static func topLeftPoint(for location: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: location.x.rounded(.down), y: (bounds.height - location.y).rounded(.down))
    }

    public static func pixel(for location: CGPoint, in bounds: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: (location.x * scale).rounded(.down), y: ((bounds.height - location.y) * scale).rounded(.down))
    }

    public static func label(for location: CGPoint, in bounds: CGRect) -> String {
        let point = topLeftPoint(for: location, in: bounds)
        return "\(Int(point.x)), \(Int(point.y))"
    }
}

public enum MagnifierLayout {
    public static let sampleCount = 15
    public static let loupeSide: CGFloat = 180
    public static let infoHeight: CGFloat = 44
    static let cursorOffset: CGFloat = 24
    public static let margin: CGFloat = 6

    public static var cardSize: CGSize {
        CGSize(width: loupeSide, height: loupeSide + infoHeight)
    }

    public static func cardFrame(for location: CGPoint, in bounds: CGRect, size: CGSize = cardSize) -> CGRect {
        var origin = CGPoint(x: location.x + cursorOffset, y: location.y - cursorOffset - size.height)
        if origin.x + size.width > bounds.maxX - margin {
            origin.x = location.x - cursorOffset - size.width
        }
        if origin.y < bounds.minY + margin {
            origin.y = location.y + cursorOffset
        }
        origin.x = min(max(origin.x, bounds.minX + margin), bounds.maxX - size.width - margin)
        origin.y = min(max(origin.y, bounds.minY + margin), bounds.maxY - size.height - margin)
        return CGRect(origin: origin, size: size)
    }
}
