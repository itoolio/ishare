import CoreGraphics
import Testing
@testable import ishareCore

struct BorderTrimTests {
    private func canvas(width: Int, height: Int, background: [UInt8], content: CGRect, color: [UInt8], noise: [(Int, Int)] = []) -> RGBAPixels {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let inside = content.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                let value = inside ? color : background
                bytes.replaceSubrange((y * width + x) * 4 ..< (y * width + x) * 4 + 4, with: value)
            }
        }
        for (x, y) in noise {
            bytes.replaceSubrange((y * width + x) * 4 ..< (y * width + x) * 4 + 4, with: color)
        }
        return RGBAPixels(width: width, height: height, bytes: bytes)
    }

    @Test func findsContentInsideAUniformBorder() {
        let pixels = canvas(width: 60, height: 40, background: [255, 255, 255, 255], content: CGRect(x: 10, y: 5, width: 30, height: 20), color: [20, 40, 60, 255])
        #expect(BorderTrim.contentRect(in: pixels) == CGRect(x: 10, y: 5, width: 30, height: 20))
    }

    @Test func treatsAllTransparentPixelsAsTheSameBorder() {
        let pixels = canvas(width: 50, height: 50, background: [10, 200, 30, 0], content: CGRect(x: 20, y: 20, width: 5, height: 5), color: [255, 0, 0, 255])
        #expect(BorderTrim.contentRect(in: pixels) == CGRect(x: 20, y: 20, width: 5, height: 5))
    }

    @Test func toleratesSlightColourNoiseInTheBorder() {
        var pixels = canvas(width: 40, height: 40, background: [240, 240, 240, 255], content: CGRect(x: 8, y: 8, width: 20, height: 20), color: [0, 0, 0, 255])
        pixels.bytes[0] = 246
        #expect(BorderTrim.contentRect(in: pixels) == CGRect(x: 8, y: 8, width: 20, height: 20))
    }

    @Test func addsPaddingWithinTheImage() {
        let pixels = canvas(width: 60, height: 40, background: [255, 255, 255, 255], content: CGRect(x: 2, y: 5, width: 30, height: 20), color: [0, 0, 0, 255])
        #expect(BorderTrim.contentRect(in: pixels, padding: 4) == CGRect(x: 0, y: 1, width: 36, height: 28))
    }

    @Test func returnsNothingForUniformOrBorderlessImages() {
        let uniform = canvas(width: 30, height: 30, background: [9, 9, 9, 255], content: .zero, color: [9, 9, 9, 255])
        #expect(BorderTrim.contentRect(in: uniform) == nil)
        let full = canvas(width: 30, height: 30, background: [0, 0, 0, 255], content: CGRect(x: 0, y: 0, width: 30, height: 30), color: [200, 0, 0, 255])
        #expect(BorderTrim.contentRect(in: full) == nil)
    }
}
