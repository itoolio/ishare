import Foundation

public enum LiveCaptionText {
    public static let defaultLineLength = 42
    public static let defaultLineCount = 2

    public static func lines(of transcript: String, lineLength: Int = defaultLineLength, lineCount: Int = defaultLineCount) -> [String] {
        let words = transcript.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, lineLength > 0, lineCount > 0 else { return [] }
        var lines: [String] = []
        var current = ""
        for word in words {
            let clipped = word.count > lineLength ? String(word.suffix(lineLength)) : word
            if current.isEmpty {
                current = clipped
            } else if current.count + 1 + clipped.count <= lineLength {
                current += " " + clipped
            } else {
                lines.append(current)
                current = clipped
            }
        }
        lines.append(current)
        return Array(lines.suffix(lineCount))
    }
}
