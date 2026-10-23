import AppKit
import Defaults
import Foundation
import Testing
@testable import ishare

struct SceneContextTests {
    @Test func labelsAreFilteredSortedHumanizedAndDeduplicated() {
        let labels = [
            SceneLabel(identifier: "document", confidence: 0.5),
            SceneLabel(identifier: "computer_keyboard", confidence: 0.9),
            SceneLabel(identifier: "sky", confidence: 0.1),
            SceneLabel(identifier: "Document", confidence: 0.4),
            SceneLabel(identifier: "text", confidence: 0.3),
        ]
        #expect(SceneLabels.select(labels) == ["computer keyboard", "document", "text"])
        #expect(SceneLabels.select(labels, limit: 1) == ["computer keyboard"])
        #expect(SceneLabels.select(labels, minimumConfidence: 0.95).isEmpty)
    }

    @Test func objectsBecomeReadablePhrases() {
        let objects = SceneObjects(animals: ["Cat", "cat", "Dog"], people: 2, faces: 1, codes: ["https://example.com"])
        #expect(objects.phrases == ["2 people", "1 face", "cat", "dog", "a code containing https://example.com"])
        #expect(SceneObjects(people: 1).phrases == ["1 person"])
        #expect(SceneObjects().phrases.isEmpty)
    }

    @Test func emptinessDependsOnEveryPart() {
        #expect(SceneContext.empty.isEmpty)
        #expect(!SceneContext(text: "", labels: ["text"], objects: []).isEmpty)
        #expect(!SceneContext(text: "Hi", labels: [], objects: []).isEmpty)
    }

    @Test func analyzerReadsTextFromAnImage() async throws {
        let image = TextImages.render([("Deploy failed at step three", CGPoint(x: 40, y: 120))])
        let context = await SceneAnalyzer.analyze(image)
        #expect(context.text.lowercased().contains("deploy failed"))
    }
}

struct SceneContextPromptTests {
    let context = SceneContext(text: "TypeError: undefined is not a function", labels: ["document", "text"], objects: ["1 person"])

    @Test func contextBlockListsTextLabelsAndObjects() {
        let block = SceneContextPrompt.contextBlock(context)
        #expect(block.contains("Recognized text:\n\"\"\"\nTypeError: undefined is not a function\n\"\"\""))
        #expect(block.contains("Scene labels: document, text"))
        #expect(block.contains("Detected objects: 1 person"))
    }

    @Test func contextBlockSaysWhenNothingWasFound() {
        let block = SceneContextPrompt.contextBlock(.empty)
        #expect(block == "Recognized text: none\nScene labels: none\nDetected objects: none")
    }

    @Test func longTextIsTruncated() {
        let text = String(repeating: "a", count: 50)
        #expect(SceneContextPrompt.truncated(text, limit: 10) == String(repeating: "a", count: 10) + "…")
        #expect(SceneContextPrompt.truncated("  short  ", limit: 10) == "short")
        let block = SceneContextPrompt.contextBlock(SceneContext(text: text, labels: [], objects: []), textLimit: 5)
        #expect(block.contains("aaaaa…"))
        #expect(!block.contains("aaaaaa"))
    }

    @Test func questionAddsTheQuestionAndLanguage() {
        let prompt = SceneContextPrompt.question("  What broke?  ", context: context, language: "German")
        #expect(prompt.hasPrefix(SceneContextPrompt.contextBlock(context)))
        #expect(prompt.contains("Question: What broke?"))
        #expect(prompt.hasSuffix("Respond in German."))
        #expect(!SceneContextPrompt.question("Hi", context: context, language: nil).contains("Respond in"))
    }

    @Test func altTextPromptAsksForOneSentence() {
        let prompt = SceneContextPrompt.altText(for: context, language: "French")
        #expect(prompt.contains("Scene labels: document, text"))
        #expect(prompt.contains("Write the alt text for this image."))
        #expect(prompt.hasSuffix("Write it in French."))
        #expect(SceneContextPrompt.altTextInstructions.contains("exactly one plain sentence"))
        #expect(SceneContextPrompt.askInstructions.contains("You cannot see the image"))
    }

    @Test func responseLanguageIsNamedInEnglish() {
        #expect(SceneContextPrompt.responseLanguage(for: Locale(identifier: "de_DE")) == "German")
        #expect(SceneContextPrompt.responseLanguage(for: Locale(identifier: "ja")) == "Japanese")
    }

    @Test func everyQuickPromptHasATitleAndQuestion() {
        #expect(AskQuickPrompt.allCases.map(\.title) == ["Describe", "Summarize", "Extract action items", "Explain this error"])
        for prompt in AskQuickPrompt.allCases {
            #expect(!prompt.question.isEmpty)
            #expect(!prompt.symbol.isEmpty)
        }
    }
}

struct AltTextTests {
    let english = Locale(identifier: "en_US")

    @Test func templateCombinesSubjectsAndText() {
        let context = SceneContext(text: "Quarterly report", labels: ["document", "text", "chart", "paper"], objects: ["1 person"])
        let expected = String(format: "Screenshot showing %@, with text reading “%@”.".localized(), "1 person, document, and text", "Quarterly report")
        #expect(AltTextTemplate.sentence(for: context, locale: english) == expected)
    }

    @Test func templateHandlesLabelsOnlyTextOnlyAndNothing() {
        let labelsOnly = SceneContext(text: "", labels: ["cat"], objects: [])
        #expect(AltTextTemplate.sentence(for: labelsOnly, locale: english) == String(format: "Screenshot showing %@.".localized(), "cat"))
        let textOnly = SceneContext(text: "Hello\nworld", labels: [], objects: [])
        #expect(AltTextTemplate.sentence(for: textOnly, locale: english) == String(format: "Screenshot with text reading “%@”.".localized(), "Hello world"))
        #expect(AltTextTemplate.sentence(for: .empty, locale: english) == nil)
    }

    @Test func templateShortensLongText() throws {
        let context = SceneContext(text: String(repeating: "word ", count: 40), labels: [], objects: [])
        let sentence = try #require(AltTextTemplate.sentence(for: context, locale: english))
        #expect(sentence.contains("…"))
        #expect(sentence.count < 140)
    }

    @Test func generatingWithoutTheModelFallsBackToTheTemplate() async {
        let context = SceneContext(text: "", labels: ["laptop"], objects: [])
        #expect(await AltText.generate(from: context, usesModel: false) == AltTextTemplate.sentence(for: context))
        #expect(await AltText.generate(from: .empty, usesModel: false) == nil)
    }

    @Test func modelResponsesAreCleanedUp() {
        #expect(AltText.sanitized("Alt text: “A terminal showing a failed build.”\nExtra line") == "A terminal showing a failed build.")
        #expect(AltText.sanitized("  \"A cat on a sofa.\"  ") == "A cat on a sofa.")
        #expect(AltText.sanitized("alt-text:   A chart.") == "A chart.")
        #expect(AltText.sanitized("   ") == nil)
        let long = AltText.sanitized(String(repeating: "a", count: 400))
        #expect(long?.count == AltText.maximumLength)
        #expect(long?.hasSuffix("…") == true)
    }

    @Test func markdownEscapesBrackets() throws {
        let url = try #require(URL(string: "https://cdn.example.com/a.png"))
        #expect(AltText.markdown(alt: "A [draft] chart", url: url) == "![A \\[draft\\] chart](https://cdn.example.com/a.png)")
    }

    @Test func altTextIsAppliedToMatchingUploadsOnly() {
        let history = [
            HistoryItem(fileUrl: "https://cdn.example.com/a.png"),
            HistoryItem(fileUrl: "https://cdn.example.com/b.png"),
            HistoryItem(),
        ]
        let updated = AltText.applying("A chart.", toUploadsAt: ["https://cdn.example.com/b.png"], in: history)
        #expect(updated.map(\.altText) == [nil, "A chart.", nil])
    }

    @Test func historyItemsExposeMarkdownWithAltText() {
        var item = HistoryItem(fileUrl: "https://cdn.example.com/a.png", shortUrl: "https://s.example.com/x")
        #expect(item.markdownImage == nil)
        item.altText = "A chart."
        #expect(item.markdownImage == "![A chart.](https://cdn.example.com/a.png)")
    }

    @Test func historyStaysDecodableWithAndWithoutAltText() throws {
        let legacy = Data(#"{"fileUrl":"https://cdn.example.com/a.png"}"#.utf8)
        let decoded = try JSONDecoder().decode(HistoryItem.self, from: legacy)
        #expect(decoded.altText == nil)
        var item = decoded
        item.altText = "A chart."
        let roundTripped = try JSONDecoder().decode(HistoryItem.self, from: JSONEncoder().encode(item))
        #expect(roundTripped.altText == "A chart.")
    }

    @Test @MainActor func altTextIsOffByDefault() {
        #expect(Defaults.Keys.generateAltText.defaultValue == false)
        #expect(Defaults.Keys.translationTargetLanguage.defaultValue == "")
    }
}

struct TranslationLanguagesTests {
    @Test func emptySettingUsesTheSystemLanguage() {
        let system = Locale.Language(identifier: "de-DE")
        #expect(TranslationLanguages.target(forSetting: "", system: system) == system)
        #expect(TranslationLanguages.target(forSetting: " ja ", system: system) == Locale.Language(identifier: "ja"))
    }

    @Test func sameLanguageIgnoresRegionButNotScript() {
        #expect(TranslationLanguages.isSame(Locale.Language(identifier: "en-US"), Locale.Language(identifier: "en-GB")))
        #expect(TranslationLanguages.isSame(Locale.Language(identifier: "de"), Locale.Language(identifier: "de-DE")))
        #expect(!TranslationLanguages.isSame(Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "zh-Hant")))
        #expect(!TranslationLanguages.isSame(Locale.Language(identifier: "en"), Locale.Language(identifier: "fr")))
    }

    @Test func detectsTheSourceLanguage() {
        let french = TranslationLanguages.detectedSource(of: "Bonjour à tous, le rapport trimestriel est maintenant disponible dans le dossier partagé.")
        #expect(french?.languageCode?.identifier == "fr")
        let japanese = TranslationLanguages.detectedSource(of: "今日はとても良い天気ですね。会議は午後三時に始まります。")
        #expect(japanese?.languageCode?.identifier == "ja")
        #expect(TranslationLanguages.detectedSource(of: "") == nil)
    }

    @Test func optionsAreDeduplicatedAndSorted() {
        let english = Locale(identifier: "en_US")
        let options = TranslationLanguages.options(
            [Locale.Language(identifier: "ja"), Locale.Language(identifier: "de"), Locale.Language(identifier: "ja-JP")],
            including: [Locale.Language(identifier: "de")],
            in: english
        )
        #expect(options.map(\.id) == ["de", "ja"])
        #expect(options.map(\.name) == ["German", "Japanese"])
    }
}

struct CaptureCountdownFocusTests {
    @Test func restoresTheAppThatWasFrontmost() {
        let focus = CountdownFocus(ownProcessID: 10, frontmost: 42)
        #expect(focus.appToRestore == 42)
        #expect(CountdownFocus(ownProcessID: 10, frontmost: 10).appToRestore == nil)
        #expect(CountdownFocus(ownProcessID: 10, frontmost: nil).appToRestore == nil)
    }

    @Test func followsAppsTheUserActivatesButIgnoresItself() {
        var focus = CountdownFocus(ownProcessID: 10, frontmost: 42)
        let followedOtherApp = focus.activated(77)
        #expect(followedOtherApp)
        #expect(focus.appToRestore == 77)
        let followedItself = focus.activated(10)
        #expect(!followedItself)
        #expect(focus.appToRestore == 77)
    }
}

struct CaptureResultPanelTests {
    @Test func panelsSitAboveTheMiddleOfTheScreen() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let origin = CaptureResultPanel.origin(for: CGSize(width: 400, height: 300), in: frame)
        #expect(origin == CGPoint(x: 300, y: 300))
    }

    @Test func panelsStayOnSmallScreens() {
        let frame = CGRect(x: 100, y: 50, width: 300, height: 200)
        let origin = CaptureResultPanel.origin(for: CGSize(width: 400, height: 300), in: frame)
        #expect(origin == CGPoint(x: 108, y: 58))
    }
}

struct IntervalDeliveryTests {
    @Test @MainActor func intervalGIFsSkipTheEditorButReachTheOtherSteps() {
        #expect(IntervalDelivery.kind == .video)
        #expect(!AfterCaptureStep.openEditor.runs(for: IntervalDelivery.kind, options: CaptureOptions(openEditor: true)))
        #expect(AfterCaptureStep.upload.runs(for: IntervalDelivery.kind, options: CaptureOptions(forceUpload: true)))
    }
}
