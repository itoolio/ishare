import Defaults
import Foundation
import ishareCore
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

struct AssistantMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
}

enum AssistantDraftReport {
    static func summary(for uploader: CustomUploader) -> String {
        let issues = UploaderValidator.issues(for: uploader)
        let state = "The draft now uploads to \(uploader.requestURL) and reads the link with the template \(uploader.responseURL)" + (uploader.deletionURL.map { " and deletes with \($0)" } ?? "") + ". "
        guard !issues.isEmpty else {
            return state + "It is valid. Tell the user it is ready to test and save, describing these exact values."
        }
        return state + "It has problems: " + issues.map(\.message).joined(separator: "; ") + ". Ask the user for the missing details or fix them."
    }
}

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable(description: "A configuration for uploading files to a web service with an HTTP request")
    struct GenerableUploader {
        @Guide(description: "A short name for the uploader, usually the service name in lowercase")
        var name: String
        @Guide(description: "The full https URL the file is POSTed to")
        var requestURL: String
        @Guide(description: "Either multipart or binary. Use multipart unless the service expects the raw file as the request body")
        var bodyType: String
        @Guide(description: "The multipart form field name that carries the file, for example file or image")
        var fileFormName: String
        @Guide(description: "Names of HTTP headers the service requires, such as Authorization, excluding Content-Type")
        var headerNames: [String]
        @Guide(description: "Values of the HTTP headers, in the same order as headerNames. Use exactly the values the user gave, or placeholders like YOUR_API_KEY")
        var headerValues: [String]
        @Guide(description: "Names of extra multipart text fields, if any")
        var formFieldNames: [String]
        @Guide(description: "Values of the extra multipart text fields, in the same order as formFieldNames")
        var formFieldValues: [String]
        @Guide(description: "Template for the public file URL. Wrap JSON paths from the response in double braces, for example {{data.url}} or {{files[0].url}}, or use {{response}} for a plain-text response")
        var responseURL: String
        @Guide(description: "Template for the deletion URL using the same placeholder syntax, or an empty string if the service has none")
        var deletionURL: String
        @Guide(description: "GET or DELETE, the HTTP method used for the deletion URL")
        var deletionMethod: String

        var spec: GeneratedUploaderSpec {
            GeneratedUploaderSpec(
                name: name, requestURL: requestURL, bodyType: bodyType, fileFormName: fileFormName,
                headerNames: headerNames, headerValues: headerValues, formFieldNames: formFieldNames,
                formFieldValues: formFieldValues, responseURL: responseURL, deletionURL: deletionURL, deletionMethod: deletionMethod
            )
        }
    }

    @available(macOS 26.0, *)
    struct UpdateUploaderDraftTool: Tool {
        let name = "updateUploaderDraft"
        let description = "Create or replace the uploader draft the user sees. Call it whenever you know enough to build or improve the uploader."
        let apply: @Sendable (GeneratedUploaderSpec) async -> String

        @Generable
        struct Arguments {
            @Guide(description: "The complete uploader configuration")
            var uploader: GenerableUploader
        }

        func call(arguments: Arguments) async throws -> String {
            await apply(arguments.uploader.spec)
        }
    }

    @available(macOS 26.0, *)
    @MainActor
    final class AssistantConversation {
        static let instructions = """
        You are the ishare uploader assistant. ishare is a macOS screenshot tool that uploads files to the user's own web service.
        Chat with the user in a friendly, concise way and in the language they write in.
        Work out how their service accepts uploads: the upload URL, authentication headers, the multipart field name or a raw binary body, and where the public link appears in the JSON response.
        Ask one short question at a time when something important is missing. If the user mentions a well-known service such as Zipline, chibisafe, copyparty, XBackBone or a Discord webhook, use what you know about its API and confirm the details.
        ishare sends one HTTP POST per file and reads the link from the response with templates like {{url}}, {{data.link}} or {{files[0].url}}, or {{response}} when the reply is plain text.
        Whenever you can build or improve the uploader, call updateUploaderDraft with the complete configuration, then briefly tell the user what you set up.
        Never invent secrets. Use the values the user provides, or placeholders such as YOUR_API_KEY.
        """

        private let session: LanguageModelSession

        init(apply: @escaping @Sendable (GeneratedUploaderSpec) async -> String) {
            session = LanguageModelSession(tools: [UpdateUploaderDraftTool(apply: apply)], instructions: Self.instructions)
        }

        func send(_ text: String) async throws -> String {
            try await session.respond(to: text).content
        }
    }
#endif

@MainActor
final class UploaderAssistantChatModel: ObservableObject {
    @Published var messages: [AssistantMessage] = [
        AssistantMessage(role: .assistant, text: "Hi! Tell me about the service you want to upload to, like where it runs and how you sign in, and I'll build the uploader for you.".localized()),
    ]
    @Published var input = ""
    @Published var draft: CustomUploader?
    @Published var isResponding = false
    @Published var testResult: String?
    private var conversation: AnyObject?

    var issues: [UploaderIssue] {
        draft.map(UploaderValidator.issues(for:)) ?? []
    }

    func apply(_ spec: GeneratedUploaderSpec) -> String {
        let conversation = messages.filter { $0.role == .user }.map(\.text).joined(separator: "\n")
        let uploader = AssistantRefinement.refine(UploaderAssistantMapper.uploader(from: spec, answers: AssistantAnswers()), conversation: conversation)
        draft = draft.map { uploader.withID($0.id) } ?? uploader
        testResult = nil
        return AssistantDraftReport.summary(for: uploader)
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        input = ""
        messages.append(AssistantMessage(role: .user, text: text))
        isResponding = true
        Task { @MainActor in
            defer { isResponding = false }
            do {
                let reply = try await respond(to: text)
                messages.append(AssistantMessage(role: .assistant, text: reply))
            } catch {
                messages.append(AssistantMessage(role: .assistant, text: error.localizedDescription))
            }
        }
    }

    private func respond(to text: String) async throws -> String {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let conversation = (self.conversation as? AssistantConversation) ?? AssistantConversation { [weak self] spec in
                    await MainActor.run { self?.apply(spec) ?? "" }
                }
                self.conversation = conversation
                return try await conversation.send(text)
            }
        #endif
        throw AssistantError.unavailable
    }

    func test() {
        guard let draft else { return }
        testResult = "Uploading a test image…".localized()
        Task { @MainActor in
            let file = FileManager.default.temporaryDirectory.appending(path: "ishare-assistant-test.png")
            if let icon = NSImage(named: NSImage.applicationIconName)?.tiffRepresentation,
               let png = NSBitmapImageRep(data: icon)?.representation(using: .png, properties: [:])
            {
                try? png.write(to: file)
            }
            do {
                let outcome = try await UploadService.upload(fileURL: file, to: .custom(draft))
                testResult = String(format: "Uploaded to %@".localized(), outcome.url.absoluteString)
            } catch {
                testResult = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func loadScreenshotConversation() {
        messages = [
            messages[0],
            AssistantMessage(role: .user, text: "I run Zipline at share.example.com, my token is in the Authorization header"),
            AssistantMessage(role: .assistant, text: "Got it! Zipline takes uploads at /api/upload with a file field and returns the link as files[0].url. I set up a draft for you, test it whenever you're ready."),
        ]
        _ = apply(ScreenshotMode.sampleAssistantSpec)
    }
}

enum AssistantOutcome {
    case save(CustomUploader)
    case edit(CustomUploader)
}

struct UploaderAssistantSheet: View {
    @StateObject private var model = UploaderAssistantChatModel()
    @FocusState private var inputFocused: Bool
    let onFinish: (AssistantOutcome?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.messages) { message in
                            bubble(for: message)
                                .id(message.id)
                        }
                        if model.isResponding {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…".localized())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 6)
                            .id("typing")
                        }
                        if let draft = model.draft {
                            draftCard(draft)
                                .id("draft")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.messages) {
                    withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: model.draft) {
                    withAnimation { proxy.scrollTo("draft", anchor: .bottom) }
                }
            }
            Divider()
            inputBar
        }
        .onAppear {
            if ScreenshotMode.isActive {
                model.loadScreenshotConversation()
            }
            inputFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Uploader Assistant".localized())
                    .font(.headline)
                Text("Runs on your Mac with Apple Intelligence".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close".localized()) { onFinish(nil) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    private func bubble(for message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            Text(message.text)
                .textSelection(.enabled)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor)
                    }
                }
                .adaptiveGlass(cornerRadius: 16, tint: message.role == .user ? .accentColor : nil)
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private func draftCard(_ draft: CustomUploader) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(draft.name, systemImage: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.issues.isEmpty ? "Ready".localized() : "Needs details".localized())
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill((model.issues.isEmpty ? Color.green : Color.orange).opacity(0.2)))
            }
            Group {
                LabeledContent("Request URL*".localized(), value: draft.requestURL)
                LabeledContent("Response URL*".localized(), value: draft.responseURL)
                if let headers = draft.headers, !headers.isEmpty {
                    LabeledContent("Headers".localized(), value: headers.keys.sorted().joined(separator: ", "))
                }
                if let deletion = draft.deletionURL {
                    LabeledContent("Deletion URL".localized(), value: deletion)
                }
            }
            .font(.system(size: 12))
            ForEach(model.issues, id: \.message) { issue in
                Label(issue.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            if let result = model.testResult {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Test".localized()) { model.test() }
                    .disabled(!model.issues.isEmpty)
                Button("Edit".localized()) { onFinish(.edit(draft)) }
                Spacer()
                Button("Save".localized()) { onFinish(.save(draft)) }
                    .adaptiveGlassButtonStyle(prominent: true)
                    .disabled(!model.issues.isEmpty)
                    .accessibilityIdentifier("assistant.save")
            }
            .controlSize(.small)
        }
        .padding(12)
        .adaptiveGlass(cornerRadius: 16)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Describe your service…".localized(), text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .focused($inputFocused)
                .onSubmit { model.send() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .adaptiveGlass(cornerRadius: 18)
                .accessibilityIdentifier("assistant.input")
            Button {
                model.send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Circle().fill(Color.accentColor))
            .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.isResponding)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("assistant.send")
        }
        .padding(12)
    }
}
