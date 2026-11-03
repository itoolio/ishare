import CoreGraphics
import Foundation

public enum AnnotationCommandKind: String, CaseIterable, Sendable {
    case arrow
    case rectangle
    case ellipse
    case highlight
    case step
    case blur
    case pixelate

    static let keywords: [(AnnotationCommandKind, [String])] = [
        (.arrow, ["arrow", "point to", "point at", "pointing"]),
        (.ellipse, ["circle", "ellipse", "ring"]),
        (.rectangle, ["box", "rectangle", "outline", "frame", "border", "square"]),
        (.highlight, ["highlight", "mark", "emphasize"]),
        (.step, ["step", "number", "badge"]),
        (.pixelate, ["pixelate", "pixel"]),
        (.blur, ["blur", "hide", "redact", "censor", "cover"]),
    ]
}

public struct ParsedAnnotationCommand: Equatable, Sendable {
    public var kind: AnnotationCommandKind
    public var target: String
}

public enum AnnotationCommand {
    static let fillerWords: Set<String> = ["a", "an", "the", "to", "at", "on", "around", "over", "add", "draw", "put", "please", "button", "label", "field", "text", "word", "of", "with", "and"]

    public static func parse(_ text: String) -> ParsedAnnotationCommand? {
        let lowered = text.lowercased()
        let found = AnnotationCommandKind.keywords.compactMap { kind, words -> (AnnotationCommandKind, Range<String.Index>)? in
            words.compactMap { lowered.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }.map { (kind, $0) }
        }
        guard let (kind, range) = found.min(by: { $0.1.lowerBound < $1.1.lowerBound }) else { return nil }
        var rest = String(lowered[range.upperBound...]) + " " + String(lowered[..<range.lowerBound])
        if let quoted = text.firstMatch(of: /[“"']([^”"']+)[”"']/) {
            rest = String(quoted.1).lowercased()
        }
        let target = tokens(rest).filter { !fillerWords.contains($0) }.joined(separator: " ")
        return target.isEmpty ? nil : ParsedAnnotationCommand(kind: kind, target: target)
    }

    public static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    public static func bestMatch(for target: String, in labels: [String]) -> Int? {
        let wanted = Set(tokens(target))
        guard !wanted.isEmpty else { return nil }
        var best: (index: Int, score: Double)?
        for (index, label) in labels.enumerated() {
            let have = tokens(label)
            guard !have.isEmpty else { continue }
            let overlap = Double(wanted.intersection(have).count)
            let partial = wanted.contains { word in have.contains { $0.hasPrefix(word) || word.hasPrefix($0) } } ? 0.5 : 0
            let score = (overlap + partial) / Double(max(wanted.count, have.count))
            if score > 0, score > (best?.score ?? 0) {
                best = (index, score)
            }
        }
        return best?.index
    }

    public static func parseModelReply(_ reply: String, labelCount: Int) -> (AnnotationCommandKind, Int)? {
        guard let match = reply.firstMatch(of: /([a-z]+)\s*\|\s*(\d+)/), let kind = AnnotationCommandKind(rawValue: String(match.1)),
            let index = Int(match.2), (0..<labelCount).contains(index)
        else { return nil }
        return (kind, index)
    }

    public static func arrow(to target: CGRect, in bounds: CGRect) -> (start: CGPoint, end: CGPoint) {
        let length = max(60, min(bounds.width, bounds.height) * 0.12)
        let goesLeft = target.midX > bounds.midX
        let goesUp = target.midY > bounds.midY
        let end = CGPoint(x: goesLeft ? target.minX - 4 : target.maxX + 4, y: goesUp ? target.minY - 4 : target.maxY + 4)
        let start = CGPoint(x: end.x + (goesLeft ? -length : length), y: end.y + (goesUp ? -length * 0.7 : length * 0.7))
        return (CGPoint(x: min(max(start.x, bounds.minX), bounds.maxX), y: min(max(start.y, bounds.minY), bounds.maxY)), end)
    }

    public static func outline(around target: CGRect, padding: CGFloat = 6) -> CGRect {
        target.insetBy(dx: -padding, dy: -padding)
    }
}
