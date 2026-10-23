import AppKit
import BezelNotification
import Defaults
import KeyboardShortcuts
import NaturalLanguage
import SwiftUI
import Translation

struct TranslationLanguageOption: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
}

enum TranslationLanguages {
    static let minimumDetectionConfidence = 0.4

    static func target(forSetting identifier: String, system: Locale.Language = Locale.current.language) -> Locale.Language {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? system : Locale.Language(identifier: trimmed)
    }

    static func detectedSource(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= minimumDetectionConfidence
        else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    static func isSame(_ first: Locale.Language, _ second: Locale.Language) -> Bool {
        let first = Locale.Language(identifier: first.maximalIdentifier)
        let second = Locale.Language(identifier: second.maximalIdentifier)
        guard let firstCode = first.languageCode, let secondCode = second.languageCode, firstCode == secondCode else { return false }
        guard let firstScript = first.script, let secondScript = second.script else { return true }
        return firstScript == secondScript
    }

    static func identifier(of language: Locale.Language) -> String {
        language.minimalIdentifier
    }

    static func displayName(of language: Locale.Language, in locale: Locale = .current) -> String {
        let identifier = identifier(of: language)
        return locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    static func options(_ languages: [Locale.Language], including extra: [Locale.Language] = [], in locale: Locale = .current) -> [TranslationLanguageOption] {
        var seen = Set<String>()
        return (languages + extra)
            .map { TranslationLanguageOption(id: identifier(of: $0), name: displayName(of: $0, in: locale)) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }
}

struct TranslationRequest: @unchecked Sendable {
    let session: TranslationSession
    let text: String
    let preparesDownload: Bool

    nonisolated func perform() async throws -> String {
        if preparesDownload {
            try await session.prepareTranslation()
        }
        return try await session.translate(text).targetText
    }
}

enum CaptureTranslateOutcome: Equatable {
    case translated(String)
    case noText
    case failed
    case cancelled
}

@MainActor
final class CaptureTranslateModel: ObservableObject {
    enum Phase: Equatable {
        case checking
        case needsDownload
        case translating
        case translated
        case sameLanguage
        case unsupported
        case failed(String)
    }

    let original: String
    let source: Locale.Language?
    @Published private(set) var target: Locale.Language
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var translation = ""
    @Published private(set) var copied = false
    @Published private(set) var options: [TranslationLanguageOption] = []
    @Published var configuration: TranslationSession.Configuration?
    private var preparesDownload = false
    var onFinish: ((CaptureTranslateOutcome) -> Void)?
    var onClose: () -> Void = {}

    init(original: String, source: Locale.Language?, target: Locale.Language) {
        self.original = original
        self.source = source
        self.target = target
        options = TranslationLanguages.options([], including: [target])
    }

    var targetID: String {
        TranslationLanguages.identifier(of: target)
    }

    var directionTitle: String {
        let targetName = TranslationLanguages.displayName(of: target)
        guard let source else { return targetName }
        return String(format: "%@ → %@".localized(), TranslationLanguages.displayName(of: source), targetName)
    }

    func prepare() async {
        options = TranslationLanguages.options(await TranslationLanguages.supportedLanguages(), including: [target])
        await evaluate()
    }

    func selectTarget(_ identifier: String) {
        guard identifier != targetID else { return }
        target = Locale.Language(identifier: identifier)
        Task { await evaluate() }
    }

    func evaluate() async {
        translation = ""
        copied = false
        if let source, TranslationLanguages.isSame(source, target) {
            phase = .sameLanguage
            return
        }
        phase = .checking
        switch await status() {
        case .installed:
            request(preparingDownload: false)
        case .supported:
            phase = .needsDownload
        default:
            phase = .unsupported
        }
    }

    func downloadLanguages() {
        NSApp.activate()
        request(preparingDownload: true)
    }

    func run(_ session: TranslationSession) async {
        let request = TranslationRequest(session: session, text: original, preparesDownload: preparesDownload)
        do {
            complete(try await request.perform())
        } catch {
            Log.capture.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    func copyTranslation() {
        guard !translation.isEmpty else { return }
        TextCaptureFlow.copy(translation)
        copied = true
    }

    func copyOriginal() {
        TextCaptureFlow.copy(original)
        copied = false
    }

    func close() {
        finish(.cancelled)
        onClose()
        onClose = {}
    }

    private func status() async -> LanguageAvailability.Status {
        let availability = LanguageAvailability()
        if let source {
            return await availability.status(from: source, to: target)
        }
        return (try? await availability.status(for: original, to: target)) ?? .unsupported
    }

    private func request(preparingDownload: Bool) {
        preparesDownload = preparingDownload
        phase = .translating
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func complete(_ text: String) {
        translation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .translated
        copyTranslation()
        finish(.translated(translation))
    }

    private func finish(_ outcome: CaptureTranslateOutcome) {
        onFinish?(outcome)
        onFinish = nil
    }
}

struct CaptureTranslateView: View {
    @ObservedObject var model: CaptureTranslateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptureResultHeader(symbol: "translate", title: "Capture and Translate".localized(), subtitle: model.directionTitle, close: model.close)
            CaptureResultTextBox(title: "Original".localized(), text: model.original)
            CaptureResultTextBox(title: "Translation".localized(), text: model.translation, placeholder: placeholder)
            status
            HStack(spacing: 8) {
                Picker("Translate to".localized(), selection: Binding(get: { model.targetID }, set: model.selectTarget)) {
                    ForEach(model.options) { Text($0.name).tag($0.id) }
                }
                .fixedSize()
                Spacer(minLength: 8)
                Button("Copy Original".localized(), action: model.copyOriginal)
                    .adaptiveGlassButtonStyle()
                Button("Copy Translation".localized(), action: model.copyTranslation)
                    .adaptiveGlassButtonStyle(prominent: true)
                    .disabled(model.translation.isEmpty)
            }
        }
        .padding(14)
        .adaptiveGlass(cornerRadius: 18)
        .translationTask(model.configuration) { session in
            await model.run(session)
        }
        .task { await model.prepare() }
    }

    private var placeholder: String? {
        switch model.phase {
        case .checking, .translating: "Translating…".localized()
        default: nil
        }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .checking, .translating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Translating on this Mac…".localized())
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .needsDownload:
            HStack(spacing: 8) {
                Text("The languages for this translation aren't downloaded yet.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Download Languages…".localized(), action: model.downloadLanguages)
                    .adaptiveGlassButtonStyle(prominent: true)
            }
        case .translated:
            if model.copied {
                Label("Translation copied".localized(), systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .sameLanguage:
            footnote("The text is already in this language. Choose another language to translate it.".localized())
        case .unsupported:
            footnote("Translation between these languages isn't supported.".localized())
        case let .failed(message):
            footnote(String(format: "Translation failed: %@".localized(), message))
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
enum CaptureTranslateFlow {
    static let panelSize = CGSize(width: 480, height: 460)
    private static var isCapturing = false
    private static var current: CaptureTranslateModel?

    static func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .captureTranslate) {
            Task { @MainActor in
                await run()
            }
        }
    }

    @discardableResult
    static func run() async -> CaptureTranslateOutcome {
        guard !isCapturing else { return .cancelled }
        isCapturing = true
        let outcome = await TextCaptureFlow.capture()
        isCapturing = false
        switch outcome {
        case let .recognized(text):
            return await present(text)
        case .noText:
            BezelNotification.show(messageText: "No text found".localized(), icon: ToastIcon)
            return .noText
        case .failed:
            BezelNotification.show(messageText: "Text recognition failed".localized(), icon: ToastIcon)
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    static func present(_ text: String) async -> CaptureTranslateOutcome {
        current?.close()
        let model = CaptureTranslateModel(
            original: text,
            source: TranslationLanguages.detectedSource(of: text),
            target: TranslationLanguages.target(forSetting: Defaults[.translationTargetLanguage])
        )
        let panel = CaptureResultPanel(size: panelSize, content: CaptureTranslateView(model: model))
        current = model
        model.onClose = { [weak model] in
            panel.close()
            if let model, current === model { current = nil }
        }
        SoundPlayer.play(.capture)
        return await withCheckedContinuation { continuation in
            model.onFinish = { continuation.resume(returning: $0) }
            panel.show()
        }
    }
}
