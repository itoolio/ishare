import CoreGraphics
import Foundation

public struct TextHighlightLine: Hashable, Sendable {
    public var frame: CGRect
    public var words: [CGRect]

    public init(frame: CGRect, words: [CGRect] = []) {
        self.frame = frame.standardized
        self.words = words.map(\.standardized).sorted { $0.minX < $1.minX }
    }

    public init(normalizedFrame: CGRect, normalizedWords: [CGRect] = [], imageSize: CGSize) {
        self.init(
            frame: Self.topLeftRect(fromNormalized: normalizedFrame, imageSize: imageSize),
            words: normalizedWords.map { Self.topLeftRect(fromNormalized: $0, imageSize: imageSize) })
    }

    public static func topLeftRect(fromNormalized rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(x: rect.minX * imageSize.width, y: (1 - rect.maxY) * imageSize.height, width: rect.width * imageSize.width, height: rect.height * imageSize.height)
    }
}

public enum TextHighlightSelection {
    public struct Caret: Comparable, Hashable, Sendable {
        public var line: Int
        public var word: Int

        public init(line: Int, word: Int) {
            self.line = line
            self.word = word
        }

        public static func < (lhs: Caret, rhs: Caret) -> Bool {
            (lhs.line, lhs.word) < (rhs.line, rhs.word)
        }
    }

    public static func readingOrder(_ lines: [TextHighlightLine]) -> [TextHighlightLine] {
        var rows: [[TextHighlightLine]] = []
        for line in lines.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let last = rows.indices.last, rows[last].contains(where: { sharesRow($0.frame, line.frame) }) {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { row in row.sorted { $0.frame.minX < $1.frame.minX } }
    }

    public static func sharesRow(_ first: CGRect, _ second: CGRect) -> Bool {
        let overlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
        return overlap > min(first.height, second.height) * 0.5
    }

    public static func caret(at point: CGPoint, in lines: [TextHighlightLine], tolerance: CGFloat?) -> Caret? {
        let candidates = lines.indices.filter { index in
            guard let tolerance else { return true }
            return lines[index].frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
        guard let line = candidates.min(by: { distance(from: point, to: lines[$0].frame) < distance(from: point, to: lines[$1].frame) }) else { return nil }
        return Caret(line: line, word: wordIndex(at: point.x, in: lines[line]))
    }

    public static func wordIndex(at x: CGFloat, in line: TextHighlightLine) -> Int {
        guard !line.words.isEmpty else { return 0 }
        if let containing = line.words.firstIndex(where: { $0.minX <= x && x <= $0.maxX }) {
            return containing
        }
        return line.words.indices.min { horizontalDistance(x, to: line.words[$0]) < horizontalDistance(x, to: line.words[$1]) } ?? 0
    }

    public static func rects(for lines: [TextHighlightLine], from start: CGPoint, to end: CGPoint, tolerance: CGFloat, padding: CGFloat = 0) -> [CGRect] {
        let ordered = readingOrder(lines.filter { $0.frame.width > 0 && $0.frame.height > 0 })
        guard !ordered.isEmpty else { return [] }
        let startCaret = caret(at: start, in: ordered, tolerance: tolerance)
        let endCaret = caret(at: end, in: ordered, tolerance: tolerance)
        let rects: [CGRect]
        switch (startCaret, endCaret) {
        case (nil, nil):
            rects = covered(by: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)), in: ordered)
        default:
            let origin = Caret(line: 0, word: 0)
            let first = startCaret ?? caret(at: start, in: ordered, tolerance: nil) ?? origin
            let last = endCaret ?? caret(at: end, in: ordered, tolerance: nil) ?? origin
            rects = flow(from: min(first, last), to: max(first, last), in: ordered)
        }
        return rects.map { $0.insetBy(dx: -padding, dy: -padding) }
    }

    public static func flow(from first: Caret, to last: Caret, in lines: [TextHighlightLine]) -> [CGRect] {
        (first.line ... last.line).compactMap { index in
            let line = lines[index]
            guard !line.words.isEmpty else { return line.frame }
            let from = index == first.line ? first.word : 0
            let to = index == last.line ? last.word : line.words.count - 1
            guard from <= to else { return nil }
            return union(Array(line.words[from ... to]), within: line.frame)
        }
    }

    public static func covered(by selection: CGRect, in lines: [TextHighlightLine]) -> [CGRect] {
        lines.compactMap { line in
            guard line.frame.intersects(selection) else { return nil }
            guard !line.words.isEmpty else { return line.frame }
            let words = line.words.filter { $0.minX <= selection.maxX && $0.maxX >= selection.minX }
            return words.isEmpty ? nil : union(words, within: line.frame)
        }
    }

    private static func union(_ words: [CGRect], within line: CGRect) -> CGRect {
        let minX = words.map(\.minX).min() ?? line.minX
        let maxX = words.map(\.maxX).max() ?? line.maxX
        return CGRect(x: minX, y: line.minY, width: maxX - minX, height: line.height)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func horizontalDistance(_ x: CGFloat, to rect: CGRect) -> CGFloat {
        max(rect.minX - x, 0, x - rect.maxX)
    }
}
