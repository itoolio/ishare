import CoreGraphics
import Testing
@testable import ishareCore

struct ShapeLibraryTests {
    private let rect = CGRect(x: 10, y: 20, width: 100, height: 60)

    @Test(arguments: LibraryShape.allCases)
    func pathsStayInsideTheirRect(_ shape: LibraryShape) {
        let bounds = shape.path(in: rect).boundingBoxOfPath
        #expect(!bounds.isEmpty)
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds))
    }

    @Test func textAreasSitInsideTextShapesOnly() {
        for shape in LibraryShape.allCases {
            let area = shape.textRect(in: rect)
            #expect(shape.holdsText == !area.isNull)
            if !area.isNull {
                #expect(rect.contains(area))
            }
        }
    }

    @Test func bracketsOpenTowardsTheirContent() {
        let left = LibraryShape.bracketLeft.path(in: rect)
        #expect(left.currentPoint == CGPoint(x: rect.maxX, y: rect.maxY))
        let right = LibraryShape.bracketRight.path(in: rect)
        #expect(right.currentPoint == CGPoint(x: rect.minX, y: rect.maxY))
    }

    @Test func convertsPathsToSVGData() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 5))
        path.addQuadCurve(to: CGPoint(x: 20, y: 0), control: CGPoint(x: 15, y: 10))
        path.closeSubpath()
        #expect(LibraryShape.svgPathData(path) { String(Int($0)) } == "M0 0 L10 5 Q15 10 20 0 Z")
    }
}
