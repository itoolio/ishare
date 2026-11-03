import CoreGraphics
import Foundation

public enum AlignmentEdge: String, CaseIterable, Sendable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom
}

public enum DistributionAxis: String, CaseIterable, Sendable {
    case horizontal
    case vertical
}

public enum Arrangement {
    public static func offsets(aligning rects: [CGRect], to edge: AlignmentEdge, within container: CGRect? = nil) -> [CGVector] {
        guard let first = rects.first else { return [] }
        let reference = container ?? (rects.count == 1 ? first : rects.dropFirst().reduce(first) { $0.union($1) })
        return rects.map { rect in
            switch edge {
            case .left: CGVector(dx: reference.minX - rect.minX, dy: 0)
            case .horizontalCenter: CGVector(dx: reference.midX - rect.midX, dy: 0)
            case .right: CGVector(dx: reference.maxX - rect.maxX, dy: 0)
            case .top: CGVector(dx: 0, dy: reference.minY - rect.minY)
            case .verticalCenter: CGVector(dx: 0, dy: reference.midY - rect.midY)
            case .bottom: CGVector(dx: 0, dy: reference.maxY - rect.maxY)
            }
        }
    }

    public static func offsets(distributing rects: [CGRect], along axis: DistributionAxis) -> [CGVector] {
        guard rects.count > 2 else { return rects.map { _ in .zero } }
        let order = rects.indices.sorted { start(of: rects[$0], axis) < start(of: rects[$1], axis) }
        let first = rects[order[0]]
        let last = rects[order[order.count - 1]]
        let span = end(of: last, axis) - start(of: first, axis)
        let occupied = rects.reduce(CGFloat(0)) { $0 + length(of: $1, axis) }
        let gap = (span - occupied) / CGFloat(rects.count - 1)
        var offsets = Array(repeating: CGVector.zero, count: rects.count)
        var cursor = start(of: first, axis)
        for index in order {
            let shift = cursor - start(of: rects[index], axis)
            offsets[index] = axis == .horizontal ? CGVector(dx: shift, dy: 0) : CGVector(dx: 0, dy: shift)
            cursor += length(of: rects[index], axis) + gap
        }
        return offsets
    }

    static func start(of rect: CGRect, _ axis: DistributionAxis) -> CGFloat {
        axis == .horizontal ? rect.minX : rect.minY
    }

    static func end(of rect: CGRect, _ axis: DistributionAxis) -> CGFloat {
        axis == .horizontal ? rect.maxX : rect.maxY
    }

    static func length(of rect: CGRect, _ axis: DistributionAxis) -> CGFloat {
        axis == .horizontal ? rect.width : rect.height
    }
}
