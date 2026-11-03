import CoreGraphics
import Testing
@testable import ishareCore

struct FaceRedactionLayoutTests {
    @Test func flipsVisionBoxesIntoTopLeftPixelsWithPadding() {
        let rects = FaceRedactionLayout.rects(forNormalized: [CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.25)], imageSize: CGSize(width: 400, height: 200), padding: 0.2)
        #expect(rects == [CGRect(x: 80, y: 40, width: 140, height: 70)])
    }

    @Test func clampsBoxesAtTheImageEdgeAndDropsSlivers() {
        let rects = FaceRedactionLayout.rects(
            forNormalized: [CGRect(x: 0.9, y: 0.9, width: 0.2, height: 0.2), CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001)],
            imageSize: CGSize(width: 100, height: 100), padding: 0)
        #expect(rects == [CGRect(x: 90, y: 0, width: 10, height: 10)])
    }
}
