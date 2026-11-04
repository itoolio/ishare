import AppKit
import ishareCore
import Testing
@testable import ishare

@MainActor
@Suite(.serialized)
struct WebPageCaptureTests {
    static let page = """
        <html><body style="margin:0;background:#fff"><div style="height:2400px"></div>
        <div id="cookie-banner" style="position:fixed;left:0;right:0;bottom:0;height:120px;background:#f00">
        <button onclick="document.getElementById('cookie-banner').remove()">Reject all</button></div></body></html>
        """

    func pageURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "web-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "index.html")
        try Self.page.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func bottomIsRed(_ image: CGImage) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 10)?.usingColorSpace(.sRGB) else { return false }
        return color.redComponent > 0.8 && color.greenComponent < 0.3
    }

    @Test func dismissesCookieBannersBeforeCapturing() async throws {
        let url = try pageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let kept = try await WebPageCapture.capture(url, request: WebPageCaptureRequest(address: url.absoluteString, width: 800, dismissesCookieBanners: false))
        #expect(bottomIsRed(kept))
        let dismissed = try await WebPageCapture.capture(url, request: WebPageCaptureRequest(address: url.absoluteString, width: 800))
        #expect(!bottomIsRed(dismissed))
        #expect(CGFloat(dismissed.height) / CGFloat(dismissed.width) > 2.5)
    }

    @Test func savesPagesAsPDF() async throws {
        let url = try pageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let data = try await WebPageCapture.pdf(url, request: WebPageCaptureRequest(address: url.absoluteString, width: 800, format: .pdf))
        #expect(data.prefix(4) == Data("%PDF".utf8))
    }
}
