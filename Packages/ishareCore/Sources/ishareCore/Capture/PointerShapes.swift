import CoreGraphics
import Foundation

public struct PointerShape: Hashable, Sendable {
    public var fingerprint: Int
    public var hotSpot: CGPoint
    public var size: CGSize

    public init(fingerprint: Int, hotSpot: CGPoint, size: CGSize) {
        self.fingerprint = fingerprint
        self.hotSpot = hotSpot
        self.size = size
    }

    public func origin(forTip tip: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: tip.x - hotSpot.x * scale, y: tip.y - (size.height - hotSpot.y) * scale)
    }
}

public struct PointerShapeChange: Hashable, Sendable {
    public var time: Double
    public var shape: Int

    public init(time: Double, shape: Int) {
        self.time = time
        self.shape = shape
    }
}

public struct PointerShapeTrack: Hashable, Sendable {
    public private(set) var shapes: [PointerShape] = []
    public private(set) var changes: [PointerShapeChange] = []

    public init() {}

    public init(shapes: [PointerShape], changes: [PointerShapeChange]) {
        self.shapes = shapes
        self.changes = changes.filter { shapes.indices.contains($0.shape) }.sorted { $0.time < $1.time }
    }

    public var isEmpty: Bool { changes.isEmpty }

    public func index(of shape: PointerShape) -> Int? {
        shapes.firstIndex(of: shape)
    }

    @discardableResult
    public mutating func record(_ shape: PointerShape, at time: Double) -> (index: Int, isNew: Bool) {
        let existing = index(of: shape)
        let index = existing ?? shapes.count
        if existing == nil {
            shapes.append(shape)
        }
        if changes.last?.shape != index {
            changes.append(PointerShapeChange(time: time, shape: index))
        }
        return (index, existing == nil)
    }

    public func shapeIndex(at time: Double) -> Int? {
        guard let first = changes.first else { return nil }
        guard time >= first.time else { return first.shape }
        var low = 0
        var high = changes.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if changes[middle].time <= time { low = middle } else { high = middle - 1 }
        }
        return changes[low].shape
    }

    public func shape(at time: Double) -> PointerShape? {
        shapeIndex(at: time).map { shapes[$0] }
    }

    public func retimed(_ transform: (Double) -> Double) -> PointerShapeTrack {
        var mapped: [PointerShapeChange] = []
        for change in changes {
            let time = transform(change.time)
            if let last = mapped.last, last.time >= time {
                mapped[mapped.count - 1] = PointerShapeChange(time: last.time, shape: change.shape)
            } else {
                mapped.append(PointerShapeChange(time: time, shape: change.shape))
            }
        }
        var collapsed: [PointerShapeChange] = []
        for change in mapped where collapsed.last?.shape != change.shape {
            collapsed.append(change)
        }
        return PointerShapeTrack(shapes: shapes, changes: collapsed)
    }
}
