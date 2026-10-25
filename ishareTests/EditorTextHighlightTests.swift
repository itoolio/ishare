import CoreGraphics
import Foundation
import ishareCore
import Testing
@testable import ishare

private func whiteImage(width: Int = 400, height: Int = 300) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func sample(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return data
}

@MainActor
struct EditorTextHighlightTests {
    let lines = [
        TextHighlightLine(
            frame: CGRect(x: 20, y: 20, width: 300, height: 30),
            words: [CGRect(x: 20, y: 20, width: 90, height: 30), CGRect(x: 120, y: 20, width: 200, height: 30)]),
        TextHighlightLine(
            frame: CGRect(x: 20, y: 70, width: 200, height: 30),
            words: [CGRect(x: 20, y: 70, width: 80, height: 30), CGRect(x: 110, y: 70, width: 110, height: 30)]),
    ]

    func document() -> EditorDocument {
        let document = EditorDocument(image: whiteImage(), fileURL: nil)
        document.select(tool: .highlight)
        document.setHighlightTarget(.text)
        document.useRecognizedText(lines)
        return document
    }

    @Test func snapsDragsToRecognizedWordsOnePerLine() throws {
        let document = document()
        let highlights = document.textHighlights(from: CGPoint(x: 150, y: 35), to: CGPoint(x: 50, y: 85), tolerance: 4)
        #expect(highlights.count == 2)
        let rects = highlights.compactMap { annotation -> CGRect? in
            if case let .highlight(rect) = annotation.shape { return rect }
            return nil
        }
        #expect(rects[0] == CGRect(x: 118, y: 18, width: 204, height: 34))
        #expect(rects[1] == CGRect(x: 18, y: 68, width: 84, height: 34))
        document.add(contentsOf: highlights)
        #expect(document.annotations.count == 2)
        document.undo()
        #expect(document.annotations.isEmpty)
    }

    @Test func areaModeAndOtherToolsDoNotSnap() {
        let document = document()
        document.setHighlightTarget(.area)
        #expect(document.textHighlights(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 60, y: 30), tolerance: 4).isEmpty)
        document.setHighlightTarget(.text)
        #expect(!document.smartShapesActive)
        document.select(tool: .rectangle)
        #expect(!document.textHighlightActive)
    }

    @Test func appliesTheChosenStyle() throws {
        let document = document()
        document.setHighlightStyle(.underline)
        let highlight = try #require(document.textHighlights(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 60, y: 30), tolerance: 4).first)
        #expect(highlight.highlightStyle == .underline)
        let drawn = try #require(document.makeAnnotation(tool: .highlight, from: .zero, to: CGPoint(x: 50, y: 50), points: []))
        #expect(drawn.highlightStyle == .underline)
        document.add(drawn)
        document.selectedID = drawn.id
        document.setHighlightStyle(.strikethrough)
        #expect(document.annotations.first?.highlightStyle == .strikethrough)
    }

    @Test func rendersUnderlinesAndStrikethroughs() throws {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 50)
        let document = EditorDocument(image: whiteImage(), fileURL: nil)
        var underline = Annotation(shape: .highlight(rect), color: .red, lineWidth: 4)
        underline.highlightStyle = .underline
        document.add(underline)
        let rendered = try #require(document.render())
        let bottom = sample(rendered, x: 200, y: 147)
        #expect(bottom[0] > 200 && bottom[1] < 120)
        #expect(sample(rendered, x: 200, y: 120) == [255, 255, 255, 255])
        var strike = underline
        strike.highlightStyle = .strikethrough
        #expect(HighlightStyle.strikethrough.lineRect(in: rect) == CGRect(x: 100, y: 122, width: 200, height: 6))
        let svg = SVGExporter.elements(for: strike, source: whiteImage())
        #expect(svg == [#"<rect x="100" y="122" width="200" height="6" fill="rgb(255,59,48)"/>"#])
        #expect(HighlightStyle.marker.lineRect(in: rect) == nil)
        let pdf = PDFExporter.data(for: VectorExportInput(base: whiteImage(), annotations: [underline, strike], crop: nil))
        #expect(pdf?.isEmpty == false)
    }

    @Test func highlightStylesSurviveCoding() throws {
        var annotation = Annotation(shape: .highlight(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, lineWidth: 2)
        #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(annotation)).highlightStyle == .marker)
        annotation.highlightStyle = .strikethrough
        #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(annotation)).highlightStyle == .strikethrough)
    }

    @Test func convertsRecognizedLinesIntoImageCoordinates() {
        let recognized = RecognizedLine(
            text: "Hi there", boundingBox: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25),
            words: [RecognizedWord(range: NSRange(location: 0, length: 2), boundingBox: CGRect(x: 0.25, y: 0.5, width: 0.125, height: 0.25))])
        let converted = TextHighlighting.lines(from: [recognized], imageSize: CGSize(width: 400, height: 200))
        #expect(converted == [TextHighlightLine(frame: CGRect(x: 100, y: 50, width: 200, height: 50), words: [CGRect(x: 100, y: 50, width: 50, height: 50)])])
    }

    @Test func recognizesTextOncePerImage() async throws {
        let image = TextImages.render([("Highlight this line", CGPoint(x: 30, y: 40)), ("and the next one", CGPoint(x: 30, y: 160))])
        let document = EditorDocument(image: image, fileURL: nil)
        document.select(tool: .highlight)
        document.highlightTarget = .text
        await document.recognizeText()
        #expect(document.textLines.count == 2)
        #expect(document.textLines.allSatisfy { !$0.words.isEmpty })
        let first = try #require(document.textLines.first { $0.frame.minY < 100 })
        let highlights = document.textHighlights(
            from: CGPoint(x: first.frame.minX + 2, y: first.frame.midY), to: CGPoint(x: first.frame.maxX - 2, y: first.frame.midY), tolerance: 4)
        #expect(highlights.count == 1)
        let lines = document.textLines
        document.prepareTextLinesIfNeeded()
        #expect(document.textLines == lines)
    }
}
