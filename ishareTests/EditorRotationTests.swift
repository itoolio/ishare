import CoreGraphics
import Foundation
import Testing
@testable import ishare

private func filledImage(width: Int = 400, height: Int = 300, gray: CGFloat = 1) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func stripes(width: Int = 400, height: Int = 300) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in stride(from: 0, to: width, by: 4) {
        context.setFillColor(CGColor(gray: x % 8 == 0 ? 0 : 1, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 4, height: height))
    }
    return context.makeImage()!
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return data
}

private func isRed(_ value: [UInt8]) -> Bool {
    value[0] > 200 && value[1] < 120 && value[2] < 120
}

@MainActor
struct EditorRotationTests {
    let bar = CGRect(x: 100, y: 140, width: 200, height: 20)

    func rotatedBar(_ shape: (CGRect) -> Annotation.Shape = { .rectangle($0) }) -> Annotation {
        var annotation = Annotation(shape: shape(bar), color: .red, lineWidth: 4, filled: true)
        annotation.rotation = .pi / 2
        return annotation
    }

    @Test func decodesExistingDocumentsWithoutRotation() throws {
        let json = #"{"shape":{"rectangle":{"_0":[[10,20],[30,40]]}},"color":{"red":1,"green":0,"blue":0,"alpha":1},"lineWidth":4}"#
        let annotation = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        #expect(annotation.rotation == 0)
        let plain = try JSONEncoder().encode(Annotation(shape: .rectangle(bar), color: .red, lineWidth: 2))
        #expect(!String(decoding: plain, as: UTF8.self).contains("rotation"))
        let rotated = rotatedBar()
        let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(rotated))
        #expect(decoded.rotation == rotated.rotation)
        let template = AnnotationTemplate(name: "Tilted", annotations: [rotated], frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(try AnnotationTemplate.decode(template.encoded()).annotations.first?.rotation == rotated.rotation)
    }

    @Test func boundsAndHitTestingFollowTheRotation() {
        let annotation = rotatedBar()
        #expect(abs(annotation.bounds.width - 20) < 0.001)
        #expect(abs(annotation.bounds.height - 200) < 0.001)
        #expect(annotation.hitTest(CGPoint(x: 200, y: 60), tolerance: 2))
        #expect(!annotation.hitTest(CGPoint(x: 120, y: 150), tolerance: 2))
        let ellipse = rotatedBar { .ellipse($0) }
        #expect(ellipse.hitTest(CGPoint(x: 200, y: 240), tolerance: 2))
    }

    @Test func calloutsKeepTheirTailWhenRotated() {
        var callout = Annotation(shape: .callout(CGPoint(x: 20, y: 20), CGRect(x: 100, y: 100, width: 120, height: 40), "Hi"), color: .red, lineWidth: 2)
        callout.rotation = .pi / 6
        #expect(callout.bounds.contains(CGPoint(x: 20, y: 20)))
        #expect(callout.hitTest(CGPoint(x: 90, y: 70), tolerance: 6))
        #expect(callout.localPoint(CGPoint(x: 160, y: 120)) == CGPoint(x: 160, y: 120))
    }

    @Test func resizingWorksInTheRotatedFrame() throws {
        let annotation = rotatedBar()
        let handle = try #require(annotation.editHandles.first { $0.0 == .resize(.right) })
        #expect(abs(handle.1.x - 200) < 0.001)
        #expect(abs(handle.1.y - 250) < 0.001)
        let resized = annotation.editing(.resize(.right), to: CGPoint(x: 210, y: 290))
        guard case let .rectangle(rect) = resized.shape else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(abs(rect.width - 240) < 0.001)
        #expect(abs(rect.height - 20) < 0.001)
        #expect(abs(resized.bounds.minY - 50) < 0.001)
        #expect(abs(resized.bounds.maxY - 290) < 0.001)
        #expect(resized.rotation == annotation.rotation)
    }

    @Test func movingKeepsTheRotation() {
        let moved = rotatedBar().offset(by: CGVector(dx: 10, dy: 0))
        #expect(moved.rotation == .pi / 2)
        #expect(abs(moved.bounds.midX - 210) < 0.001)
    }

    @Test func straightenTiltsBoxAnnotationsAndUndoes() throws {
        let document = EditorDocument(image: filledImage(), fileURL: nil)
        let rectangle = Annotation(shape: .rectangle(bar), color: .red, lineWidth: 4)
        let text = Annotation(shape: .text(CGPoint(x: 40, y: 40), "Hello"), color: .red, lineWidth: 2, fontSize: 20)
        let arrow = Annotation(shape: .arrow(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10)), color: .red, lineWidth: 4)
        document.add(rectangle)
        document.add(text)
        document.add(arrow)
        document.straightenAngle = 10
        document.applyStraighten()
        let radians = 10 * CGFloat.pi / 180
        let tilted = try #require(document.annotations.first { $0.id == rectangle.id })
        #expect(abs(tilted.rotation - radians) < 0.0001)
        guard case let .rectangle(rect) = tilted.shape else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(rect.size == bar.size)
        let tiltedText = try #require(document.annotations.first { $0.id == text.id })
        #expect(abs(tiltedText.rotation - radians) < 0.0001)
        #expect(try #require(document.annotations.first { $0.id == arrow.id }).rotation == 0)
        document.undo()
        #expect(document.annotations.allSatisfy { $0.rotation == 0 })
    }

    @Test func flipsMirrorTheRotation() {
        let mapping = CanvasMapping.orientation(.flipHorizontal, size: CGSize(width: 400, height: 300))
        var annotation = Annotation(shape: .rectangle(bar), color: .red, lineWidth: 4)
        annotation.rotation = 0.3
        #expect(annotation.mapped(by: mapping).rotation == -0.3)
        let quarter = CanvasMapping.orientation(.rotateRight, size: CGSize(width: 400, height: 300))
        #expect(annotation.mapped(by: quarter).rotation == 0.3)
    }

    @Test func rendersRotatedShapesInThePNG() throws {
        let document = EditorDocument(image: filledImage(), fileURL: nil)
        document.add(rotatedBar())
        let rendered = try #require(document.render())
        #expect(isRed(pixel(rendered, x: 200, y: 70)))
        #expect(!isRed(pixel(rendered, x: 120, y: 150)))
    }

    @Test func rotatedEffectsStayInsideTheirOutline() throws {
        var blur = Annotation(shape: .pixelate(CGRect(x: 100, y: 100, width: 200, height: 100)), color: .red, lineWidth: 4)
        blur.rotation = .pi / 4
        let source = stripes()
        let effected = AnnotationRenderer.applyingEffect(blur, to: source)
        let corner = blur.bounds.insetBy(dx: 4, dy: 4)
        #expect(pixel(effected, x: Int(corner.minX), y: Int(corner.minY)) == pixel(source, x: Int(corner.minX), y: Int(corner.minY)))
        var changed = 0
        for x in 180 ..< 220 where pixel(effected, x: x, y: 150) != pixel(source, x: x, y: 150) {
            changed += 1
        }
        #expect(changed > 10)
    }

    @Test func exportsRotationToSVGAndPDF() throws {
        let annotations = [rotatedBar(), rotatedBar { .spotlight($0) }]
        let input = VectorExportInput(base: filledImage(), annotations: annotations, crop: nil)
        let svg = SVGExporter.document(for: input)
        #expect(svg.contains(#"<g transform="rotate(90 200 150)">"#))
        #expect(svg.contains("fill-rule=\"evenodd\""))
        let pdf = try #require(PDFExporter.data(for: input))
        #expect(!pdf.isEmpty)
        let spotlightPath = try #require(AnnotationRenderer.spotlightPath(annotations[1]))
        #expect(abs(spotlightPath.boundingBoxOfPath.height - 200) < 0.5)
    }
}
