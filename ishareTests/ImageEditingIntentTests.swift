import AppIntents
import CoreGraphics
import Foundation
import Testing
@testable import ishare

struct ImageEditingIntentTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try ImageEncoder.write(try #require(context.makeImage()), as: .PNG, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    @Test func loadsIntentFilesAndWritesPNGResults() throws {
        let file = IntentFile(data: try pngData(width: 30, height: 20), filename: "shot.png", type: .png)
        let (image, staged) = try ImageIntentIO.load(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        #expect(image.width == 30 && image.height == 20)
        let output = try ImageIntentIO.output(image, named: ImageIntentIO.baseName(of: file) + "-trimmed")
        #expect(output.filename == "shot-trimmed.png")
        #expect(output.type == .png)
        let written = try #require(output.fileURL)
        #expect(ImageEncoder.loadImage(at: written)?.width == 30)
    }

    @Test func choicesMapToTheEditorTypes() {
        #expect(DeviceFrameChoice.phone.frame == .phone)
        #expect(CombineLayoutChoice.grid.layout == .grid)
    }
}
