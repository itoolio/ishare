import AppKit
import CoreGraphics

struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let red = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    static let orange = RGBAColor(red: 1, green: 0.58, blue: 0)
    static let yellow = RGBAColor(red: 1, green: 0.8, blue: 0)
    static let green = RGBAColor(red: 0.2, green: 0.78, blue: 0.35)
    static let blue = RGBAColor(red: 0, green: 0.48, blue: 1)
    static let purple = RGBAColor(red: 0.69, green: 0.32, blue: 0.87)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
        alpha = Double(converted.alphaComponent)
    }

    var contrastingText: RGBAColor {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}

enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case arrow
    case line
    case rectangle
    case ellipse
    case highlight
    case pen
    case marker
    case text
    case step
    case blur
    case pixelate
    case crop

    var id: Self { self }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "rectangle.fill"
        case .pen: "scribble"
        case .marker: "highlighter"
        case .text: "textformat"
        case .step: "1.circle"
        case .blur: "drop"
        case .pixelate: "squareshape.split.3x3"
        case .crop: "crop"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        case .pen: "Pen"
        case .marker: "Marker"
        case .text: "Text"
        case .step: "Step"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .crop: "Crop"
        }
    }

    var shortcut: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .highlight: "h"
        case .pen: "p"
        case .marker: "m"
        case .text: "t"
        case .step: "n"
        case .blur: "b"
        case .pixelate: "x"
        case .crop: "c"
        }
    }
}

struct Annotation: Identifiable, Hashable, Sendable {
    enum Shape: Hashable, Sendable {
        case arrow(CGPoint, CGPoint)
        case line(CGPoint, CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case highlight(CGRect)
        case pen([CGPoint])
        case marker([CGPoint])
        case text(CGPoint, String)
        case step(CGPoint, Int)
        case blur(CGRect)
        case pixelate(CGRect)
    }

    var id = UUID()
    var shape: Shape
    var color: RGBAColor
    var lineWidth: CGFloat
    var fontSize: CGFloat = 32

    var isEffect: Bool {
        switch shape {
        case .blur, .pixelate: true
        default: false
        }
    }

    var bounds: CGRect {
        switch shape {
        case let .arrow(start, end), let .line(start, end):
            ScreenGeometry.rect(from: start, to: end).insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case let .rectangle(rect), let .ellipse(rect), let .highlight(rect), let .blur(rect), let .pixelate(rect):
            rect
        case let .pen(points), let .marker(points):
            Annotation.boundingRect(of: points).insetBy(dx: -lineWidth, dy: -lineWidth)
        case let .text(origin, string):
            CGRect(origin: origin, size: AnnotationRenderer.textSize(string, fontSize: fontSize))
        case let .step(center, _):
            CGRect(x: center.x - stepRadius, y: center.y - stepRadius, width: stepRadius * 2, height: stepRadius * 2)
        }
    }

    var stepRadius: CGFloat {
        max(14, fontSize * 0.7)
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch shape {
        case let .arrow(start, end), let .line(start, end):
            Annotation.distance(from: point, toSegment: start, end) <= max(tolerance, lineWidth)
        case let .pen(points), let .marker(points):
            zip(points, points.dropFirst()).contains { Annotation.distance(from: point, toSegment: $0, $1) <= max(tolerance, lineWidth) }
        default:
            bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    func offset(by delta: CGVector) -> Annotation {
        var copy = self
        func move(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        func move(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: delta.dx, dy: delta.dy) }
        copy.shape = switch shape {
        case let .arrow(start, end): .arrow(move(start), move(end))
        case let .line(start, end): .line(move(start), move(end))
        case let .rectangle(rect): .rectangle(move(rect))
        case let .ellipse(rect): .ellipse(move(rect))
        case let .highlight(rect): .highlight(move(rect))
        case let .pen(points): .pen(points.map(move))
        case let .marker(points): .marker(points.map(move))
        case let .text(origin, string): .text(move(origin), string)
        case let .step(center, number): .step(move(center), number)
        case let .blur(rect): .blur(move(rect))
        case let .pixelate(rect): .pixelate(move(rect))
        }
        return copy
    }

    static func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }
}
