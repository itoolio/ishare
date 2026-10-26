import CoreGraphics
import ishareCore

enum ArrowPath: String, CaseIterable, Identifiable, Sendable {
    case straight
    case curved

    var id: Self { self }

    var title: String {
        switch self {
        case .straight: "Straight".localized()
        case .curved: "Curved".localized()
        }
    }

    var symbol: String {
        switch self {
        case .straight: "arrow.up.right"
        case .curved: "arrow.turn.up.right"
        }
    }
}

enum ArrowHead: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case filled
    case open
    case line

    var id: Self { self }

    var title: String {
        switch self {
        case .filled: "Filled Head".localized()
        case .open: "Open Head".localized()
        case .line: "Line Head".localized()
        }
    }

    var symbol: String {
        switch self {
        case .filled: "arrowtriangle.right.fill"
        case .open: "arrowtriangle.right"
        case .line: "chevron.right"
        }
    }
}

enum ArrowGeometry {
    static func curve(from start: CGPoint, control: CGPoint, to end: CGPoint) -> QuadraticCurve {
        QuadraticCurve(start: start, control: control, end: end)
    }

    static func samples(from start: CGPoint, control: CGPoint, to end: CGPoint) -> [CGPoint] {
        curve(from: start, control: control, to: end).samples()
    }

    static func midpoint(from start: CGPoint, control: CGPoint, to end: CGPoint) -> CGPoint {
        curve(from: start, control: control, to: end).midpoint
    }

    static func control(passingThrough midpoint: CGPoint, from start: CGPoint, to end: CGPoint) -> CGPoint {
        QuadraticCurve.control(passingThrough: midpoint, from: start, to: end)
    }

    static func defaultControl(from start: CGPoint, to end: CGPoint) -> CGPoint {
        QuadraticCurve.defaultControl(from: start, to: end)
    }

    static func headLength(for width: CGFloat, length: CGFloat) -> CGFloat {
        min(length * 0.6, max(14, width * 4.5))
    }

    static func headPoints(tip: CGPoint, from tail: CGPoint, headLength: CGFloat) -> (left: CGPoint, right: CGPoint) {
        headPoints(tip: tip, angle: atan2(tip.y - tail.y, tip.x - tail.x), headLength: headLength)
    }

    static func headPoints(tip: CGPoint, angle: CGFloat, headLength: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let headWidth = headLength * 0.8
        let left = CGPoint(x: tip.x - cos(angle) * headLength + sin(angle) * headWidth / 2, y: tip.y - sin(angle) * headLength - cos(angle) * headWidth / 2)
        let right = CGPoint(x: tip.x - cos(angle) * headLength - sin(angle) * headWidth / 2, y: tip.y - sin(angle) * headLength + cos(angle) * headWidth / 2)
        return (left, right)
    }

    static func headAngles(start: CGPoint, control: CGPoint?, end: CGPoint) -> (end: CGFloat, start: CGFloat) {
        guard let control else {
            let angle = atan2(end.y - start.y, end.x - start.x)
            return (angle, angle + .pi)
        }
        let curve = curve(from: start, control: control, to: end)
        return (curve.endTangentAngle, curve.startTangentAngle)
    }

    static func trimmed(start: CGPoint, control: CGPoint, end: CGPoint, startBy startDistance: CGFloat, endBy endDistance: CGFloat) -> (
        start: CGPoint, control: CGPoint, end: CGPoint
    ) {
        let trimmed = curve(from: start, control: control, to: end).trimmed(startBy: startDistance, endBy: endDistance)
        return (trimmed.start, trimmed.control, trimmed.end)
    }

    static func retracted(_ tip: CGPoint, toward tail: CGPoint, by distance: CGFloat) -> CGPoint {
        let length = hypot(tip.x - tail.x, tip.y - tail.y)
        guard length > 0 else { return tip }
        return CGPoint(x: tip.x - (tip.x - tail.x) / length * distance, y: tip.y - (tip.y - tail.y) / length * distance)
    }
}
