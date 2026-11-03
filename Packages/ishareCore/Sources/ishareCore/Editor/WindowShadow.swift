import CoreGraphics
import Foundation

public enum WindowShadowStyle: String, CaseIterable, Sendable {
    case none
    case soft
    case strong

    public var blur: CGFloat {
        switch self {
        case .none: 0
        case .soft: 24
        case .strong: 48
        }
    }

    public var opacity: CGFloat {
        switch self {
        case .none: 0
        case .soft: 0.35
        case .strong: 0.55
        }
    }

    public var offset: CGFloat {
        switch self {
        case .none: 0
        case .soft: 10
        case .strong: 22
        }
    }

    public var padding: CGFloat {
        blur * 2 + offset
    }
}

public enum WindowShadow {
    public static let opaqueAlpha: UInt8 = 250
    public static let minimumTransparentFraction = 0.02

    public static func opaqueBounds(in pixels: RGBAPixels, threshold: UInt8 = opaqueAlpha) -> CGRect? {
        var minX = pixels.width, minY = pixels.height, maxX = -1, maxY = -1
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.pixel(x: x, y: y).3 >= threshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    public static func hasShadow(_ pixels: RGBAPixels, opaque: CGRect) -> Bool {
        let total = Double(pixels.width * pixels.height)
        guard total > 0 else { return false }
        return 1 - Double(opaque.width * opaque.height) / total >= minimumTransparentFraction
    }
}
