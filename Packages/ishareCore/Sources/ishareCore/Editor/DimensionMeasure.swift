import CoreGraphics
import Foundation

public enum DimensionMeasure {
    public static func length(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    public static func angleDegrees(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let degrees = atan2(start.y - end.y, end.x - start.x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    public static func isAxisAligned(_ degrees: CGFloat, tolerance: CGFloat = 1) -> Bool {
        let remainder = degrees.truncatingRemainder(dividingBy: 90)
        return remainder <= tolerance || 90 - remainder <= tolerance
    }

    public static func label(from start: CGPoint, to end: CGPoint, pointScale: CGFloat) -> String {
        let pixels = length(from: start, to: end)
        var parts = ["\(Int(pixels.rounded())) px"]
        if pointScale > 1 {
            parts.append("\(Int((pixels / pointScale).rounded())) pt")
        }
        let angle = angleDegrees(from: start, to: end)
        if !isAxisAligned(angle) {
            parts.append("\(Int(angle.rounded()))°")
        }
        return parts.joined(separator: " · ")
    }

    public static func ticks(from start: CGPoint, to end: CGPoint, length tickLength: CGFloat) -> [(CGPoint, CGPoint)] {
        let distance = length(from: start, to: end)
        guard distance > 0 else { return [] }
        let normal = CGVector(dx: -(end.y - start.y) / distance * tickLength / 2, dy: (end.x - start.x) / distance * tickLength / 2)
        return [start, end].map { point in
            (CGPoint(x: point.x - normal.dx, y: point.y - normal.dy), CGPoint(x: point.x + normal.dx, y: point.y + normal.dy))
        }
    }

    public static func selectionDimensions(of rect: CGRect, offset: CGFloat) -> [(CGPoint, CGPoint)] {
        [
            (CGPoint(x: rect.minX, y: rect.minY - offset), CGPoint(x: rect.maxX, y: rect.minY - offset)),
            (CGPoint(x: rect.minX - offset, y: rect.minY), CGPoint(x: rect.minX - offset, y: rect.maxY)),
        ]
    }
}
