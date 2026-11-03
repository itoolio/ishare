import CoreGraphics
import Foundation

public enum FollowPointerSize: String, CaseIterable, Codable, Sendable {
    case hd720
    case hd1080
    case square
    case portrait

    public func pointSize(fitting display: CGSize) -> CGSize {
        let wanted: CGSize =
            switch self {
            case .hd720: CGSize(width: 1280, height: 720)
            case .hd1080: CGSize(width: 1920, height: 1080)
            case .square: CGSize(width: 900, height: 900)
            case .portrait: CGSize(width: 720, height: 1280)
            }
        let fit = min(1, display.width / wanted.width, display.height / wanted.height)
        return CGSize(width: (wanted.width * fit).rounded(), height: (wanted.height * fit).rounded())
    }
}

public struct PointerFollowCamera: Equatable, Sendable {
    public static let defaultDeadZone: CGFloat = 0.3
    public static let defaultTimeConstant: Double = 0.18

    public let display: CGSize
    public let size: CGSize
    public var deadZone: CGFloat
    public var timeConstant: Double
    public private(set) var origin: CGPoint

    public init(display: CGSize, size: CGSize, centeredAt point: CGPoint, deadZone: CGFloat = defaultDeadZone, timeConstant: Double = defaultTimeConstant) {
        self.display = display
        self.size = CGSize(width: min(size.width, display.width), height: min(size.height, display.height))
        self.deadZone = deadZone
        self.timeConstant = timeConstant
        origin = .zero
        origin = clamped(CGPoint(x: point.x - self.size.width / 2, y: point.y - self.size.height / 2))
    }

    public var rect: CGRect {
        CGRect(origin: origin, size: size)
    }

    public func target(for pointer: CGPoint) -> CGPoint {
        let marginX = size.width * deadZone / 2
        let marginY = size.height * deadZone / 2
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let dx = Self.excess(pointer.x - center.x, allowance: marginX)
        let dy = Self.excess(pointer.y - center.y, allowance: marginY)
        return clamped(CGPoint(x: origin.x + dx, y: origin.y + dy))
    }

    @discardableResult
    public mutating func step(toward pointer: CGPoint, elapsed: Double) -> Bool {
        let goal = target(for: pointer)
        let alpha = timeConstant > 0 ? 1 - exp(-max(0, elapsed) / timeConstant) : 1
        var next = CGPoint(x: origin.x + (goal.x - origin.x) * alpha, y: origin.y + (goal.y - origin.y) * alpha)
        if abs(goal.x - next.x) < 0.5 { next.x = goal.x }
        if abs(goal.y - next.y) < 0.5 { next.y = goal.y }
        next = CGPoint(x: next.x.rounded(), y: next.y.rounded())
        guard next != origin else { return false }
        origin = next
        return true
    }

    static func excess(_ offset: CGFloat, allowance: CGFloat) -> CGFloat {
        if offset > allowance { return offset - allowance }
        if offset < -allowance { return offset + allowance }
        return 0
    }

    func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), display.width - size.width), y: min(max(point.y, 0), display.height - size.height))
    }
}
