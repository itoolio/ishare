import CoreGraphics

enum SmartShapes {
    static let snapDistance: CGFloat = 8
    static let matchOverlap: CGFloat = 0.6

    static func supports(_ tool: EditorTool) -> Bool {
        switch tool {
        case .rectangle, .highlight, .spotlight: true
        default: false
        }
    }

    static func snap(_ rect: CGRect, to targets: [CGRect], threshold: CGFloat) -> CGRect {
        let rect = rect.standardized
        guard !targets.isEmpty, threshold > 0 else { return rect }
        let verticalNeighbours = targets.filter { overlaps($0.minY ... $0.maxY, rect.minY - threshold ... rect.maxY + threshold) }
        let horizontalNeighbours = targets.filter { overlaps($0.minX ... $0.maxX, rect.minX - threshold ... rect.maxX + threshold) }
        let xEdges = verticalNeighbours.flatMap { [$0.minX, $0.maxX] }
        let yEdges = horizontalNeighbours.flatMap { [$0.minY, $0.maxY] }
        var minX = nearest(to: rect.minX, in: xEdges, threshold: threshold) ?? rect.minX
        var maxX = nearest(to: rect.maxX, in: xEdges, threshold: threshold) ?? rect.maxX
        var minY = nearest(to: rect.minY, in: yEdges, threshold: threshold) ?? rect.minY
        var maxY = nearest(to: rect.maxY, in: yEdges, threshold: threshold) ?? rect.maxY
        if maxX - minX < 1 {
            minX = rect.minX
            maxX = rect.maxX
        }
        if maxY - minY < 1 {
            minY = rect.minY
            maxY = rect.maxY
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func snappedCorners(from start: CGPoint, to end: CGPoint, targets: [CGRect], threshold: CGFloat) -> (start: CGPoint, end: CGPoint) {
        let rect = snap(ScreenGeometry.rect(from: start, to: end), to: targets, threshold: threshold)
        let startX = start.x <= end.x ? rect.minX : rect.maxX
        let endX = start.x <= end.x ? rect.maxX : rect.minX
        let startY = start.y <= end.y ? rect.minY : rect.maxY
        let endY = start.y <= end.y ? rect.maxY : rect.minY
        return (CGPoint(x: startX, y: startY), CGPoint(x: endX, y: endY))
    }

    static func nearest(to value: CGFloat, in edges: [CGFloat], threshold: CGFloat) -> CGFloat? {
        edges
            .map { ($0, abs($0 - value)) }
            .filter { $0.1 <= threshold }
            .min { $0.1 < $1.1 }?.0
    }

    static func candidate(at point: CGPoint, in targets: [CGRect], tolerance: CGFloat) -> CGRect? {
        targets
            .filter { $0.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
            .min { $0.width * $0.height < $1.width * $1.height }
    }

    static func matchedTarget(for rect: CGRect, in targets: [CGRect]) -> CGRect? {
        targets
            .map { ($0, overlapRatio($0, rect)) }
            .filter { $0.1 >= matchOverlap }
            .max { $0.1 < $1.1 }?.0
    }

    static func overlapRatio(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height + second.width * second.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private static func overlaps(_ first: ClosedRange<CGFloat>, _ second: ClosedRange<CGFloat>) -> Bool {
        first.lowerBound <= second.upperBound && second.lowerBound <= first.upperBound
    }
}
