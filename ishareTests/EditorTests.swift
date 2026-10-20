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

@MainActor
struct EditorToolTests {
    func checkerboard(width: Int = 200, height: Int = 100) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return context.makeImage()!
    }

    @Test func rotatesAndFlipsAsUndoableSteps() throws {
        let document = EditorDocument(image: checkerboard(), fileURL: nil)
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: .blue, lineWidth: 2))
        document.apply(.rotateRight)
        #expect(document.imageSize == CGSize(width: 100, height: 200))
        #expect(document.annotations.isEmpty)
        document.apply(.flipHorizontal)
        #expect(document.imageSize == CGSize(width: 100, height: 200))
        document.undo()
        document.undo()
        #expect(document.imageSize == CGSize(width: 200, height: 100))
        #expect(document.annotations.count == 1)
    }

    @Test func smartEraserFillsWithTheSurroundingColor() throws {
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 20, height: 20))
        let erased = ImageProcessing.erase(context.makeImage()!, region: CGRect(x: 35, y: 35, width: 30, height: 30))
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        probe.draw(erased, in: CGRect(x: -50, y: -50, width: 100, height: 100))
        #expect(pixel[0] < 30)
        #expect(pixel[2] > 220)
    }

    @Test func createsShareXStyleAnnotations() throws {
        let document = EditorDocument(image: checkerboard(), fileURL: nil)
        document.filled = true
        let filled = try #require(document.makeAnnotation(tool: .rectangle, from: .zero, to: CGPoint(x: 20, y: 20), points: []))
        #expect(filled.filled)
        let arrow = try #require(document.makeAnnotation(tool: .arrow, from: .zero, to: CGPoint(x: 20, y: 20), points: []))
        #expect(!arrow.filled)
        let magnify = try #require(document.makeAnnotation(tool: .magnify, from: .zero, to: CGPoint(x: 40, y: 10), points: []))
        #expect(magnify.bounds.width == magnify.bounds.height)
        let callout = try #require(document.makeAnnotation(tool: .callout, from: .zero, to: CGPoint(x: 50, y: 40), points: []))
        #expect(document.isSubstantial(callout))
        document.add(callout)
        document.editingText = .init(origin: .zero, text: "Hi", replacing: callout.id)
        document.commitText()
        guard case let .callout(_, _, text) = document.annotations.first?.shape else {
            Issue.record("Expected a callout")
            return
        }
        #expect(text == "Hi")
    }

    @Test func rendersEveryToolWithoutChangingTheCanvasSize() throws {
        let document = EditorDocument(image: checkerboard(), fileURL: nil)
        let shapes: [Annotation.Shape] = [
            .spotlight(CGRect(x: 10, y: 10, width: 50, height: 50)),
            .magnify(CGRect(x: 120, y: 10, width: 60, height: 60)),
            .callout(CGPoint(x: 5, y: 95), CGRect(x: 20, y: 60, width: 80, height: 30), "Note"),
            .cursor(CGPoint(x: 150, y: 50)),
            .eraser(CGRect(x: 90, y: 40, width: 20, height: 20)),
            .text(CGPoint(x: 10, y: 70), "Label"),
        ]
        for shape in shapes {
            document.add(Annotation(shape: shape, color: .yellow, lineWidth: 3, fontSize: 14, textBackground: true))
        }
        let rendered = try #require(document.render())
        #expect(rendered.width == 200)
        #expect(rendered.height == 100)
    }

    @Test func magnifiesTheUnderlyingImage() throws {
        let document = EditorDocument(image: checkerboard(), fileURL: nil)
        document.add(Annotation(shape: .magnify(CGRect(x: 90, y: 0, width: 100, height: 100)), color: .white, lineWidth: 1))
        let rendered = try #require(document.render())
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        probe.draw(rendered, in: CGRect(x: -96, y: -50, width: 200, height: 100))
        #expect(pixel[1] > 200, "Expected magnified white content but got \(pixel)")
    }

    @Test func pointsCalloutTailsAwayFromTheBubble() {
        let path = AnnotationRenderer.calloutPath(tail: CGPoint(x: 0, y: 0), rect: CGRect(x: 50, y: 50, width: 100, height: 40), radius: 8)
        #expect(path.boundingBox.minX <= 0.5)
        #expect(path.boundingBox.maxX >= 150)
    }
}
