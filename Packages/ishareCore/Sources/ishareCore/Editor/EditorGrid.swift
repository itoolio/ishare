import CoreGraphics
import Foundation

public struct EditorGrid: Equatable, Sendable {
    public static let spacingChoices = [8, 10, 16, 20, 25, 32, 50, 64, 100]
    public static let minimumOnScreenSpacing: CGFloat = 6

    public var spacing: CGFloat

    public init(spacing: CGFloat) {
        self.spacing = max(1, spacing)
    }

    public func snap(_ value: CGFloat) -> CGFloat {
        (value / spacing).rounded() * spacing
    }

    public func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: snap(point.x), y: snap(point.y))
    }

    public func offsetSnapping(_ rect: CGRect, movedBy delta: CGVector) -> CGVector {
        let target = CGPoint(x: snap(rect.minX + delta.dx), y: snap(rect.minY + delta.dy))
        return CGVector(dx: target.x - rect.minX, dy: target.y - rect.minY)
    }

    public func lines(in rect: CGRect, scale: CGFloat) -> (vertical: [CGFloat], horizontal: [CGFloat]) {
        guard spacing * scale >= Self.minimumOnScreenSpacing, rect.width > 0, rect.height > 0 else { return ([], []) }
        func positions(from low: CGFloat, to high: CGFloat) -> [CGFloat] {
            let first = (low / spacing).rounded(.up) * spacing
            return Array(stride(from: first, through: high, by: spacing))
        }
        return (positions(from: rect.minX, to: rect.maxX), positions(from: rect.minY, to: rect.maxY))
    }
}

public struct RulerTick: Equatable, Sendable {
    public var position: CGFloat
    public var isMajor: Bool
    public var label: String?
}

public enum Ruler {
    public static let steps: [CGFloat] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]
    public static let minimumMajorSpacing: CGFloat = 60

    public static func majorStep(forScale scale: CGFloat) -> CGFloat {
        steps.first { $0 * scale >= minimumMajorSpacing } ?? steps[steps.count - 1]
    }

    public static func ticks(from low: CGFloat, to high: CGFloat, scale: CGFloat) -> [RulerTick] {
        guard high > low, scale > 0 else { return [] }
        let major = majorStep(forScale: scale)
        let minor = major / (major * scale >= 120 ? 10 : 5)
        let firstIndex = Int((low / minor).rounded(.up))
        let lastIndex = Int((high / minor).rounded(.down))
        guard firstIndex <= lastIndex else { return [] }
        return (firstIndex ... lastIndex).map { index in
            let value = CGFloat(index) * minor
            let isMajor = abs((value / major).rounded() * major - value) < minor / 2
            return RulerTick(position: value, isMajor: isMajor, label: isMajor ? String(Int(value.rounded())) : nil)
        }
    }
}
