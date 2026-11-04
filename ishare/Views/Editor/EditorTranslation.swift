import AppKit
import BezelNotification
import Defaults
import ishareCore
import Translation

struct BatchTranslationRequest: @unchecked Sendable {
    let session: TranslationSession
    let texts: [String]

    nonisolated func perform() async throws -> [String] {
        try await session.prepareTranslation()
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
        let responses = try await session.translations(from: requests)
        var results = texts
        for response in responses {
            if let index = response.clientIdentifier.flatMap(Int.init), results.indices.contains(index) {
                results[index] = response.targetText
            }
        }
        return results
    }
}

@MainActor
final class EditorTranslation: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    private var lines: [CGRect] = []
    private var texts: [String] = []
    private var pixels: RGBAPixels?

    func begin(on image: CGImage) async -> Bool {
        guard let recognized = try? await TextRecognition.lines(in: image), !recognized.isEmpty else {
            BezelNotification.show(messageText: "No text found".localized(), icon: ToastIcon)
            return false
        }
        let size = CGSize(width: image.width, height: image.height)
        lines = recognized.map { UIElementDetector.pixelRect(fromNormalized: $0.boundingBox, imageSize: size) }
        texts = recognized.map(\.text)
        pixels = ImageUpscaler.PixelBuffer(image: image).map { RGBAPixels(width: $0.width, height: $0.height, bytes: $0.bytes) }
        let target = TranslationLanguages.target(forSetting: Defaults[.translationTargetLanguage])
        let source = TranslationLanguages.detectedSource(of: TextLayout.joined(TextLayout.ordered(recognized)))
        if let source, TranslationLanguages.isSame(source, target) {
            BezelNotification.show(messageText: "The text is already in your language".localized(), icon: ToastIcon)
            return false
        }
        NSApp.activate()
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
        return true
    }

    func annotations(using session: TranslationSession) async -> [Annotation] {
        let request = BatchTranslationRequest(session: session, texts: texts)
        let translated: [String]
        do {
            translated = try await request.perform()
        } catch {
            Log.capture.error("Translating the image failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Translation failed".localized(), icon: ToastIcon)
            return []
        }
        return zip(lines, translated).map { rect, text in Self.annotation(for: text, in: rect, pixels: pixels) }
    }

    static func annotation(for text: String, in rect: CGRect, pixels: RGBAPixels?) -> Annotation {
        let unit = AnnotationRenderer.textSize(text, fontSize: 100)
        let placement = TranslationOverlay.placement(
            for: rect, textWidthAtUnitSize: unit.width / 100, lineHeightAtUnitSize: unit.height / 100)
        let background = pixels.flatMap { TranslationOverlay.backgroundColor(around: rect, in: $0) }
        let color = background.map { RGBAColor(red: $0.red, green: $0.green, blue: $0.blue) } ?? .white
        var annotation = Annotation(shape: .text(placement.origin, text), color: color, lineWidth: 1, fontSize: placement.fontSize)
        annotation.textBackground = true
        return annotation
    }
}
