import CoreGraphics
import Foundation

public enum UpscaleFactor: Int, CaseIterable, Identifiable, Sendable {
    case double = 2
    case quadruple = 4

    public var id: Self { self }

    public var scale: CGFloat { CGFloat(rawValue) }

    public var passes: Int {
        switch self {
        case .double: 1
        case .quadruple: 2
        }
    }
}

public enum UpscaleGeometry {
    public static let maximumPixelsPerSide = 16_384

    public static func outputSize(for size: CGSize, factor: UpscaleFactor) -> CGSize {
        CGSize(width: (size.width * factor.scale).rounded(), height: (size.height * factor.scale).rounded())
    }

    public static func canUpscale(_ size: CGSize, by factor: UpscaleFactor, maximum: Int = maximumPixelsPerSide) -> Bool {
        guard size.width >= 1, size.height >= 1 else { return false }
        let output = outputSize(for: size, factor: factor)
        return output.width <= CGFloat(maximum) && output.height <= CGFloat(maximum)
    }

    public static func availableFactors(for size: CGSize, maximum: Int = maximumPixelsPerSide) -> [UpscaleFactor] {
        UpscaleFactor.allCases.filter { canUpscale(size, by: $0, maximum: maximum) }
    }
}
