import CoreGraphics
import Foundation

public struct SnapEdge: Hashable, Sendable {
    public var position: CGFloat
    public var span: ClosedRange<CGFloat>

    public init(position: CGFloat, span: ClosedRange<CGFloat>) {
        self.position = position
        self.span = span
    }
}

public struct SnappedPoint: Equatable, Sendable {
    public var point: CGPoint
    public var verticalEdge: SnapEdge?
    public var horizontalEdge: SnapEdge?

    public var isSnapped: Bool {
        verticalEdge != nil || horizontalEdge != nil
    }
}

public struct SnapEdges: Equatable, Sendable {
    public static let defaultThreshold: CGFloat = 8
    public static let minimumRectSide: CGFloat = 12

    public private(set) var vertical: [SnapEdge]
    public private(set) var horizontal: [SnapEdge]

    public init(vertical: [SnapEdge] = [], horizontal: [SnapEdge] = []) {
        self.vertical = vertical
        self.horizontal = horizontal
    }

    public init(rects: [CGRect], within bounds: CGRect) {
        self.init()
        add(rects: rects, within: bounds)
    }

    public var isEmpty: Bool {
        vertical.isEmpty && horizontal.isEmpty
    }

    public mutating func add(rects: [CGRect], within bounds: CGRect) {
        for rect in rects {
            let clipped = rect.intersection(bounds)
            guard !clipped.isNull, clipped.width >= Self.minimumRectSide, clipped.height >= Self.minimumRectSide else { continue }
            let rows = clipped.minY...clipped.maxY
            let columns = clipped.minX...clipped.maxX
            for x in [rect.minX, rect.maxX] where x > bounds.minX && x < bounds.maxX {
                vertical.append(SnapEdge(position: x, span: rows))
            }
            for y in [rect.minY, rect.maxY] where y > bounds.minY && y < bounds.maxY {
                horizontal.append(SnapEdge(position: y, span: columns))
            }
        }
    }

    public func snapping(_ point: CGPoint, threshold: CGFloat = defaultThreshold) -> SnappedPoint {
        let verticalEdge = Self.nearest(in: vertical, to: point.x, along: point.y, threshold: threshold)
        let horizontalEdge = Self.nearest(in: horizontal, to: point.y, along: point.x, threshold: threshold)
        let snapped = CGPoint(x: verticalEdge?.position ?? point.x, y: horizontalEdge?.position ?? point.y)
        return SnappedPoint(point: snapped, verticalEdge: verticalEdge, horizontalEdge: horizontalEdge)
    }

    static func nearest(in edges: [SnapEdge], to value: CGFloat, along cross: CGFloat, threshold: CGFloat) -> SnapEdge? {
        edges
            .filter { abs($0.position - value) <= threshold && cross >= $0.span.lowerBound - threshold && cross <= $0.span.upperBound + threshold }
            .min { abs($0.position - value) < abs($1.position - value) }
    }

    public static func flippedImageRects(_ pixelRects: [CGRect], scale: CGFloat, viewHeight: CGFloat) -> [CGRect] {
        let factor = max(scale, 0.01)
        return pixelRects.map { rect in
            CGRect(x: rect.minX / factor, y: viewHeight - rect.maxY / factor, width: rect.width / factor, height: rect.height / factor)
        }
    }

    public static func viewRects(fromQuartz frames: [CGRect], screenFrame: CGRect, primaryScreenHeight: CGFloat) -> [CGRect] {
        frames.map { frame in
            let cocoaY = primaryScreenHeight - frame.maxY
            return CGRect(x: frame.minX - screenFrame.minX, y: cocoaY - screenFrame.minY, width: frame.width, height: frame.height)
        }
    }
}
