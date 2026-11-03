import CoreGraphics
import Testing
@testable import ishareCore

struct WindowShadowTests {
    func pixels(width: Int, height: Int, opaque: CGRect) -> RGBAPixels {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inside = opaque.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
                bytes[(y * width + x) * 4 + 3] = inside ? 255 : 60
            }
        }
        return RGBAPixels(width: width, height: height, bytes: bytes)
    }

    @Test func findsTheWindowInsideItsShadow() {
        let image = pixels(width: 40, height: 30, opaque: CGRect(x: 6, y: 4, width: 28, height: 20))
        let bounds = WindowShadow.opaqueBounds(in: image)
        #expect(bounds == CGRect(x: 6, y: 4, width: 28, height: 20))
        #expect(WindowShadow.hasShadow(image, opaque: bounds!))
    }

    @Test func leavesShadowlessImagesAlone() {
        let image = pixels(width: 20, height: 20, opaque: CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(!WindowShadow.hasShadow(image, opaque: WindowShadow.opaqueBounds(in: image)!))
        #expect(WindowShadowStyle.strong.padding > WindowShadowStyle.soft.padding)
    }
}
