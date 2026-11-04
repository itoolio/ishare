import CoreGraphics
import Testing
@testable import ishareCore

struct WebPageCapturePlanTests {
    @Test func normalizesTypedAddresses() {
        #expect(WebPageCapturePlan.normalizedURL(from: " example.com/docs ")?.absoluteString == "https://example.com/docs")
        #expect(WebPageCapturePlan.normalizedURL(from: "http://localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(WebPageCapturePlan.normalizedURL(from: "file:///etc/passwd") == nil)
        #expect(WebPageCapturePlan.normalizedURL(from: "not a url") == nil)
        #expect(WebPageCapturePlan.normalizedURL(from: "javascript:alert(1)") == nil)
    }

    @Test func splitsTallPagesIntoChunksAndCapsTheHeight() {
        let chunks = WebPageCapturePlan.chunks(height: 9000, chunkHeight: 4000)
        #expect(chunks.map(\.height) == [4000, 4000, 1000])
        #expect(chunks.map(\.minY) == [0, 4000, 8000])
        #expect(WebPageCapturePlan.cappedHeight(100_000) == WebPageCapturePlan.maximumHeight)
    }

    @Test func scrollsThroughThePageAndBackToTheTop() {
        #expect(WebPageCapturePlan.scrollStops(height: 2500, viewport: 1000) == [0, 1000, 2000, 0])
    }

    @Test func widthPresetsMatchCommonViewports() {
        #expect(WebPageWidth.allCases.map(\.points) == [1440, 834, 390])
    }
}

struct WebPageWidthParsingTests {
    @Test func acceptsPresetsAndCustomWidths() {
        #expect(WebPageCapturePlan.width(from: nil) == 1440)
        #expect(WebPageCapturePlan.width(from: "mobile") == 390)
        #expect(WebPageCapturePlan.width(from: "1024") == 1024)
        #expect(WebPageCapturePlan.width(from: "1280px") == 1280)
        #expect(WebPageCapturePlan.width(from: "100") == 320)
        #expect(WebPageCapturePlan.width(from: "99999") == 3840)
        #expect(WebPageCapturePlan.width(from: "wide") == nil)
    }
}
