import Defaults
import Foundation
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

struct AssistantAnswers: Equatable, Sendable {
    var service = ""
    var endpoint = ""
    var authHeaderName = ""
    var authHeaderValue = ""
    var fileFieldName = ""
    var exampleResponse = ""
    var notes = ""

    var prompt: String {
        var lines = ["Build an ishare custom uploader."]
        if !service.isEmpty { lines.append("Service: \(service)") }
        if !endpoint.isEmpty { lines.append("Upload endpoint: \(endpoint)") }
        if !authHeaderName.isEmpty { lines.append("Authentication header name: \(authHeaderName)") }
        if !fileFieldName.isEmpty { lines.append("Multipart file field name: \(fileFieldName)") }
        if !exampleResponse.isEmpty { lines.append("Example JSON response after a successful upload:\n\(exampleResponse)") }
        if !notes.isEmpty { lines.append("Additional notes from the user:\n\(notes)") }
        return lines.joined(separator: "\n")
    }
}

struct GeneratedUploaderSpec: Equatable, Sendable {
    var name: String
    var requestURL: String
    var bodyType: String
    var fileFormName: String
    var headerNames: [String]
    var headerValues: [String]
    var formFieldNames: [String]
    var formFieldValues: [String]
    var responseURL: String
    var deletionURL: String
    var deletionMethod: String
}

enum UploaderAssistantMapper {
    static func template(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("{{") || trimmed.lowercased().hasPrefix("http") {
            return trimmed
        }
        let path = trimmed.hasPrefix("$.") ? String(trimmed.dropFirst(2)) : trimmed
        return "{{\(path)}}"
    }

    static func uploader(from spec: GeneratedUploaderSpec, answers: AssistantAnswers) -> CustomUploader {
        var headers: [String: String] = [:]
        for (name, value) in zip(spec.headerNames, spec.headerValues) where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            headers[name] = value
        }
        let authName = answers.authHeaderName.trimmingCharacters(in: .whitespaces)
        if !authName.isEmpty {
            headers = headers.filter { $0.key.lowercased() != authName.lowercased() }
            headers[authName] = answers.authHeaderValue
        }
        var formData: [String: String] = [:]
        for (name, value) in zip(spec.formFieldNames, spec.formFieldValues) where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            formData[name] = value
        }
        let isBinary = spec.bodyType.lowercased().contains("binary") || spec.bodyType.lowercased() == "raw"
        let endpoint = answers.endpoint.trimmingCharacters(in: .whitespaces)
        let fileField = answers.fileFieldName.trimmingCharacters(in: .whitespaces).isEmpty ? spec.fileFormName : answers.fileFieldName
        let deletion = template(spec.deletionURL)
        let name = spec.name.trimmingCharacters(in: .whitespaces).isEmpty ? answers.service : spec.name
        return CustomUploader(
            name: name.isEmpty ? "Uploader" : name,
            requestURL: endpoint.isEmpty ? spec.requestURL.trimmingCharacters(in: .whitespaces) : endpoint,
            headers: headers.isEmpty ? nil : headers,
            formData: isBinary || formData.isEmpty ? nil : formData,
            fileFormName: isBinary || fileField.trimmingCharacters(in: .whitespaces).isEmpty ? nil : fileField.trimmingCharacters(in: .whitespaces),
            requestBodyType: isBinary ? .binary : .multipartFormData,
            responseURL: template(spec.responseURL),
            deletionURL: deletion.isEmpty ? nil : deletion,
            deleteRequestType: deletion.isEmpty ? nil : (spec.deletionMethod.uppercased() == "DELETE" ? .delete : .get)
        )
    }
}

enum UploaderAssistantAvailability {
    static var isAvailable: Bool {
        if ScreenshotMode.isActive {
            return true
        }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }
}

enum AssistantError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Apple Intelligence is not available on this Mac"
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
        @Guide(description: "Names of extra HTTP headers the service requires, excluding Content-Type")
        var headerNames: [String]
        @Guide(description: "Values of the extra HTTP headers, in the same order as headerNames. Use placeholders like YOUR_API_KEY for secrets")
        var headerValues: [String]
        @Guide(description: "Names of extra multipart text fields, if any")
        var formFieldNames: [String]
        @Guide(description: "Values of the extra multipart text fields, in the same order as formFieldNames")
        var formFieldValues: [String]
        @Guide(description: "Template for the public file URL. Wrap JSON paths from the response in double braces, for example {{data.url}} or {{files[0].url}}")
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
    @MainActor
    final class FoundationModelsUploaderGenerator {
        static let instructions = """
        You help people configure ishare, a macOS screenshot tool, to upload files to their own web service.
        ishare sends one HTTP POST per file, either as multipart/form-data or as the raw file body, and reads the public URL from the JSON response.
        Response templates use double braces around JSON paths, such as {{url}}, {{data.link}} or {{files[0].url}}.
        Use {{response}} when the service answers with the URL as plain text.
        Never invent secrets; use placeholders such as YOUR_API_KEY when a value is unknown.
        """

        private let session = LanguageModelSession(instructions: instructions)

        func generate(_ prompt: String) async throws -> GeneratedUploaderSpec {
            try await session.respond(to: prompt, generating: GenerableUploader.self).content.spec
        }
    }
#endif

@MainActor
final class UploaderAssistantModel: ObservableObject {
    @Published var answers = AssistantAnswers()
    @Published var refinement = ""
    @Published var result: CustomUploader?
    @Published var isGenerating = false
    @Published var errorMessage: String?
    private var generator: AnyObject?

    var issues: [UploaderIssue] {
        result.map(UploaderValidator.issues(for:)) ?? []
    }

    func generate(refining: Bool = false) {
        let prompt = refining && !refinement.isEmpty
            ? "Update the previous uploader. \(refinement)"
            : answers.prompt
        isGenerating = true
        errorMessage = nil
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let spec = try await run(prompt)
                result = UploaderAssistantMapper.uploader(from: spec, answers: answers)
                refinement = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func run(_ prompt: String) async throws -> GeneratedUploaderSpec {
        if ScreenshotMode.isActive {
            return ScreenshotMode.sampleAssistantSpec
        }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let generator = (self.generator as? FoundationModelsUploaderGenerator) ?? FoundationModelsUploaderGenerator()
                self.generator = generator
                return try await generator.generate(prompt)
            }
        #endif
        throw AssistantError.unavailable
    }
}

struct UploaderAssistantSheet: View {
    @StateObject private var model = UploaderAssistantModel()
    let onFinish: (CustomUploader?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uploader Assistant".localized())
                        .font(.headline)
                    Text("Answer a few questions and Apple Intelligence builds the uploader on your Mac.".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Form {
                Section("Service".localized()) {
                    TextField("Which service do you upload to?".localized(), text: $model.answers.service, prompt: Text("Zipline, Chibisafe, my own server…"))
                        .accessibilityIdentifier("assistant.service")
                    TextField("Upload endpoint".localized(), text: $model.answers.endpoint, prompt: Text("https://example.com/api/upload"))
                }
                Section("Authentication".localized()) {
                    TextField("Header name".localized(), text: $model.answers.authHeaderName, prompt: Text("Authorization"))
                    SecureField("Header value".localized(), text: $model.answers.authHeaderValue)
                    TextField("File field name".localized(), text: $model.answers.fileFieldName, prompt: Text("file"))
                }
                if !ScreenshotMode.isActive || model.result == nil {
                Section("Response".localized()) {
                    TextEditor(text: $model.answers.exampleResponse)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 70)
                    Text("Paste an example JSON response, API documentation or a curl command.".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Anything else?".localized(), text: $model.answers.notes, axis: .vertical)
                }
                }
                if let result = model.result {
                    Section("Result".localized()) {
                        LabeledContent("Name".localized(), value: result.name)
                        LabeledContent("Request URL*".localized(), value: result.requestURL)
                        LabeledContent("Response URL*".localized(), value: result.responseURL)
                        if let deletion = result.deletionURL {
                            LabeledContent("Deletion URL".localized(), value: deletion)
                        }
                        ForEach(model.issues, id: \.message) { issue in
                            Label(issue.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                        HStack {
                            TextField("Ask for a change…".localized(), text: $model.refinement)
                                .onSubmit { model.generate(refining: true) }
                            Button("Refine".localized()) { model.generate(refining: true) }
                                .disabled(model.refinement.isEmpty || model.isGenerating)
                        }
                    }
                }
                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel".localized(), role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.isGenerating {
                    ProgressView().controlSize(.small)
                }
                Button(model.result == nil ? "Generate".localized() : "Regenerate".localized()) { model.generate() }
                    .disabled(model.isGenerating || (model.answers.service.isEmpty && model.answers.endpoint.isEmpty))
                    .accessibilityIdentifier("assistant.generate")
                Button("Review and Save".localized()) { onFinish(model.result) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.result == nil || model.isGenerating)
            }
            .padding(14)
        }
        .onAppear {
            if ScreenshotMode.isActive {
                model.answers = ScreenshotMode.sampleAssistantAnswers
                model.result = UploaderAssistantMapper.uploader(from: ScreenshotMode.sampleAssistantSpec, answers: ScreenshotMode.sampleAssistantAnswers)
            }
        }
    }
}
