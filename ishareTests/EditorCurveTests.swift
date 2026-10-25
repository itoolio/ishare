import CoreGraphics
import Foundation
import Testing
@testable import ishare

private func blankImage(width: Int = 400, height: Int = 300) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func near(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.01) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

struct EditorCurveTests {
    let arrow = Annotation(shape: .arrow(CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100)), color: .red, lineWidth: 4)
    let line = Annotation(shape: .line(CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100)), color: .red, lineWidth: 4)

    @Test func straightArrowsAndLinesOfferABendHandleAtTheMidpoint() {
        for annotation in [arrow, line] {
            let handle = annotation.editHandles.first { $0.0 == .control }
            #expect(handle.map { near($0.1, CGPoint(x: 100, y: 100)) } == true)
            #expect(annotation.editHandle(at: CGPoint(x: 101, y: 99), tolerance: 5) == .control)
        }
    }

    @Test func draggingTheBendHandleCurvesThroughThePointer() throws {
        let bentArrow = arrow.editing(.control, to: CGPoint(x: 100, y: 40))
        guard case let .curvedArrow(start, control, end) = bentArrow.shape else {
            Issue.record("Expected a curved arrow")
            return
        }
        #expect(near(ArrowGeometry.midpoint(from: start, control: control, to: end), CGPoint(x: 100, y: 40)))
        let bentLine = line.editing(.control, to: CGPoint(x: 100, y: 160))
        guard case let .curvedLine(lineStart, lineControl, lineEnd) = bentLine.shape else {
            Issue.record("Expected a curved line")
            return
        }
        #expect(near(ArrowGeometry.midpoint(from: lineStart, control: lineControl, to: lineEnd), CGPoint(x: 100, y: 160)))
        let moved = bentLine.editing(.end, to: CGPoint(x: 300, y: 100))
        guard case .curvedLine = moved.shape else {
            Issue.record("Moving an end keeps the line curved")
            return
        }
        #expect(near(try #require(moved.editHandles.first { $0.0 == .control }).1, CGPoint(x: 100, y: 160)))
    }

    @Test func hitTestingFollowsTheCurve() {
        let bent = line.editing(.control, to: CGPoint(x: 100, y: 40))
        #expect(bent.hitTest(CGPoint(x: 100, y: 42), tolerance: 4))
        #expect(!bent.hitTest(CGPoint(x: 100, y: 100), tolerance: 4))
        #expect(bent.bounds.minY < 40)
        #expect(bent.bounds.minY > 30)
    }

    @Test func straighteningRestoresTheStraightShape() {
        #expect(arrow.editing(.control, to: CGPoint(x: 100, y: 40)).straightened().shape == arrow.shape)
        #expect(line.editing(.control, to: CGPoint(x: 100, y: 40)).straightened().shape == line.shape)
        #expect(arrow.straightened() == arrow)
        #expect(line.editing(.control, to: CGPoint(x: 100, y: 40)).isCurved)
    }

    @Test func arrowheadsFollowTheEndTangent() {
        let angles = ArrowGeometry.headAngles(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 100, y: 0), end: CGPoint(x: 100, y: 100))
        #expect(abs(angles.end - .pi / 2) < 0.0001)
        #expect(abs(cos(angles.start) + 1) < 0.0001)
        let straight = ArrowGeometry.headAngles(start: .zero, control: nil, end: CGPoint(x: 10, y: 0))
        #expect(straight.end == 0)
        #expect(abs(cos(straight.start) + 1) < 0.0001)
    }

    @Test(arguments: ArrowHead.allCases)
    @MainActor
    func rendersEveryArrowStyleOnACurve(head: ArrowHead) throws {
        let document = EditorDocument(image: blankImage(), fileURL: nil)
        var curved = Annotation(shape: .curvedArrow(CGPoint(x: 40, y: 250), CGPoint(x: 200, y: 0), CGPoint(x: 360, y: 250)), color: .black, lineWidth: 6, arrowHead: head)
        curved.doubleHeaded = true
        curved.dashed = true
        document.add(curved)
        let rendered = try #require(document.render())
        #expect(rendered.width == 400)
        let svg = SVGExporter.document(for: VectorExportInput(base: document.adjustedBase, annotations: document.annotations, crop: nil))
        #expect(svg.contains(" Q"))
        #expect(svg.contains("stroke-dasharray"))
        #expect(PDFExporter.data(for: VectorExportInput(base: document.adjustedBase, annotations: document.annotations, crop: nil)) != nil)
    }

    @Test func exportsCurvedLinesAsPaths() {
        let bent = line.editing(.control, to: CGPoint(x: 100, y: 40))
        let elements = SVGExporter.elements(for: bent, source: blankImage())
        #expect(elements.count == 1)
        #expect(elements[0].hasPrefix("<path d=\"M0 100 Q100 -20 200 100\""))
    }

    @Test func curvedLinesSurviveCodingAndMapping() throws {
        let bent = line.editing(.control, to: CGPoint(x: 100, y: 40))
        let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(bent))
        #expect(decoded.shape == bent.shape)
        let moved = bent.offset(by: CGVector(dx: 10, dy: 5))
        #expect(moved.editHandles.first { $0.0 == .control }.map { near($0.1, CGPoint(x: 110, y: 45)) } == true)
        #expect(bent.tool == .line)
        #expect(bent.supportsDash)
    }
}
