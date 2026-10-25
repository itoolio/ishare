import CoreGraphics

enum EditHandle: Hashable, Sendable {
    case resize(ResizeHandle)
    case start
    case end
    case control
}

extension Annotation {
    var editableRect: CGRect? {
        switch shape {
        case let .rectangle(rect), let .ellipse(rect), let .highlight(rect), let .magnify(rect), let .spotlight(rect),
            let .blur(rect), let .pixelate(rect), let .eraser(rect), let .stamp(rect, _):
            rect
        default:
            nil
        }
    }

    var keepsSquareProportions: Bool {
        switch shape {
        case .magnify, .stamp: true
        default: false
        }
    }

    var editHandles: [(EditHandle, CGPoint)] {
        switch shape {
        case let .arrow(start, end), let .line(start, end):
            return [(.start, start), (.control, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)), (.end, end)]
        case let .curvedArrow(start, control, end), let .curvedLine(start, control, end):
            return [(.start, start), (.control, ArrowGeometry.midpoint(from: start, control: control, to: end)), (.end, end)]
        default:
            guard let rect = editableRect else { return [] }
            let handles = keepsSquareProportions ? ResizeHandle.allCases.filter(\.isCorner) : ResizeHandle.allCases
            return handles.map { (.resize($0), $0.point(in: rect)) }
        }
    }

    func editHandle(at point: CGPoint, tolerance: CGFloat) -> EditHandle? {
        editHandles
            .map { ($0.0, hypot($0.1.x - point.x, $0.1.y - point.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    func editing(_ handle: EditHandle, to point: CGPoint) -> Annotation {
        var copy = self
        switch (shape, handle) {
        case let (.arrow(_, end), .start): copy.shape = .arrow(point, end)
        case let (.arrow(start, _), .end): copy.shape = .arrow(start, point)
        case let (.line(_, end), .start): copy.shape = .line(point, end)
        case let (.line(start, _), .end): copy.shape = .line(start, point)
        case let (.arrow(start, end), .control):
            copy.shape = .curvedArrow(start, ArrowGeometry.control(passingThrough: point, from: start, to: end), end)
        case let (.line(start, end), .control):
            copy.shape = .curvedLine(start, ArrowGeometry.control(passingThrough: point, from: start, to: end), end)
        case let (.curvedArrow(start, control, end), .start), let (.curvedLine(start, control, end), .start):
            let midpoint = ArrowGeometry.midpoint(from: start, control: control, to: end)
            copy.shape = bent(point, ArrowGeometry.control(passingThrough: midpoint, from: point, to: end), end)
        case let (.curvedArrow(start, control, end), .end), let (.curvedLine(start, control, end), .end):
            let midpoint = ArrowGeometry.midpoint(from: start, control: control, to: end)
            copy.shape = bent(start, ArrowGeometry.control(passingThrough: midpoint, from: start, to: point), point)
        case let (.curvedArrow(start, _, end), .control), let (.curvedLine(start, _, end), .control):
            copy.shape = bent(start, ArrowGeometry.control(passingThrough: point, from: start, to: end), end)
        case let (_, .resize(resizeHandle)):
            guard let rect = editableRect else { return self }
            let unbounded = CGRect(x: -1e7, y: -1e7, width: 2e7, height: 2e7)
            let newRect = CropGeometry.resize(rect, handle: resizeHandle, to: point, ratio: keepsSquareProportions ? 1 : nil, bounds: unbounded)
            copy = resized(to: newRect)
        default:
            break
        }
        return copy
    }

    private func bent(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint) -> Shape {
        isArrow ? .curvedArrow(start, control, end) : .curvedLine(start, control, end)
    }

    var curveControlPoints: (CGPoint, CGPoint, CGPoint)? {
        switch shape {
        case let .curvedArrow(start, control, end), let .curvedLine(start, control, end): (start, control, end)
        default: nil
        }
    }

    var isCurved: Bool {
        switch shape {
        case .curvedArrow, .curvedLine: true
        default: false
        }
    }

    var supportsBending: Bool {
        switch shape {
        case .arrow, .line, .curvedArrow, .curvedLine: true
        default: false
        }
    }

    func straightened() -> Annotation {
        var copy = self
        switch shape {
        case let .curvedArrow(start, _, end): copy.shape = .arrow(start, end)
        case let .curvedLine(start, _, end): copy.shape = .line(start, end)
        default: break
        }
        return copy
    }

    func resized(to rect: CGRect) -> Annotation {
        var copy = self
        switch shape {
        case .rectangle: copy.shape = .rectangle(rect)
        case .ellipse: copy.shape = .ellipse(rect)
        case .highlight: copy.shape = .highlight(rect)
        case .magnify: copy.shape = .magnify(rect)
        case .spotlight: copy.shape = .spotlight(rect)
        case .blur: copy.shape = .blur(rect)
        case .pixelate: copy.shape = .pixelate(rect)
        case .eraser: copy.shape = .eraser(rect)
        case let .stamp(_, stamp): copy.shape = .stamp(rect, stamp)
        default: break
        }
        return copy
    }

    var isArrow: Bool {
        switch shape {
        case .arrow, .curvedArrow: true
        default: false
        }
    }

    var supportsDash: Bool {
        switch shape {
        case .arrow, .curvedArrow, .line, .curvedLine: true
        case .rectangle, .ellipse: !filled
        default: false
        }
    }
}
