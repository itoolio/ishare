import CoreGraphics
import Foundation

public struct OverlayColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct TranslationOverlayPlacement: Equatable, Sendable {
    public var origin: CGPoint
    public var fontSize: CGFloat
}

public enum TranslationOverlay {
    public static let heightFill: CGFloat = 0.78
    public static let minimumFontSize: CGFloat = 6
    public static let ringWidth = 3

    public static func placement(for line: CGRect, textWidthAtUnitSize: CGFloat, lineHeightAtUnitSize: CGFloat = 1.2) -> TranslationOverlayPlacement {
        let byHeight = line.height * heightFill
        let byWidth = textWidthAtUnitSize > 0 ? line.width / textWidthAtUnitSize : byHeight
        let fontSize = max(minimumFontSize, min(byHeight, byWidth))
        let textHeight = fontSize * lineHeightAtUnitSize
        return TranslationOverlayPlacement(origin: CGPoint(x: line.minX, y: line.midY - textHeight / 2), fontSize: fontSize)
    }

    public static func backgroundColor(around rect: CGRect, in pixels: RGBAPixels) -> OverlayColor? {
        let outer = rect.insetBy(dx: -CGFloat(ringWidth), dy: -CGFloat(ringWidth)).integral
        let minX = max(0, Int(outer.minX)), maxX = min(pixels.width - 1, Int(outer.maxX))
        let minY = max(0, Int(outer.minY)), maxY = min(pixels.height - 1, Int(outer.maxY))
        guard minX <= maxX, minY <= maxY else { return nil }
        let inner = rect.integral
        var reds: [UInt8] = [], greens: [UInt8] = [], blues: [UInt8] = []
        for y in minY...maxY {
            for x in minX...maxX where !inner.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                let pixel = pixels.pixel(x: x, y: y)
                reds.append(pixel.0)
                greens.append(pixel.1)
                blues.append(pixel.2)
            }
        }
        guard !reds.isEmpty else { return nil }
        return OverlayColor(red: median(reds), green: median(greens), blue: median(blues))
    }

    static func median(_ values: [UInt8]) -> Double {
        let sorted = values.sorted()
        return Double(sorted[sorted.count / 2]) / 255
    }
}
