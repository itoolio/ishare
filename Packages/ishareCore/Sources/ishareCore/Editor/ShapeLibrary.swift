import CoreGraphics
import Foundation

public enum LibraryShape: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case roundBubble
    case thoughtBubble
    case bracketLeft
    case bracketRight
    case braceLeft
    case braceRight
    case check
    case cross
    case keycap

    public var id: Self { self }

    public var isClosed: Bool {
        switch self {
        case .roundBubble, .thoughtBubble, .keycap: true
        default: false
        }
    }

    public var holdsText: Bool {
        self == .keycap || self == .roundBubble || self == .thoughtBubble
    }

    public func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        switch self {
        case .roundBubble:
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.8)
            path.addEllipse(in: body)
            path.move(to: CGPoint(x: body.minX + body.width * 0.25, y: body.maxY - body.height * 0.08))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
            path.addLine(to: CGPoint(x: body.minX + body.width * 0.4, y: body.maxY - body.height * 0.02))
        case .thoughtBubble:
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.75)
            path.addEllipse(in: body)
            let small = min(rect.width, rect.height) * 0.09
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.2, y: body.maxY + small * 0.3, width: small * 1.4, height: small * 1.4))
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.08, y: rect.maxY - small, width: small, height: small))
        case .bracketLeft, .bracketRight:
            let inner = self == .bracketLeft ? rect.maxX : rect.minX
            let outer = self == .bracketLeft ? rect.minX : rect.maxX
            path.move(to: CGPoint(x: inner, y: rect.minY))
            path.addLine(to: CGPoint(x: outer, y: rect.minY))
            path.addLine(to: CGPoint(x: outer, y: rect.maxY))
            path.addLine(to: CGPoint(x: inner, y: rect.maxY))
        case .braceLeft, .braceRight:
            let inner = self == .braceLeft ? rect.maxX : rect.minX
            let middle = rect.midX
            let tip = self == .braceLeft ? rect.minX : rect.maxX
            path.move(to: CGPoint(x: inner, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: middle, y: rect.minY + rect.height * 0.15), control: CGPoint(x: middle, y: rect.minY))
            path.addLine(to: CGPoint(x: middle, y: rect.midY - rect.height * 0.08))
            path.addQuadCurve(to: CGPoint(x: tip, y: rect.midY), control: CGPoint(x: middle, y: rect.midY))
            path.addQuadCurve(to: CGPoint(x: middle, y: rect.midY + rect.height * 0.08), control: CGPoint(x: middle, y: rect.midY))
            path.addLine(to: CGPoint(x: middle, y: rect.maxY - rect.height * 0.15))
            path.addQuadCurve(to: CGPoint(x: inner, y: rect.maxY), control: CGPoint(x: middle, y: rect.maxY))
        case .check:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .cross:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .keycap:
            let radius = min(rect.width, rect.height) * 0.18
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            let inset = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
            let face = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height * 0.85)
            path.addRoundedRect(in: face, cornerWidth: radius * 0.7, cornerHeight: radius * 0.7)
        }
        return path
    }

    public func textRect(in rect: CGRect) -> CGRect {
        switch self {
        case .roundBubble: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.8).insetBy(dx: rect.width * 0.15, dy: rect.height * 0.12)
        case .thoughtBubble: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.75).insetBy(dx: rect.width * 0.15, dy: rect.height * 0.12)
        case .keycap:
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.92).insetBy(dx: rect.width * 0.12, dy: rect.height * 0.1)
        default: .null
        }
    }

    public static func svgPathData(_ path: CGPath, format: (CGFloat) -> String) -> String {
        var commands: [String] = []
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                commands.append("M\(format(points[0].x)) \(format(points[0].y))")
            case .addLineToPoint:
                commands.append("L\(format(points[0].x)) \(format(points[0].y))")
            case .addQuadCurveToPoint:
                commands.append("Q\(format(points[0].x)) \(format(points[0].y)) \(format(points[1].x)) \(format(points[1].y))")
            case .addCurveToPoint:
                commands.append(
                    "C\(format(points[0].x)) \(format(points[0].y)) \(format(points[1].x)) \(format(points[1].y)) \(format(points[2].x)) \(format(points[2].y))")
            case .closeSubpath:
                commands.append("Z")
            @unknown default:
                break
            }
        }
        return commands.joined(separator: " ")
    }
}
