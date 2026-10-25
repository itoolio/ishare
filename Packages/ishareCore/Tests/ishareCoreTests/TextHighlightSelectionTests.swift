import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct TextHighlightSelectionTests {
    let first = TextHighlightLine(
        frame: CGRect(x: 10, y: 10, width: 300, height: 20),
        words: [CGRect(x: 10, y: 10, width: 80, height: 20), CGRect(x: 100, y: 10, width: 90, height: 20), CGRect(x: 200, y: 10, width: 110, height: 20)])
    let second = TextHighlightLine(
        frame: CGRect(x: 10, y: 40, width: 200, height: 20),
        words: [CGRect(x: 10, y: 40, width: 60, height: 20), CGRect(x: 80, y: 40, width: 60, height: 20), CGRect(x: 150, y: 40, width: 60, height: 20)])
    let third = TextHighlightLine(
        frame: CGRect(x: 10, y: 70, width: 250, height: 20),
        words: [CGRect(x: 10, y: 70, width: 120, height: 20), CGRect(x: 140, y: 70, width: 120, height: 20)])

    var lines: [TextHighlightLine] { [third, first, second] }

    @Test func convertsVisionCoordinatesToTheTopLeft() {
        let line = TextHighlightLine(
            normalizedFrame: CGRect(x: 0.125, y: 0.75, width: 0.5, height: 0.125), normalizedWords: [CGRect(x: 0.125, y: 0.75, width: 0.25, height: 0.125)],
            imageSize: CGSize(width: 1000, height: 500))
        #expect(line.frame == CGRect(x: 125, y: 62.5, width: 500, height: 62.5))
        #expect(line.words == [CGRect(x: 125, y: 62.5, width: 250, height: 62.5)])
    }

    @Test func ordersLinesTopToBottomThenLeftToRight() {
        let right = TextHighlightLine(frame: CGRect(x: 400, y: 12, width: 50, height: 18))
        let ordered = TextHighlightSelection.readingOrder(lines + [right])
        #expect(ordered.map(\.frame.minY) == [10, 12, 40, 70])
        #expect(ordered[1] == right)
    }

    @Test func snapsASingleLineDragToTheCoveredWords() {
        let rects = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 120, y: 20), to: CGPoint(x: 230, y: 22), tolerance: 4)
        #expect(rects == [CGRect(x: 100, y: 10, width: 210, height: 20)])
    }

    @Test func dragsBackwardsSelectTheSameWords() {
        let forward = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 120, y: 20), to: CGPoint(x: 230, y: 22), tolerance: 4)
        let backward = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 230, y: 22), to: CGPoint(x: 120, y: 20), tolerance: 4)
        #expect(forward == backward)
    }

    @Test func multiLineSelectionsProduceOneRectPerLine() {
        let rects = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 150, y: 15), to: CGPoint(x: 50, y: 80), tolerance: 4)
        #expect(
            rects == [
                CGRect(x: 100, y: 10, width: 210, height: 20),
                CGRect(x: 10, y: 40, width: 200, height: 20),
                CGRect(x: 10, y: 70, width: 120, height: 20),
            ])
    }

    @Test func pointsBetweenWordsSnapToTheNearestWord() {
        let caret = TextHighlightSelection.caret(at: CGPoint(x: 96, y: 20), in: TextHighlightSelection.readingOrder(lines), tolerance: 2)
        #expect(caret == TextHighlightSelection.Caret(line: 0, word: 1))
    }

    @Test func dragsEndingOutsideTheTextExtendToTheNearestLine() {
        let rects = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 160, y: 50), to: CGPoint(x: 500, y: 300), tolerance: 4)
        #expect(rects == [CGRect(x: 150, y: 40, width: 60, height: 20), CGRect(x: 10, y: 70, width: 250, height: 20)])
    }

    @Test func dragsAroundTextSelectTheCoveredLines() {
        let rects = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 0, y: 35), to: CGPoint(x: 95, y: 100), tolerance: 2)
        #expect(rects == [CGRect(x: 10, y: 40, width: 130, height: 20), CGRect(x: 10, y: 70, width: 120, height: 20)])
    }

    @Test func dragsAwayFromTextSelectNothing() {
        #expect(TextHighlightSelection.rects(for: lines, from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), tolerance: 4).isEmpty)
        #expect(TextHighlightSelection.rects(for: [], from: .zero, to: CGPoint(x: 10, y: 10), tolerance: 4).isEmpty)
    }

    @Test func linesWithoutWordsHighlightTheWholeLine() {
        let bare = TextHighlightLine(frame: CGRect(x: 0, y: 0, width: 100, height: 10))
        #expect(TextHighlightSelection.rects(for: [bare], from: CGPoint(x: 20, y: 5), to: CGPoint(x: 30, y: 5), tolerance: 2) == [bare.frame])
    }

    @Test func padsTheResult() {
        let rects = TextHighlightSelection.rects(for: lines, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 30, y: 20), tolerance: 4, padding: 2)
        #expect(rects == [CGRect(x: 8, y: 8, width: 84, height: 24)])
    }
}
