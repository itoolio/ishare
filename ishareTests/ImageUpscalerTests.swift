import CoreGraphics
import Foundation
import ishareCore
import Testing
@testable import ishare

private enum Synthetic {
    static func disc(size: Int, inset: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setShouldAntialias(true)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(CGFloat(size) / 32)
        context.move(to: CGPoint(x: 0, y: CGFloat(size) * 0.1))
        context.addLine(to: CGPoint(x: CGFloat(size), y: CGFloat(size) * 0.35))
        context.strokePath()
        return context.makeImage()!
    }

    static func resampled(_ image: CGImage, width: Int, height: Int, quality: CGInterpolationQuality) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = quality
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func gray(_ image: CGImage) -> [Double] {
        guard let pixels = ImageUpscaler.PixelBuffer(image: image) else { return [] }
        return stride(from: 0, to: pixels.bytes.count, by: 4).map { index in
            (Double(pixels.bytes[index]) + Double(pixels.bytes[index + 1]) + Double(pixels.bytes[index + 2])) / (3 * 255)
        }
    }

    static func meanError(_ image: CGImage, against reference: CGImage) -> Double {
        let first = gray(image)
        let second = gray(reference)
        guard first.count == second.count, !first.isEmpty else { return .infinity }
        return zip(first, second).map { abs($0 - $1) }.reduce(0, +) / Double(first.count)
    }
}

@MainActor
struct ImageUpscalerTests {
    @Test(arguments: [UpscaleFactor.double, .quadruple], [UpscaleMethod.lanczos, .automatic])
    func producesTheRequestedSizeWithFiniteValues(factor: UpscaleFactor, method: UpscaleMethod) throws {
        let source = Synthetic.disc(size: 64, inset: 8)
        let upscaled = try #require(ImageUpscaler.upscale(source, by: factor, method: method))
        #expect(upscaled.width == 64 * factor.rawValue)
        #expect(upscaled.height == 64 * factor.rawValue)
        let values = Synthetic.gray(upscaled)
        #expect(values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        #expect(Set(values.map { Int($0 * 10) }).count > 2)
    }

    @Test(arguments: [UpscaleMethod.lanczos, .automatic])
    func reconstructsEdgesBetterThanNearestNeighbor(method: UpscaleMethod) throws {
        let reference = Synthetic.disc(size: 256, inset: 30)
        let small = Synthetic.resampled(reference, width: 64, height: 64, quality: .high)
        let nearest = Synthetic.resampled(small, width: 256, height: 256, quality: .none)
        let upscaled = try #require(ImageUpscaler.upscale(small, by: .quadruple, method: method))
        let upscaledError = Synthetic.meanError(upscaled, against: reference)
        let nearestError = Synthetic.meanError(nearest, against: reference)
        #expect(upscaledError.isFinite)
        #expect(upscaledError < nearestError)
    }

    @Test func metalFXRunsOffScreenWhenSupported() throws {
        let source = Synthetic.disc(size: 48, inset: 6)
        guard ImageUpscaler.supportsMetalFX else {
            #expect(ImageUpscaler.metalFX(source, factor: .double) == nil)
            return
        }
        let upscaled = try #require(ImageUpscaler.metalFX(source, factor: .double))
        #expect(upscaled.width == 96)
    }

    @Test func transparentImagesKeepTheirAlpha() throws {
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
        let source = try #require(context.makeImage())
        #expect(ImageUpscaler.metalFX(source, factor: .double) == nil)
        let upscaled = try #require(ImageUpscaler.upscale(source, by: .double))
        let pixels = try #require(ImageUpscaler.PixelBuffer(image: upscaled))
        #expect(pixels.bytes[3] == 0)
        #expect(!pixels.isOpaque)
    }

    @Test func refusesResultsLargerThanTheLimit() {
        let wide = Synthetic.resampled(Synthetic.disc(size: 8, inset: 1), width: 4200, height: 2, quality: .none)
        #expect(ImageUpscaler.upscale(wide, by: .quadruple) == nil)
        let document = EditorDocument(image: wide, fileURL: nil)
        #expect(document.canUpscale(by: .double))
        #expect(!document.canUpscale(by: .quadruple))
    }

    @Test func upscalingTheDocumentScalesAnnotationsAndUndoes() async throws {
        let document = EditorDocument(image: Synthetic.disc(size: 100, inset: 10), fileURL: nil)
        var rectangle = Annotation(shape: .rectangle(CGRect(x: 10, y: 20, width: 30, height: 40)), color: .red, lineWidth: 4)
        rectangle.rotation = 0.2
        let text = Annotation(shape: .text(CGPoint(x: 5, y: 5), "Hi"), color: .red, lineWidth: 2, fontSize: 18)
        document.add(rectangle)
        document.add(text)
        document.applyCrop(CGRect(x: 0, y: 0, width: 50, height: 60))
        #expect(await document.upscale(by: .double, method: .lanczos))
        #expect(document.imageSize == CGSize(width: 200, height: 200))
        let scaled = try #require(document.annotations.first { $0.id == rectangle.id })
        #expect(scaled.shape == .rectangle(CGRect(x: 20, y: 40, width: 60, height: 80)))
        #expect(scaled.lineWidth == 8)
        #expect(scaled.rotation == 0.2)
        #expect(document.annotations.first { $0.id == text.id }?.fontSize == 36)
        #expect(document.crop == CGRect(x: 0, y: 0, width: 100, height: 120))
        #expect(!document.isProcessing)
        document.undo()
        #expect(document.imageSize == CGSize(width: 100, height: 100))
        #expect(document.annotations.first { $0.id == rectangle.id } == rectangle)
    }

    @Test func titlesShowTheResultingSize() {
        #expect(UpscaleFlow.title(for: .double, size: CGSize(width: 300, height: 200)) == "2× — 600 × 400")
    }
}
