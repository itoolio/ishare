import CoreGraphics
import Foundation
import ImageIO
import Vision

struct SceneContext: Hashable, Sendable {
    var text: String
    var labels: [String]
    var objects: [String]

    static let empty = SceneContext(text: "", labels: [], objects: [])

    var isEmpty: Bool {
        text.isEmpty && labels.isEmpty && objects.isEmpty
    }
}

struct SceneLabel: Hashable, Sendable {
    var identifier: String
    var confidence: Float
}

enum SceneLabels {
    static let minimumConfidence: Float = 0.3
    static let maximumCount = 6

    static func select(_ labels: [SceneLabel], minimumConfidence: Float = minimumConfidence, limit: Int = maximumCount) -> [String] {
        var seen = Set<String>()
        return
            labels
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .map { humanized($0.identifier) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(limit)
            .map(\.self)
    }

    static func humanized(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

struct SceneObjects: Hashable, Sendable {
    var animals: [String] = []
    var people = 0
    var faces = 0
    var codes: [String] = []

    var phrases: [String] {
        var phrases: [String] = []
        if people > 0 {
            phrases.append(people == 1 ? "1 person" : "\(people) people")
        }
        if faces > 0 {
            phrases.append(faces == 1 ? "1 face" : "\(faces) faces")
        }
        var seenAnimals = Set<String>()
        phrases += animals.map(SceneLabels.humanized).filter { seenAnimals.insert($0).inserted }
        phrases += codes.map { "a code containing \($0)" }
        return phrases
    }
}

enum SceneAnalyzer {
    static func analyze(_ image: CGImage) async -> SceneContext {
        async let text = recognizedText(in: image)
        async let vision = detached { try performVision(on: image) }
        let (labels, objects) = await (vision?.labels ?? [], vision?.objects ?? SceneObjects())
        return SceneContext(text: await text, labels: SceneLabels.select(labels), objects: objects.phrases)
    }

    static func analyze(fileAt url: URL) async -> SceneContext? {
        guard let image = image(at: url) else { return nil }
        return await analyze(image)
    }

    static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func recognizedText(in image: CGImage) async -> String {
        ((try? await TextRecognition.recognize(in: image)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detached<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async -> Value? {
        try? await Task.detached(priority: .userInitiated) { try work() }.value
    }

    private static func performVision(on image: CGImage) throws -> (labels: [SceneLabel], objects: SceneObjects) {
        let classify = VNClassifyImageRequest()
        let animals = VNRecognizeAnimalsRequest()
        let humans = VNDetectHumanRectanglesRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let codes = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([classify, animals, humans, faces, codes])
        let labels = (classify.results ?? []).map { SceneLabel(identifier: $0.identifier, confidence: $0.confidence) }
        let objects = SceneObjects(
            animals: (animals.results ?? []).compactMap { $0.labels.first?.identifier },
            people: humans.results?.count ?? 0,
            faces: faces.results?.count ?? 0,
            codes: (codes.results ?? []).compactMap(\.payloadStringValue).filter { !$0.isEmpty }
        )
        return (labels, objects)
    }
}
