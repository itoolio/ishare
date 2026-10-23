import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ishare

@MainActor
struct ClipboardTests {
    func capture(as fileType: FileType) throws -> URL {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let url = FileManager.default.temporaryDirectory.appending(path: "clipboard-\(UUID().uuidString).\(fileType.rawValue)")
        try ImageEncoder.write(context.makeImage()!, as: fileType, to: url)
        return url
    }

    func copied(_ fileURL: URL) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("ishare.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([PostCapture.pasteboardItem(forImageAt: fileURL)])
        return pasteboard
    }

    @Test func imageCopyKeepsTheFileURLAndAddsPNGPixels() throws {
        let url = try capture(as: .PNG)
        let pasteboard = copied(url)
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: url)
        }
        #expect(pasteboard.string(forType: .fileURL) == url.absoluteString)
        #expect(try pasteboard.data(forType: .png) == Data(contentsOf: url))
    }

    @Test func nonPNGCapturesAreTranscodedToPNG() throws {
        let url = try capture(as: .JPG)
        let pasteboard = copied(url)
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: url)
        }
        let png = try #require(pasteboard.data(forType: .png))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }
}
