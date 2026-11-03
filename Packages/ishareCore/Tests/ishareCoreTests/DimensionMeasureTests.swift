import CoreGraphics
import Testing
@testable import ishareCore

struct DimensionMeasureTests {
    @Test func labelsPixelsAndPointsForAxisAlignedLines() {
        #expect(DimensionMeasure.label(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 240, y: 0), pointScale: 2) == "240 px · 120 pt")
        #expect(DimensionMeasure.label(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 50), pointScale: 1) == "50 px")
    }

    @Test func addsTheAngleForDiagonalLines() {
        #expect(DimensionMeasure.label(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 100, y: 0), pointScale: 1) == "141 px · 45°")
        #expect(DimensionMeasure.angleDegrees(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100)) == 315)
    }

    @Test func ticksArePerpendicularAtBothEnds() {
        let ticks = DimensionMeasure.ticks(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 0), length: 8)
        #expect(ticks.count == 2)
        #expect(ticks[0].0 == CGPoint(x: 0, y: -4))
        #expect(ticks[1].1 == CGPoint(x: 10, y: 4))
        #expect(DimensionMeasure.ticks(from: .zero, to: .zero, length: 8).isEmpty)
    }

    @Test func selectionDimensionsRunAlongTheTopAndLeftEdges() {
        let lines = DimensionMeasure.selectionDimensions(of: CGRect(x: 10, y: 20, width: 30, height: 40), offset: 5)
        #expect(lines[0].0 == CGPoint(x: 10, y: 15))
        #expect(lines[0].1 == CGPoint(x: 40, y: 15))
        #expect(lines[1].0 == CGPoint(x: 5, y: 20))
        #expect(lines[1].1 == CGPoint(x: 5, y: 60))
    }
}
