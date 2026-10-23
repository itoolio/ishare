import CoreGraphics

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
    static let curveSamples = 32

    static func point(onCurveFrom start: CGPoint, control: CGPoint, to end: CGPoint, at t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    static func samples(from start: CGPoint, control: CGPoint, to end: CGPoint) -> [CGPoint] {
        (0 ... curveSamples).map { point(onCurveFrom: start, control: control, to: end, at: CGFloat($0) / CGFloat(curveSamples)) }
    }

    static func midpoint(from start: CGPoint, control: CGPoint, to end: CGPoint) -> CGPoint {
        point(onCurveFrom: start, control: control, to: end, at: 0.5)
    }

    static func control(passingThrough midpoint: CGPoint, from start: CGPoint, to end: CGPoint) -> CGPoint {
        CGPoint(x: 2 * midpoint.x - (start.x + end.x) / 2, y: 2 * midpoint.y - (start.y + end.y) / 2)
    }

    static func defaultControl(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return start }
        let normal = CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length)
        let bulge = length * 0.25
        let middle = CGPoint(x: (start.x + end.x) / 2 + normal.x * bulge, y: (start.y + end.y) / 2 + normal.y * bulge)
        return control(passingThrough: middle, from: start, to: end)
    }

    static func headLength(for width: CGFloat, length: CGFloat) -> CGFloat {
        min(length * 0.6, max(14, width * 4.5))
    }

    static func headPoints(tip: CGPoint, from tail: CGPoint, headLength: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let headWidth = headLength * 0.8
        let left = CGPoint(x: tip.x - cos(angle) * headLength + sin(angle) * headWidth / 2, y: tip.y - sin(angle) * headLength - cos(angle) * headWidth / 2)
        let right = CGPoint(x: tip.x - cos(angle) * headLength - sin(angle) * headWidth / 2, y: tip.y - sin(angle) * headLength + cos(angle) * headWidth / 2)
        return (left, right)
    }

    static func parameter(at distance: CGFloat, fromEndOf start: CGPoint, control: CGPoint, end: CGPoint) -> CGFloat {
        guard distance > 0 else { return 1 }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0 ..< 24 {
            let middle = (low + high) / 2
            let point = point(onCurveFrom: start, control: control, to: end, at: middle)
            if hypot(point.x - end.x, point.y - end.y) > distance {
                low = middle
            } else {
                high = middle
            }
        }
        return low
    }

    static func trimmed(start: CGPoint, control: CGPoint, end: CGPoint, startBy startDistance: CGFloat, endBy endDistance: CGFloat) -> (start: CGPoint, control: CGPoint, end: CGPoint) {
        let endT = parameter(at: endDistance, fromEndOf: start, control: control, end: end)
        let firstControl = CGPoint(x: start.x + (control.x - start.x) * endT, y: start.y + (control.y - start.y) * endT)
        let firstEnd = point(onCurveFrom: start, control: control, to: end, at: endT)
        let startT = parameter(at: startDistance, fromEndOf: firstEnd, control: firstControl, end: start)
        let secondControl = CGPoint(x: firstEnd.x + (firstControl.x - firstEnd.x) * startT, y: firstEnd.y + (firstControl.y - firstEnd.y) * startT)
        let secondStart = point(onCurveFrom: firstEnd, control: firstControl, to: start, at: startT)
        return (secondStart, secondControl, firstEnd)
    }

    static func retracted(_ tip: CGPoint, toward tail: CGPoint, by distance: CGFloat) -> CGPoint {
        let length = hypot(tip.x - tail.x, tip.y - tail.y)
        guard length > 0 else { return tip }
        return CGPoint(x: tip.x - (tip.x - tail.x) / length * distance, y: tip.y - (tip.y - tail.y) / length * distance)
    }
}
