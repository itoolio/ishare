import Defaults
import Foundation

enum CaptionOutput: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case srtFile
    case burnIn

    var id: Self { self }

    var title: String {
        switch self {
        case .srtFile: "Save as .srt next to the recording"
        case .burnIn: "Burn into the video"
        }
    }
}

struct TranscriptSegment: Hashable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

struct CaptionCue: Hashable, Sendable {
    var start: Double
    var end: Double
    var lines: [String]

    var text: String { lines.joined(separator: "\n") }
}

enum CaptionLayout {
    static let maxLineLength = 42
    static let maxLines = 2
    static let maxCueDuration: Double = 7
    static let maxPause: Double = 1.2
    static let minimumCueDuration: Double = 0.8
    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]

    static func words(from segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.flatMap { segment -> [TranscriptSegment] in
            let pieces = segment.text
                .split(whereSeparator: \.isWhitespace)
                .flatMap { chunked(String($0), length: maxLineLength) }
            guard !pieces.isEmpty else { return [] }
            let duration = max(0, segment.end - segment.start)
            let weights = pieces.map { Double($0.count + 1) }
            let total = weights.reduce(0, +)
            var cursor = segment.start
            return zip(pieces, weights).map { piece, weight in
                let end = cursor + duration * weight / total
                defer { cursor = end }
                return TranscriptSegment(text: piece, start: cursor, end: end)
            }
        }
    }

    static func wrap(_ words: [String], maxLineLength: Int = maxLineLength) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in words.flatMap({ chunked($0, length: maxLineLength) }) {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= maxLineLength {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    static func cues(from segments: [TranscriptSegment]) -> [CaptionCue] {
        let words = words(from: segments.sorted { $0.start < $1.start })
        var groups: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        for word in words {
            if let first = current.first, let last = current.last {
                let fits = wrap((current + [word]).map(\.text)).count <= maxLines
                let paused = word.start - last.end > maxPause
                let tooLong = word.end - first.start > maxCueDuration
                let endsSentence = last.text.last.map(sentenceTerminators.contains) ?? false
                if !fits || paused || tooLong || endsSentence {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        var cues = groups.compactMap { group -> CaptionCue? in
            guard let first = group.first, let last = group.last else { return nil }
            return CaptionCue(start: first.start, end: max(last.end, first.start + minimumCueDuration), lines: wrap(group.map(\.text)))
        }
        for index in cues.indices.dropLast() where cues[index].end > cues[index + 1].start {
            cues[index].end = max(cues[index].start, cues[index + 1].start)
        }
        return cues
    }

    private static func chunked(_ word: String, length: Int) -> [String] {
        guard word.count > length else { return [word] }
        var chunks: [String] = []
        var remainder = Substring(word)
        while !remainder.isEmpty {
            chunks.append(String(remainder.prefix(length)))
            remainder = remainder.dropFirst(length)
        }
        return chunks
    }
}

enum SRTFormatter {
    static func timestamp(_ seconds: Double) -> String {
        let totalMilliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60000 % 60
        let secs = totalMilliseconds / 1000 % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }

    static func string(for cues: [CaptionCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }
        .joined(separator: "\n")
    }

    static func subtitleURL(for videoURL: URL) -> URL {
        videoURL.deletingPathExtension().appendingPathExtension("srt")
    }

    static func write(_ cues: [CaptionCue], nextTo videoURL: URL) throws -> URL {
        let url = subtitleURL(for: videoURL)
        try string(for: cues).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
