import CoreGraphics
import Foundation
import Testing
@testable import ishare

struct QRCodeTests {
    @Test func rendersSquareModulesScaledToWholePixels() throws {
        let modules = try #require(QRCodeRenderer.moduleImage(for: "https://example.com/a.png"))
        #expect(modules.width == modules.height)
        let image = try #require(QRCodeRenderer.image(for: "https://example.com/a.png", targetPixels: 512))
        let scale = QRCodeRenderer.scaleFactor(moduleCount: modules.width, targetPixels: 512)
        #expect(scale > 1)
        #expect(image.width == modules.width * scale)
        #expect(image.height == image.width)
        #expect(image.width <= 512)
    }

    @Test func scalesWithNearestNeighborSoEveryPixelIsBlackOrWhite() throws {
        let image = try #require(QRCodeRenderer.image(for: "https://example.com/crisp", targetPixels: 300))
        let width = image.width
        var pixels = [UInt8](repeating: 0, count: width * image.height)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: image.height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        #expect(pixels.allSatisfy { $0 == 0 || $0 == 255 })
        #expect(pixels.contains(0))
        #expect(pixels.contains(255))
    }

    @Test func neverScalesBelowOnePixelPerModule() {
        #expect(QRCodeRenderer.scaleFactor(moduleCount: 41, targetPixels: 20) == 1)
        #expect(QRCodeRenderer.scaleFactor(moduleCount: 0, targetPixels: 20) == 1)
        #expect(QRCodeRenderer.scaleFactor(moduleCount: 25, targetPixels: 512) == 20)
    }

    @Test func rejectsEmptyText() {
        #expect(QRCodeRenderer.image(for: "") == nil)
    }

    @MainActor @Test func listsAlternativeAddressesAfterThePrimaryOne() throws {
        let primary = try #require(URL(string: "http://192.168.1.2:5000/t/a.png"))
        let other = try #require(URL(string: "http://10.0.0.2:5000/t/a.png"))
        let model = QRCodeModel(content: QRCodeContent(url: primary, title: "t", alternatives: [primary, other]), onStop: nil)
        #expect(model.choices == [primary, other])
        #expect(model.selectedURL == primary)
    }
}
