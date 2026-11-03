import CoreGraphics
import Foundation

public enum ImagePointScale {
    public static let baseDPI: Double = 72
    public static let range: ClosedRange<CGFloat> = 1...4

    public static func scale(dpi: Double?) -> CGFloat? {
        guard let dpi, dpi > 0 else { return nil }
        let scale = (CGFloat(dpi / baseDPI) * 2).rounded() / 2
        return min(max(scale, range.lowerBound), range.upperBound)
    }

    public static func dpi(for scale: CGFloat) -> Double {
        Double(min(max(scale, range.lowerBound), range.upperBound)) * baseDPI
    }
}
