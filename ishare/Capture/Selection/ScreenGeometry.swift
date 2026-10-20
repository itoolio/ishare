import CoreGraphics
import Foundation

enum ScreenGeometry {
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
    }

    static func squareRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        let x = end.x >= start.x ? start.x : start.x - side
        let y = end.y >= start.y ? start.y : start.y - side
        return CGRect(x: x, y: y, width: side, height: side)
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let intersection = rect.intersection(bounds)
        return intersection.isNull ? .zero : intersection
    }

    static func moved(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var origin = CGPoint(x: rect.origin.x + delta.dx, y: rect.origin.y + delta.dy)
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - rect.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: origin, size: rect.size)
    }

    static func flippedVertically(_ rect: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: containerHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoaToQuartz(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        flippedVertically(rect, containerHeight: primaryScreenHeight)
    }

    static func quartzToCocoa(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        flippedVertically(rect, containerHeight: primaryScreenHeight)
    }

    static func cocoaPointToQuartz(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func pixelRect(for pointRect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (pointRect.origin.x * scale).rounded(.down),
            y: (pointRect.origin.y * scale).rounded(.down),
            width: (pointRect.width * scale).rounded(),
            height: (pointRect.height * scale).rounded()
        )
    }

    static func evenPixelSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width / 2).rounded() * 2), height: max(2, (size.height / 2).rounded() * 2))
    }

    static func topmostWindowIndex(at point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    static func isMeaningfulSelection(_ rect: CGRect, minimum: CGFloat = 4) -> Bool {
        rect.width >= minimum && rect.height >= minimum
    }
}
