import CoreGraphics
import Testing
@testable import ishareCore

struct TranslationOverlayTests {
    @Test func fitsTheTextToTheLineHeight() {
        let placement = TranslationOverlay.placement(for: CGRect(x: 10, y: 100, width: 500, height: 20), textWidthAtUnitSize: 5)
        #expect(abs(placement.fontSize - 15.6) < 0.001)
        #expect(placement.origin.x == 10)
        #expect(abs(placement.origin.y - (110 - 15.6 * 1.2 / 2)) < 0.001)
    }

    @Test func shrinksLongTranslationsToTheLineWidth() {
        let placement = TranslationOverlay.placement(for: CGRect(x: 0, y: 0, width: 100, height: 20), textWidthAtUnitSize: 10)
        #expect(placement.fontSize == 10)
        #expect(TranslationOverlay.placement(for: CGRect(x: 0, y: 0, width: 10, height: 20), textWidthAtUnitSize: 10).fontSize == TranslationOverlay.minimumFontSize)
    }

    @Test func samplesTheColorAroundTheText() {
        let width = 20, height = 20
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width + x) * 4
                let inside = (6 ..< 14).contains(x) && (6 ..< 14).contains(y)
                bytes[index] = inside ? 0 : 255
                bytes[index + 1] = inside ? 0 : 128
                bytes[index + 2] = inside ? 0 : 0
                bytes[index + 3] = 255
            }
        }
        let color = TranslationOverlay.backgroundColor(around: CGRect(x: 6, y: 6, width: 8, height: 8), in: RGBAPixels(width: width, height: height, bytes: bytes))
        #expect(color == OverlayColor(red: 1, green: 128.0 / 255, blue: 0))
    }
}
