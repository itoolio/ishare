import CoreGraphics
import Foundation
import Vision

struct RecognizedWord: Hashable, Sendable {
    var range: NSRange
    var boundingBox: CGRect
}

struct RecognizedLine: Hashable, Sendable {
    var text: String
    var boundingBox: CGRect
    var words: [RecognizedWord] = []
}

enum TextLayout {
    static func ordered(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        rows(of: lines).flatMap { $0 }
    }

    static func joined(_ lines: [RecognizedLine]) -> String {
        rows(of: lines)
            .map { row in row.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    static func rows(of lines: [RecognizedLine]) -> [[RecognizedLine]] {
        let topToBottom = lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[RecognizedLine]] = []
        for line in topToBottom {
            if let last = rows.indices.last, rows[last].contains(where: { sharesRow($0.boundingBox, line.boundingBox) }) {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in row.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    static func sharesRow(_ first: CGRect, _ second: CGRect) -> Bool {
        let overlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
        return overlap > min(first.height, second.height) * 0.5
    }

    static func wordRanges(in text: String) -> [NSRange] {
        let pattern = /\S+/
        return text.matches(of: pattern).map { NSRange($0.range, in: text) }
    }
}

enum TextRecognition {
    static func recognize(in image: CGImage) async throws -> String {
        TextLayout.joined(try await lines(in: image))
    }

    static func lines(in image: CGImage) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            try performRecognition(on: image)
        }.value
    }

    private static func performRecognition(on image: CGImage) throws -> [RecognizedLine] {
        do {
            return try performRecognition(on: image, onCPU: false)
        } catch {
            return try performRecognition(on: image, onCPU: true)
        }
    }

    private static func performRecognition(on image: CGImage, onCPU: Bool) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        if onCPU, let cpu = try request.supportedComputeStageDevices[.main]?.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap(line(from:))
    }

    private static func line(from observation: VNRecognizedTextObservation) -> RecognizedLine? {
        guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
        let text = candidate.string
        let words = TextLayout.wordRanges(in: text).compactMap { range -> RecognizedWord? in
            guard let swiftRange = Range(range, in: text),
                let box = try? candidate.boundingBox(for: swiftRange)?.boundingBox
            else { return nil }
            return RecognizedWord(range: range, boundingBox: box)
        }
        return RecognizedLine(text: text, boundingBox: observation.boundingBox, words: words)
    }
}
