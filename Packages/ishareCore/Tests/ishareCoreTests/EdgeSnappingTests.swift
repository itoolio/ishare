import CoreGraphics
import Testing
@testable import ishareCore

struct EdgeSnappingTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func snapsToTheNearestEdgeWithinTheThreshold() {
        let edges = SnapEdges(rects: [CGRect(x: 100, y: 100, width: 300, height: 200)], within: bounds)
        let snapped = edges.snapping(CGPoint(x: 105, y: 297), threshold: 8)
        #expect(snapped.point == CGPoint(x: 100, y: 300))
        #expect(snapped.verticalEdge?.position == 100)
        #expect(snapped.horizontalEdge?.position == 300)
    }

    @Test func leavesPointsAwayFromEdgesAlone() {
        let edges = SnapEdges(rects: [CGRect(x: 100, y: 100, width: 300, height: 200)], within: bounds)
        let snapped = edges.snapping(CGPoint(x: 250, y: 200), threshold: 8)
        #expect(snapped.point == CGPoint(x: 250, y: 200))
        #expect(!snapped.isSnapped)
    }

    @Test func ignoresEdgesThatDoNotReachThePoint() {
        let edges = SnapEdges(rects: [CGRect(x: 100, y: 100, width: 300, height: 200)], within: bounds)
        let snapped = edges.snapping(CGPoint(x: 102, y: 600), threshold: 8)
        #expect(snapped.verticalEdge == nil)
    }

    @Test func prefersTheClosestOfSeveralEdges() {
        let edges = SnapEdges(
            rects: [CGRect(x: 100, y: 0, width: 200, height: 400), CGRect(x: 104, y: 0, width: 200, height: 400)], within: bounds)
        #expect(edges.snapping(CGPoint(x: 103, y: 50), threshold: 8).point.x == 104)
    }

    @Test func skipsTinyRectsAndScreenEdges() {
        let edges = SnapEdges(rects: [CGRect(x: 10, y: 10, width: 4, height: 4), bounds], within: bounds)
        #expect(edges.isEmpty)
    }

    @Test func convertsImagePixelsToFlippedViewPoints() {
        let rects = SnapEdges.flippedImageRects([CGRect(x: 20, y: 40, width: 100, height: 60)], scale: 2, viewHeight: 500)
        #expect(rects == [CGRect(x: 10, y: 450, width: 50, height: 30)])
    }

    @Test func convertsQuartzWindowFramesToScreenLocalViewRects() {
        let screen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let rects = SnapEdges.viewRects(fromQuartz: [CGRect(x: 1500, y: 100, width: 400, height: 300)], screenFrame: screen, primaryScreenHeight: 1080)
        #expect(rects == [CGRect(x: 60, y: 680, width: 400, height: 300)])
    }
}
