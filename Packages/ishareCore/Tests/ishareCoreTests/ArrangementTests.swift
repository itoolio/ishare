import CoreGraphics
import Testing
@testable import ishareCore

struct ArrangementTests {
    let rects = [CGRect(x: 10, y: 10, width: 20, height: 20), CGRect(x: 50, y: 40, width: 40, height: 10), CGRect(x: 30, y: 100, width: 10, height: 30)]

    @Test func alignsToTheSharedEdgesOfTheSelection() {
        #expect(Arrangement.offsets(aligning: rects, to: .left) == [.zero, CGVector(dx: -40, dy: 0), CGVector(dx: -20, dy: 0)])
        #expect(Arrangement.offsets(aligning: rects, to: .right) == [CGVector(dx: 60, dy: 0), .zero, CGVector(dx: 50, dy: 0)])
        #expect(Arrangement.offsets(aligning: rects, to: .bottom) == [CGVector(dx: 0, dy: 100), CGVector(dx: 0, dy: 80), .zero])
        #expect(Arrangement.offsets(aligning: rects, to: .horizontalCenter)[1] == CGVector(dx: -20, dy: 0))
    }

    @Test func alignsASingleItemToTheImage() {
        let offsets = Arrangement.offsets(aligning: [CGRect(x: 10, y: 10, width: 20, height: 20)], to: .verticalCenter, within: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(offsets == [CGVector(dx: 0, dy: 30)])
    }

    @Test func distributesWithEqualGaps() {
        let row = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 80, y: 0, width: 20, height: 10), CGRect(x: 15, y: 0, width: 10, height: 10)]
        let offsets = Arrangement.offsets(distributing: row, along: .horizontal)
        let moved = zip(row, offsets).map { $0.offsetBy(dx: $1.dx, dy: $1.dy) }
        #expect(moved[0].minX == 0)
        #expect(moved[2].minX == 40)
        #expect(moved[1].minX == 80)
    }

    @Test func leavesTwoItemsWhereTheyAre() {
        #expect(Arrangement.offsets(distributing: Array(rects.prefix(2)), along: .vertical) == [.zero, .zero])
    }
}
