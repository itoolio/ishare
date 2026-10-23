import Defaults
import Foundation

enum AltTextTemplate {
    static let quoteLimit = 80
    static let subjectLimit = 3

    static func sentence(for context: SceneContext, locale: Locale = .current) -> String? {
        let subjects = Array((context.objects + context.labels).prefix(subjectLimit))
        let quote = context.text.isEmpty ? nil : TextCapturePreview.summary(of: context.text, limit: quoteLimit)
        let list = subjects.formatted(.list(type: .and).locale(locale))
        switch (subjects.isEmpty, quote) {
        case let (false, quote?):
            return String(format: "Screenshot showing %@, with text reading “%@”.".localized(), list, quote)
        case (false, nil):
            return String(format: "Screenshot showing %@.".localized(), list)
        case let (true, quote?):
            return String(format: "Screenshot with text reading “%@”.".localized(), quote)
        case (true, nil):
            return nil
        }
    }
}

enum AltText {
    static let maximumLength = 250

    static func generate(for url: URL) async -> String? {
        guard let context = await SceneAnalyzer.analyze(fileAt: url), !context.isEmpty else { return nil }
        return await generate(from: context)
    }

    static func generate(from context: SceneContext, usesModel: Bool = OnDeviceModel.isAvailable) async -> String? {
        if usesModel,
            let response = try? await OnDeviceModel.respond(to: SceneContextPrompt.altText(for: context), instructions: SceneContextPrompt.altTextInstructions),
            let sentence = sanitized(response)
        {
            return sentence
        }
        return AltTextTemplate.sentence(for: context)
    }

    static func sanitized(_ response: String) -> String? {
        var text = response.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^(alt[ -]?text)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’").union(.whitespaces))
        guard !text.isEmpty else { return nil }
        if text.count > maximumLength {
            text = String(text.prefix(maximumLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    static func markdown(alt: String, url: URL) -> String {
        let escaped =
            alt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "![\(escaped)](\(url.absoluteString))"
    }

    static func applying(_ altText: String, toUploadsAt urls: Set<String>, in history: [HistoryItem]) -> [HistoryItem] {
        history.map { item in
            guard let fileUrl = item.fileUrl, urls.contains(fileUrl) else { return item }
            var item = item
            item.altText = altText
            return item
        }
    }

    @MainActor static func store(_ altText: String, forUploadsAt urls: [URL]) {
        let keys = Set(urls.map(\.absoluteString))
        guard !keys.isEmpty else { return }
        let history = Defaults[.uploadHistory]
        let updated = applying(altText, toUploadsAt: keys, in: history)
        if updated != history {
            Defaults[.uploadHistory] = updated
        }
    }

    @MainActor static var isEnabled: Bool {
        Defaults[.generateAltText] && OnDeviceModel.isAvailable
    }
}

extension HistoryItem {
    var markdownImage: String? {
        guard let altText, !altText.isEmpty, let url = remoteURL else { return nil }
        return AltText.markdown(alt: altText, url: url)
    }
}
