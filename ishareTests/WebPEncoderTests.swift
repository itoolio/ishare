import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ishare

struct WebPEncoderTests {
    private func image(width: Int, height: Int, alpha: CGFloat, red: CGFloat = 1) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.4, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        return try #require(context.makeImage())
    }

    private func decoded(_ data: Data) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithData(data as CFData, nil))
    }

    @Test func encodesLosslessStillsThatImageIOCanRead() throws {
        let data = try WebPEncoder.encode(try image(width: 64, height: 48, alpha: 1))
        let source = try decoded(data)
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(frame.width == 64 && frame.height == 48)
    }

    @Test func keepsTransparency() throws {
        let data = try WebPEncoder.encode(try image(width: 32, height: 32, alpha: 0.5), quality: 0.8)
        let frame = try #require(CGImageSourceCreateImageAtIndex(try decoded(data), 0, nil))
        #expect(frame.alphaInfo != .none && frame.alphaInfo != .noneSkipLast && frame.alphaInfo != .noneSkipFirst)
    }

    @Test func encodesAnimationsWithFramesAndAnInfiniteLoop() throws {
        let frames = try [0.2, 0.6, 1].map { WebPEncoder.Frame(image: try image(width: 40, height: 30, alpha: 1, red: $0), duration: 0.1) }
        let source = try decoded(try WebPEncoder.encodeAnimation(frames))
        #expect(CGImageSourceGetCount(source) == 3)
        let container = try #require(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let webp = try #require(container[kCGImagePropertyWebPDictionary] as? [CFString: Any])
        #expect(webp[kCGImagePropertyWebPLoopCount] as? Int == 0)
    }

    @Test func writesWebPAsACaptureFileType() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).webp")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageEncoder.write(try image(width: 20, height: 20, alpha: 1), as: .WEBP, to: url)
        #expect(ImageEncoder.loadImage(at: url)?.width == 20)
    }
}
