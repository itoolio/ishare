import CoreGraphics
import Testing
@testable import ishareCore

struct EditorGridTests {
    @Test func snapsPointsToTheNearestLine() {
        let grid = EditorGrid(spacing: 20)
        #expect(grid.snap(CGPoint(x: 29, y: 31)) == CGPoint(x: 20, y: 40))
        #expect(grid.snap(-9) == 0)
    }

    @Test func snapsMovesByTheTopLeftCorner() {
        let grid = EditorGrid(spacing: 10)
        let offset = grid.offsetSnapping(CGRect(x: 3, y: 7, width: 50, height: 50), movedBy: CGVector(dx: 12, dy: 1))
        #expect(offset == CGVector(dx: 17, dy: 3))
    }

    @Test func hidesLinesThatWouldBeTooDense() {
        let grid = EditorGrid(spacing: 10)
        #expect(grid.lines(in: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 0.5).vertical.isEmpty)
        let lines = grid.lines(in: CGRect(x: 5, y: 0, width: 30, height: 20), scale: 1)
        #expect(lines.vertical == [10, 20, 30])
        #expect(lines.horizontal == [0, 10, 20])
    }

    @Test func picksReadableRulerSteps() {
        #expect(Ruler.majorStep(forScale: 1) == 100)
        #expect(Ruler.majorStep(forScale: 0.25) == 250)
        #expect(Ruler.majorStep(forScale: 8) == 10)
    }

    @Test func labelsOnlyMajorTicks() {
        let ticks = Ruler.ticks(from: 0, to: 200, scale: 1)
        #expect(ticks.filter(\.isMajor).map(\.label) == ["0", "100", "200"])
        #expect(ticks.count == 11)
        #expect(Ruler.ticks(from: 10, to: 5, scale: 1).isEmpty)
    }
}
