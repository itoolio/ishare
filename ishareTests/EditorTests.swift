import CoreGraphics
import Foundation
import Testing
@testable import ishare

@MainActor
struct EditorDocumentTests {
    func image(width: Int = 400, height: Int = 300, gray: CGFloat = 1) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return data
    }

    @Test func undoesAndRedoesAnnotations() {
        let document = EditorDocument(image: image(), fileURL: nil)
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)), color: .red, lineWidth: 4))
        document.add(Annotation(shape: .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)), color: .blue, lineWidth: 4))
        #expect(document.annotations.count == 2)
        document.undo()
        #expect(document.annotations.count == 1)
        document.redo()
        #expect(document.annotations.count == 2)
        document.undo()
        document.add(Annotation(shape: .line(.zero, CGPoint(x: 5, y: 5)), color: .green, lineWidth: 2))
        #expect(!document.canRedo)
    }

    @Test func numbersStepsSequentially() {
        let document = EditorDocument(image: image(), fileURL: nil)
        #expect(document.nextStepNumber == 1)
        document.add(Annotation(shape: .step(CGPoint(x: 20, y: 20), 1), color: .red, lineWidth: 4))
        document.add(Annotation(shape: .step(CGPoint(x: 60, y: 20), 2), color: .red, lineWidth: 4))
        #expect(document.nextStepNumber == 3)
    }

    @Test func hitTestsAndMovesAnnotations() throws {
        let document = EditorDocument(image: image(), fileURL: nil)
        let annotation = Annotation(shape: .line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)), color: .red, lineWidth: 4)
        document.add(annotation)
        #expect(document.annotation(at: CGPoint(x: 50, y: 3))?.id == annotation.id)
        #expect(document.annotation(at: CGPoint(x: 50, y: 80)) == nil)
        document.move(annotation.id, by: CGVector(dx: 0, dy: 80))
        #expect(document.annotation(at: CGPoint(x: 50, y: 80))?.id == annotation.id)
    }

    @Test func cropsTheRenderedImage() throws {
        let document = EditorDocument(image: image(), fileURL: nil)
        document.applyCrop(CGRect(x: 50, y: 40, width: 120, height: 90))
        let rendered = try #require(document.render())
        #expect(rendered.width == 120)
        #expect(rendered.height == 90)
        document.undo()
        #expect(document.crop == nil)
    }

    @Test func ignoresTinyCrops() {
        let document = EditorDocument(image: image(), fileURL: nil)
        document.applyCrop(CGRect(x: 5, y: 5, width: 1, height: 1))
        #expect(document.crop == nil)
    }

    @Test func drawsFilledRectanglesInTopLeftCoordinates() throws {
        let document = EditorDocument(image: image(gray: 1), fileURL: nil)
        document.add(Annotation(shape: .highlight(CGRect(x: 0, y: 0, width: 100, height: 50)), color: .black, lineWidth: 1))
        let rendered = try #require(document.render())
        #expect(pixel(rendered, x: 10, y: 10)[0] < 255)
        #expect(pixel(rendered, x: 10, y: 250)[0] == 255)
    }

    @Test func pixelatesOnlyTheSelectedRegion() throws {
        let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0 ..< 200 {
            context.setFillColor(CGColor(gray: x % 2 == 0 ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 200))
        }
        let base = context.makeImage()!
        let output = ImageProcessing.pixelate(base, region: CGRect(x: 0, y: 0, width: 100, height: 100), blockSize: 20)
        #expect(output.width == 200)
        let inside = pixel(output, x: 10, y: 10)[0]
        #expect(inside > 40 && inside < 215)
        #expect(pixel(output, x: 150, y: 150)[0] == pixel(base, x: 150, y: 150)[0])
    }

    @Test func commitsTextAnnotations() {
        let document = EditorDocument(image: image(), fileURL: nil)
        document.beginText(at: CGPoint(x: 10, y: 10))
        document.editingText?.text = "  Hello  "
        document.commitText()
        guard case let .text(_, string) = document.annotations.first?.shape else {
            Issue.record("Expected a text annotation")
            return
        }
        #expect(string == "Hello")
        document.beginText(at: .zero)
        document.commitText()
        #expect(document.annotations.count == 1)
    }

    @Test func measuresAnnotationBounds() {
        let annotation = Annotation(shape: .pen([CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 5)]), color: .red, lineWidth: 2)
        #expect(annotation.bounds == CGRect(x: 8, y: 3, width: 34, height: 19))
        #expect(Annotation.distance(from: CGPoint(x: 5, y: 5), toSegment: .zero, CGPoint(x: 10, y: 0)) == 5)
    }
}
