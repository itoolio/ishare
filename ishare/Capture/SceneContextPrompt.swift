import Foundation

enum SceneContextPrompt {
    static let textLimit = 3000

    static let askInstructions = """
        You help people with screenshots they captured on their Mac. You cannot see the image. \
        You only receive the text that was recognized in it, labels that classify the scene, and objects that were detected. \
        Base every answer on that context, say plainly when it isn't enough, and never invent details that aren't in it. \
        Keep answers short and use plain text without Markdown headings.
        """

    static let altTextInstructions = """
        You write alt text for images that people share online. You cannot see the image. \
        You only receive the text that was recognized in it, labels that classify the scene, and objects that were detected. \
        Reply with exactly one plain sentence of at most 125 characters that describes what the image most likely shows. \
        Mention the most important text when it matters. Don't add quotes, a preamble or a label like "Alt text:".
        """

    static func contextBlock(_ context: SceneContext, textLimit: Int = textLimit) -> String {
        let text = truncated(context.text, limit: textLimit)
        return [
            text.isEmpty ? "Recognized text: none" : "Recognized text:\n\"\"\"\n\(text)\n\"\"\"",
            "Scene labels: \(listed(context.labels))",
            "Detected objects: \(listed(context.objects))",
        ].joined(separator: "\n")
    }

    static func question(_ question: String, context: SceneContext, language: String? = responseLanguage()) -> String {
        var parts = [contextBlock(context), "Question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))"]
        if let language {
            parts.append("Respond in \(language).")
        }
        return parts.joined(separator: "\n\n")
    }

    static func altText(for context: SceneContext, language: String? = responseLanguage()) -> String {
        var parts = [contextBlock(context, textLimit: 1500), "Write the alt text for this image."]
        if let language {
            parts.append("Write it in \(language).")
        }
        return parts.joined(separator: "\n\n")
    }

    static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func responseLanguage(for locale: Locale = .current) -> String? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }

    private static func listed(_ items: [String]) -> String {
        items.isEmpty ? "none" : items.joined(separator: ", ")
    }
}
