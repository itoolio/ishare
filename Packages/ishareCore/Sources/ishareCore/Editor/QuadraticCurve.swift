import CoreGraphics
import Foundation

public struct QuadraticCurve: Hashable, Sendable {
    public static let sampleCount = 32

    public var start: CGPoint
    public var control: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, control: CGPoint, end: CGPoint) {
        self.start = start
        self.control = control
        self.end = end
    }

    public init(start: CGPoint, through midpoint: CGPoint, end: CGPoint) {
        self.init(start: start, control: Self.control(passingThrough: midpoint, from: start, to: end), end: end)
    }

    public static func control(passingThrough midpoint: CGPoint, from start: CGPoint, to end: CGPoint) -> CGPoint {
        CGPoint(x: 2 * midpoint.x - (start.x + end.x) / 2, y: 2 * midpoint.y - (start.y + end.y) / 2)
    }

    public static func defaultControl(from start: CGPoint, to end: CGPoint, bulge: CGFloat = 0.25) -> CGPoint {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return start }
        let normal = CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length)
        let middle = CGPoint(x: (start.x + end.x) / 2 + normal.x * length * bulge, y: (start.y + end.y) / 2 + normal.y * length * bulge)
        return control(passingThrough: middle, from: start, to: end)
    }

    public func point(at t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    public func derivative(at t: CGFloat) -> CGVector {
        CGVector(
            dx: 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x),
            dy: 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        )
    }

    public var midpoint: CGPoint {
        point(at: 0.5)
    }

    public var chordLength: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    public var endTangent: CGVector {
        Self.direction(derivative(at: 1), fallback: CGVector(dx: end.x - start.x, dy: end.y - start.y))
    }

    public var startTangent: CGVector {
        let forward = Self.direction(derivative(at: 0), fallback: CGVector(dx: end.x - start.x, dy: end.y - start.y))
        return CGVector(dx: -forward.dx, dy: -forward.dy)
    }

    public var endTangentAngle: CGFloat {
        atan2(endTangent.dy, endTangent.dx)
    }

    public var startTangentAngle: CGFloat {
        atan2(startTangent.dy, startTangent.dx)
    }

    public func samples(count: Int = QuadraticCurve.sampleCount) -> [CGPoint] {
        let segments = max(1, count)
        return (0 ... segments).map { point(at: CGFloat($0) / CGFloat(segments)) }
    }

    public var bend: CGFloat {
        let length = chordLength
        guard length > 0 else { return hypot(midpoint.x - start.x, midpoint.y - start.y) }
        let middle = midpoint
        return abs((end.x - start.x) * (start.y - middle.y) - (start.x - middle.x) * (end.y - start.y)) / length
    }

    public func isStraight(tolerance: CGFloat) -> Bool {
        bend <= tolerance
    }

    public var boundingBox: CGRect {
        var xs = [start.x, end.x]
        var ys = [start.y, end.y]
        for t in [Self.extremum(start.x, control.x, end.x), Self.extremum(start.y, control.y, end.y)].compactMap({ $0 }) {
            let extreme = point(at: t)
            xs.append(extreme.x)
            ys.append(extreme.y)
        }
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    public func closestParameter(to target: CGPoint) -> CGFloat {
        let segments = 48
        var best: CGFloat = 0
        var bestDistance = CGFloat.infinity
        for index in 0 ... segments {
            let t = CGFloat(index) / CGFloat(segments)
            let distance = Self.squaredDistance(point(at: t), target)
            if distance < bestDistance {
                bestDistance = distance
                best = t
            }
        }
        var low = max(0, best - 1 / CGFloat(segments))
        var high = min(1, best + 1 / CGFloat(segments))
        for _ in 0 ..< 40 {
            let first = low + (high - low) / 3
            let second = high - (high - low) / 3
            if Self.squaredDistance(point(at: first), target) < Self.squaredDistance(point(at: second), target) {
                high = second
            } else {
                low = first
            }
        }
        return (low + high) / 2
    }

    public func distance(to target: CGPoint) -> CGFloat {
        let closest = point(at: closestParameter(to: target))
        return hypot(closest.x - target.x, closest.y - target.y)
    }

    public func split(at t: CGFloat) -> (first: QuadraticCurve, second: QuadraticCurve) {
        let firstControl = Self.lerp(start, control, t)
        let secondControl = Self.lerp(control, end, t)
        let middle = Self.lerp(firstControl, secondControl, t)
        return (QuadraticCurve(start: start, control: firstControl, end: middle), QuadraticCurve(start: middle, control: secondControl, end: end))
    }

    public func parameter(atDistance distance: CGFloat, fromEnd: Bool) -> CGFloat {
        guard distance > 0 else { return fromEnd ? 1 : 0 }
        let anchor = fromEnd ? end : start
        var near: CGFloat = fromEnd ? 1 : 0
        var far: CGFloat = fromEnd ? 0 : 1
        for _ in 0 ..< 24 {
            let middle = (near + far) / 2
            let sample = point(at: middle)
            if hypot(sample.x - anchor.x, sample.y - anchor.y) > distance {
                far = middle
            } else {
                near = middle
            }
        }
        return far
    }

    public func trimmed(startBy startDistance: CGFloat, endBy endDistance: CGFloat) -> QuadraticCurve {
        let headless = split(at: parameter(atDistance: endDistance, fromEnd: true)).first
        return headless.split(at: headless.parameter(atDistance: startDistance, fromEnd: false)).second
    }

    private static func extremum(_ start: CGFloat, _ control: CGFloat, _ end: CGFloat) -> CGFloat? {
        let denominator = start - 2 * control + end
        guard abs(denominator) > 1e-9 else { return nil }
        let t = (start - control) / denominator
        return t > 0 && t < 1 ? t : nil
    }

    private static func direction(_ vector: CGVector, fallback: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        if length > 1e-6 {
            return CGVector(dx: vector.dx / length, dy: vector.dy / length)
        }
        let fallbackLength = hypot(fallback.dx, fallback.dy)
        guard fallbackLength > 1e-6 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: fallback.dx / fallbackLength, dy: fallback.dy / fallbackLength)
    }

    private static func lerp(_ from: CGPoint, _ to: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }

    private static func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        (first.x - second.x) * (first.x - second.x) + (first.y - second.y) * (first.y - second.y)
    }
}
