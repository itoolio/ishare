import CoreGraphics

struct CanvasTransform: Equatable {
    static let padding: CGFloat = 20
    static let minimumZoom: CGFloat = 0.1
    static let maximumZoom: CGFloat = 8
    static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    var visibleRect: CGRect
    var scale: CGFloat
    var origin: CGPoint

    var contentRect: CGRect {
        CGRect(origin: origin, size: CGSize(width: visibleRect.width * scale, height: visibleRect.height * scale))
    }

    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (point.x - visibleRect.minX) * scale, y: origin.y + (point.y - visibleRect.minY) * scale)
    }

    func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale + visibleRect.minX, y: (point.y - origin.y) / scale + visibleRect.minY)
    }

    func toView(_ rect: CGRect) -> CGRect {
        CGRect(origin: toView(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    func toImage(_ rect: CGRect) -> CGRect {
        CGRect(origin: toImage(rect.origin), size: CGSize(width: rect.width / scale, height: rect.height / scale))
    }

    func toImage(_ length: CGFloat) -> CGFloat {
        length / scale
    }

    var cgTransform: CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -visibleRect.minX, y: -visibleRect.minY)
    }

    static func fitScale(for size: CGSize, in container: CGSize, backingScale: CGFloat) -> CGFloat {
        let available = CGSize(width: max(1, container.width - padding * 2), height: max(1, container.height - padding * 2))
        let natural = 1 / max(1, backingScale)
        return min(natural, available.width / max(1, size.width), available.height / max(1, size.height))
    }

    static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, zoom))
    }

    static func zoomIn(from zoom: CGFloat) -> CGFloat {
        zoomSteps.first { $0 > zoom + 0.001 } ?? maximumZoom
    }

    static func zoomOut(from zoom: CGFloat) -> CGFloat {
        zoomSteps.last { $0 < zoom - 0.001 } ?? minimumZoom
    }

    static func make(visibleRect: CGRect, container: CGSize, scale: CGFloat, center: CGPoint?) -> CanvasTransform {
        let content = CGSize(width: visibleRect.width * scale, height: visibleRect.height * scale)
        let focus = center ?? CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        func axisOrigin(content: CGFloat, container: CGFloat, focus: CGFloat, minimum: CGFloat) -> CGFloat {
            guard content + padding * 2 > container else { return (container - content) / 2 }
            let centered = container / 2 - (focus - minimum) * scale
            return min(padding, max(container - content - padding, centered))
        }
        let origin = CGPoint(
            x: axisOrigin(content: content.width, container: container.width, focus: focus.x, minimum: visibleRect.minX),
            y: axisOrigin(content: content.height, container: container.height, focus: focus.y, minimum: visibleRect.minY)
        )
        return CanvasTransform(visibleRect: visibleRect, scale: scale, origin: origin)
    }

    func center(in container: CGSize) -> CGPoint {
        toImage(CGPoint(x: container.width / 2, y: container.height / 2))
    }

    func panned(by delta: CGVector, in container: CGSize) -> CanvasTransform {
        let current = center(in: container)
        let moved = CGPoint(x: current.x - delta.dx / scale, y: current.y - delta.dy / scale)
        return .make(visibleRect: visibleRect, container: container, scale: scale, center: moved)
    }

    func zoomAnchor(pointer: CGPoint?, selection: CGRect?, in container: CGSize) -> CGPoint {
        let bounds = CGRect(origin: .zero, size: container)
        if let pointer, bounds.contains(pointer) {
            return pointer
        }
        if let selection, !selection.isNull, !selection.isInfinite {
            let center = toView(CGPoint(x: selection.midX, y: selection.midY))
            return CGPoint(x: min(max(center.x, bounds.minX), bounds.maxX), y: min(max(center.y, bounds.minY), bounds.maxY))
        }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func zoomed(to newScale: CGFloat, anchor: CGPoint, in container: CGSize) -> CanvasTransform {
        let pinned = toImage(anchor)
        let newOrigin = CGPoint(x: anchor.x - (pinned.x - visibleRect.minX) * newScale, y: anchor.y - (pinned.y - visibleRect.minY) * newScale)
        let unclamped = CanvasTransform(visibleRect: visibleRect, scale: newScale, origin: newOrigin)
        return .make(visibleRect: visibleRect, container: container, scale: newScale, center: unclamped.center(in: container))
    }
}
