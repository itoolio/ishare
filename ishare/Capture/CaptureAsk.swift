import AppKit
import BezelNotification
import Defaults
import KeyboardShortcuts
import SwiftUI

enum AskQuickPrompt: String, CaseIterable, Identifiable, Sendable {
    case describe
    case summarize
    case actionItems
    case explainError

    var id: Self { self }

    var title: String {
        switch self {
        case .describe: "Describe"
        case .summarize: "Summarize"
        case .actionItems: "Extract action items"
        case .explainError: "Explain this error"
        }
    }

    var symbol: String {
        switch self {
        case .describe: "text.below.photo"
        case .summarize: "text.alignleft"
        case .actionItems: "checklist"
        case .explainError: "exclamationmark.triangle"
        }
    }

    var question: String {
        switch self {
        case .describe: "Describe what this screenshot most likely shows."
        case .summarize: "Summarize the text in this screenshot in a few sentences."
        case .actionItems: "List the action items, tasks or to-dos in this screenshot as a short bulleted list. Say so if there are none."
        case .explainError: "Explain the error message in this screenshot, what likely causes it and how to fix it. Say so if there is no error."
        }
    }
}

@MainActor
final class CaptureAskModel: ObservableObject {
    let image: NSImage
    let context: SceneContext
    @Published var prompt = ""
    @Published private(set) var question: String?
    @Published private(set) var answer = ""
    @Published private(set) var isResponding = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var copied = false
    private var task: Task<Void, Never>?
    var onClose: () -> Void = {}

    init(image: NSImage, context: SceneContext) {
        self.image = image
        self.context = context
    }

    var recognizedSummary: String {
        let items = context.objects + context.labels
        let lineCount = context.text.isEmpty ? 0 : context.text.split(separator: "\n").count
        var parts: [String] = []
        if lineCount > 0 {
            parts.append(lineCount == 1 ? "1 line of text".localized() : String(format: "%d lines of text".localized(), lineCount))
        }
        parts += items.prefix(5)
        return parts.isEmpty ? "Nothing recognized".localized() : parts.joined(separator: " · ")
    }

    func ask(_ quickPrompt: AskQuickPrompt) {
        send(quickPrompt.question, shownAs: quickPrompt.title.localized())
    }

    func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        send(text, shownAs: text)
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        TextCaptureFlow.copy(answer)
        copied = true
    }

    func close() {
        task?.cancel()
        task = nil
        onClose()
        onClose = {}
    }

    private func send(_ text: String, shownAs title: String) {
        task?.cancel()
        question = title
        answer = ""
        errorMessage = nil
        copied = false
        isResponding = true
        let fullPrompt = SceneContextPrompt.question(text, context: context)
        task = Task { [weak self] in
            do {
                try await OnDeviceModel.stream(fullPrompt, instructions: SceneContextPrompt.askInstructions) { partial in
                    guard !Task.isCancelled else { return }
                    self?.answer = partial
                }
            } catch {
                if !Task.isCancelled {
                    Log.capture.error("Capture and Ask failed: \(error.localizedDescription, privacy: .public)")
                    self?.errorMessage = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                self?.isResponding = false
            }
        }
    }
}

struct CaptureAskView: View {
    @ObservedObject var model: CaptureAskModel
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptureResultHeader(
                symbol: "sparkles", title: "Capture and Ask".localized(),
                subtitle: "Answers are based on the text and objects ishare recognizes".localized(), close: model.close
            )
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: model.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recognized".localized())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(model.recognizedSummary)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(AskQuickPrompt.allCases) { quickPrompt in
                    Button {
                        model.ask(quickPrompt)
                    } label: {
                        Label(quickPrompt.title.localized(), systemImage: quickPrompt.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButtonStyle()
                    .disabled(model.isResponding)
                    .accessibilityIdentifier("ask.\(quickPrompt.rawValue)")
                }
            }
            CaptureResultTextBox(title: model.question ?? "Answer".localized(), text: model.answer, placeholder: placeholder)
            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField("Ask about this capture".localized(), text: $model.prompt)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPromptFocused)
                    .onSubmit(model.submit)
                    .disabled(model.isResponding)
                Button(model.copied ? "Copied".localized() : "Copy".localized(), action: model.copyAnswer)
                    .adaptiveGlassButtonStyle(prominent: true)
                    .disabled(model.answer.isEmpty || model.isResponding)
            }
        }
        .padding(14)
        .adaptiveGlass(cornerRadius: 18)
        .onAppear { isPromptFocused = true }
    }

    private var placeholder: String {
        model.isResponding ? "Thinking…".localized() : "Pick a quick prompt or ask a question about this capture.".localized()
    }
}

@MainActor
enum CaptureAskFlow {
    static let panelSize = CGSize(width: 480, height: 500)
    private static var isCapturing = false
    private static var current: CaptureAskModel?

    static var isAvailable: Bool {
        OnDeviceModel.isAvailable
    }

    static func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .captureAsk) {
            Task { @MainActor in
                await run()
            }
        }
    }

    static func run() async {
        guard isAvailable else {
            BezelNotification.show(messageText: "Apple Intelligence is not available on this Mac".localized(), icon: ToastIcon)
            return
        }
        guard !isCapturing else { return }
        isCapturing = true
        let image = await ImageCaptureFlow.captureForRecognition()
        guard let image else {
            isCapturing = false
            return
        }
        let context = await SceneAnalyzer.analyze(image)
        isCapturing = false
        guard !context.isEmpty else {
            BezelNotification.show(messageText: "ishare couldn't recognize any text or objects".localized(), icon: ToastIcon)
            return
        }
        present(image: NSImage(cgImage: image, size: .zero), context: context)
    }

    static func present(image: NSImage, context: SceneContext) {
        current?.close()
        let model = CaptureAskModel(image: image, context: context)
        let panel = CaptureResultPanel(size: panelSize, content: CaptureAskView(model: model))
        current = model
        model.onClose = { [weak model] in
            panel.close()
            if let model, current === model { current = nil }
        }
        SoundPlayer.play(.capture)
        panel.show()
    }
}
