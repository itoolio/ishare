import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct UploaderSettingsView: View {
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.uploadType) var uploadType
    @Default(.uploadDestination) var uploadDestination

    @State private var editor: UploaderEditorTarget?
    @State private var isImportSheetPresented = false
    @State private var isAssistantPresented = false
    @State private var testingID: UUID?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                if CustomUploader.allCases.isEmpty {
                    Text("You have no saved uploaders".localized())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(CustomUploader.allCases) { uploader in
                        row(for: uploader)
                    }
                }
            } header: {
                Text("Custom Uploaders".localized())
            } footer: {
                HStack {
                    Menu {
                        Button("Custom HTTP uploader".localized()) { editor = .new(.custom) }
                        Button("S3-compatible storage".localized()) { editor = .new(.s3) }
                    } label: {
                        Label("Create".localized(), systemImage: "plus")
                    }
                    .fixedSize()
                    .accessibilityIdentifier("uploaders.create")
                    Button {
                        isImportSheetPresented = true
                    } label: {
                        Label("Import".localized(), systemImage: "square.and.arrow.down")
                    }
                    if UploaderAssistantAvailability.isAvailable {
                        Button {
                            isAssistantPresented = true
                        } label: {
                            Label("Assistant".localized(), systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("uploaders.assistant")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text("Clear All".localized())
                    }
                    .disabled(CustomUploader.allCases.isEmpty)
                }
                .padding(.top, 6)
            }

            Section {
                LabeledContent("Shortcuts".localized()) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "shortcuts://")!)
                    } label: {
                        Label("Open Shortcuts".localized(), systemImage: "square.2.layers.3d")
                    }
                }
                Text("Every uploader is available in the Shortcuts app as an “Upload with ishare” action.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts".localized())
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { target in
            UploaderEditorView(target: target) { saved in
                save(saved)
                editor = nil
            } onCancel: {
                editor = nil
            }
            .frame(width: 560, height: 600)
        }
        .sheet(isPresented: $isImportSheetPresented) {
            ImportCustomUploaderView()
                .frame(width: 380, height: 300)
        }
        .sheet(isPresented: $isAssistantPresented) {
            UploaderAssistantSheet { generated in
                isAssistantPresented = false
                if let generated {
                    editor = .edit(generated)
                }
            }
            .frame(width: 580, height: 620)
        }
        .confirmationDialog("Remove all uploaders?".localized(), isPresented: $confirmClear) {
            Button("Clear All".localized(), role: .destructive) { clearAllUploaders() }
        }
    }

    private func row(for uploader: CustomUploader) -> some View {
        HStack(spacing: 10) {
            Image(systemName: uploader.kind == .s3 ? "externaldrive.connected.to.line.below" : "server.rack")
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill((uploader.kind == .s3 ? Color.orange : Color.teal).gradient))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(uploader.name)
                        .font(.system(size: 13, weight: .medium))
                    if uploader.id == activeCustomUploader, uploadType == .CUSTOM {
                        Text("Active".localized())
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                }
                Text(subtitle(for: uploader))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if testingID == uploader.id {
                ProgressView().controlSize(.small)
            }
            Group {
                iconButton("checkmark.circle", help: "Use") { activate(uploader) }
                iconButton("paperplane", help: "Test Uploader") { test(uploader) }
                iconButton("pencil", help: "Edit Uploader") { editor = .edit(uploader) }
                iconButton("square.and.arrow.up", help: "Export Uploader") { export(uploader) }
                iconButton("trash", help: "Delete Uploader") { delete(uploader) }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Duplicate".localized()) { save(uploader.withID(UUID())) }
        }
    }

    private func subtitle(for uploader: CustomUploader) -> String {
        if let s3 = uploader.s3, uploader.kind == .s3 {
            return "\(s3.bucket) · \(s3.endpointURL?.host() ?? s3.endpoint)"
        }
        return uploader.requestURL
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help.localized())
    }

    private func save(_ uploader: CustomUploader) {
        var uploaders = savedCustomUploaders ?? []
        uploaders.remove(uploader)
        uploaders.insert(uploader)
        savedCustomUploaders = uploaders
    }

    private func activate(_ uploader: CustomUploader) {
        activeCustomUploader = uploader.id
        uploadType = .CUSTOM
        uploadDestination = .custom(uploader.id)
    }

    private func delete(_ uploader: CustomUploader) {
        savedCustomUploaders = (savedCustomUploaders ?? []).filter { $0.id != uploader.id }
        if uploader.id == activeCustomUploader {
            activeCustomUploader = nil
            uploadType = .IMGUR
            uploadDestination = .builtIn(.IMGUR)
        }
    }

    private func clearAllUploaders() {
        savedCustomUploaders = nil
        activeCustomUploader = nil
        uploadType = .IMGUR
        uploadDestination = .builtIn(.IMGUR)
    }

    private func test(_ uploader: CustomUploader) {
        guard let icon = NSImage(named: NSImage.applicationIconName),
              let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "ishare-test-\(UUID().uuidString.prefix(8)).png")
        try? png.write(to: fileURL)
        testingID = uploader.id
        Task { @MainActor in
            let alert = NSAlert()
            do {
                let outcome = try await UploadService.upload(fileURL: fileURL, to: .custom(uploader))
                alert.alertStyle = .informational
                alert.messageText = "Upload Successful".localized()
                alert.informativeText = outcome.url.absoluteString
            } catch {
                alert.alertStyle = .critical
                alert.messageText = "Upload Error".localized()
                alert.informativeText = error.localizedDescription
            }
            testingID = nil
            try? FileManager.default.removeItem(at: fileURL)
            alert.runModal()
        }
    }

    private func export(_ uploader: CustomUploader) {
        guard let data = try? uploader.toJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iscu") ?? .json]
        panel.nameFieldStringValue = "\(uploader.name).iscu"
        Task { @MainActor in
            if await panel.beginAsyncModal() == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}

enum UploaderEditorTarget: Identifiable {
    case new(UploaderKind)
    case edit(CustomUploader)

    var id: String {
        switch self {
        case let .new(kind): "new-\(kind.rawValue)"
        case let .edit(uploader): uploader.id.uuidString
        }
    }
}

struct UploaderEditorView: View {
    let target: UploaderEditorTarget
    let onSave: (CustomUploader) -> Void
    let onCancel: () -> Void

    @State private var id = UUID()
    @State private var kind: UploaderKind = .custom
    @State private var name = ""
    @State private var requestURL = ""
    @State private var responseURL = ""
    @State private var deletionURL = ""
    @State private var fileFormName = ""
    @State private var bodyType: RequestBodyType = .multipartFormData
    @State private var deleteMethod: DeleteRequestType = .get
    @State private var headers: [CustomEntryModel] = []
    @State private var formData: [CustomEntryModel] = []
    @State private var endpoint = ""
    @State private var region = "us-east-1"
    @State private var bucket = ""
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
    @State private var pathStyle = true
    @State private var keyTemplate = "{{date}}/{{uuid}}.{{ext}}"
    @State private var acl = ""
    @State private var publicURL = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name".localized(), text: $name)
                        .accessibilityIdentifier("uploaderEditor.name")
                    Picker("Type".localized(), selection: $kind) {
                        Text("Custom HTTP uploader".localized()).tag(UploaderKind.custom)
                        Text("S3-compatible storage".localized()).tag(UploaderKind.s3)
                    }
                }
                if kind == .custom {
                    customSections
                } else {
                    s3Sections
                }
                if !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.message) { issue in
                            Label(issue.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel".localized(), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save".localized()) { onSave(build()) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!issues.isEmpty)
                    .accessibilityIdentifier("uploaderEditor.save")
            }
            .padding(14)
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var customSections: some View {
        Section("Request".localized()) {
            TextField("Request URL*".localized(), text: $requestURL, prompt: Text("https://example.com/upload"))
            Picker("Body".localized(), selection: $bodyType) {
                Text("Multipart form data".localized()).tag(RequestBodyType.multipartFormData)
                Text("Binary".localized()).tag(RequestBodyType.binary)
            }
            if bodyType == .multipartFormData {
                TextField("File Form Name".localized(), text: $fileFormName, prompt: Text("file"))
            }
        }
        Section("Response".localized()) {
            TextField("Response URL*".localized(), text: $responseURL, prompt: Text("{{data.url}}"))
            TextField("Deletion URL".localized(), text: $deletionURL, prompt: Text("{{data.deleteUrl}}"))
            Picker("Deletion method".localized(), selection: $deleteMethod) {
                Text("GET").tag(DeleteRequestType.get)
                Text("DELETE").tag(DeleteRequestType.delete)
            }
            Text("Use {{path.to.value}} to insert values from the JSON response, or {{response}} for a plain-text response.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        EntrySection(title: "Headers", entries: $headers)
        if bodyType == .multipartFormData {
            EntrySection(title: "Form Data", entries: $formData)
        }
    }

    @ViewBuilder
    private var s3Sections: some View {
        Section("Bucket".localized()) {
            TextField("Endpoint".localized(), text: $endpoint, prompt: Text("https://s3.us-east-1.amazonaws.com"))
            TextField("Region".localized(), text: $region, prompt: Text("us-east-1"))
            TextField("Bucket".localized(), text: $bucket)
            Toggle("Path-style URLs".localized(), isOn: $pathStyle)
        }
        Section("Credentials".localized()) {
            TextField("Access key ID".localized(), text: $accessKeyId)
            SecureField("Secret access key".localized(), text: $secretAccessKey)
        }
        Section("Objects".localized()) {
            TextField("Key template".localized(), text: $keyTemplate)
            TextField("ACL".localized(), text: $acl, prompt: Text("public-read"))
            TextField("Public URL".localized(), text: $publicURL, prompt: Text("https://cdn.example.com/{{key}}"))
            Text("Key placeholders: {{filename}}, {{name}}, {{ext}}, {{uuid}}, {{random}}, {{timestamp}}, {{date}}. Public URL placeholders: {{key}}, {{bucket}}, {{region}}, {{host}}, {{endpoint}}.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var issues: [UploaderIssue] {
        UploaderValidator.issues(for: build())
    }

    private func load() {
        switch target {
        case let .new(newKind):
            kind = newKind
        case let .edit(uploader):
            id = uploader.id
            kind = uploader.kind
            name = uploader.name
            requestURL = uploader.requestURL
            responseURL = uploader.responseURL
            deletionURL = uploader.deletionURL ?? ""
            fileFormName = uploader.fileFormName ?? ""
            bodyType = uploader.requestBodyType ?? .multipartFormData
            deleteMethod = uploader.deleteRequestType ?? .get
            headers = (uploader.headers ?? [:]).sorted { $0.key < $1.key }.map { CustomEntryModel(key: $0.key, value: $0.value) }
            formData = (uploader.formData ?? [:]).sorted { $0.key < $1.key }.map { CustomEntryModel(key: $0.key, value: $0.value) }
            if let s3 = uploader.s3 {
                endpoint = s3.endpoint
                region = s3.region
                bucket = s3.bucket
                accessKeyId = s3.accessKeyId
                secretAccessKey = s3.secretAccessKey
                pathStyle = s3.usesPathStyle
                keyTemplate = s3.keyTemplate ?? ""
                acl = s3.acl ?? ""
                publicURL = s3.publicURL ?? ""
            }
        }
    }

    private func dictionary(_ entries: [CustomEntryModel]) -> [String: String]? {
        let pairs = entries.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !pairs.isEmpty else { return nil }
        return Dictionary(pairs.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func build() -> CustomUploader {
        switch kind {
        case .s3:
            return .s3(id: id, name: name, configuration: S3Configuration(
                endpoint: endpoint, region: region, bucket: bucket, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey,
                pathStyle: pathStyle, keyTemplate: nonEmpty(keyTemplate), acl: nonEmpty(acl), publicURL: nonEmpty(publicURL)
            ))
        case .custom:
            return CustomUploader(
                id: id, name: name, requestURL: requestURL.trimmingCharacters(in: .whitespaces),
                headers: dictionary(headers), formData: bodyType == .multipartFormData ? dictionary(formData) : nil,
                fileFormName: bodyType == .multipartFormData ? nonEmpty(fileFormName) : nil,
                requestBodyType: bodyType, responseURL: responseURL.trimmingCharacters(in: .whitespaces),
                deletionURL: nonEmpty(deletionURL), deleteRequestType: nonEmpty(deletionURL) == nil ? nil : deleteMethod
            )
        }
    }
}

struct EntrySection: View {
    let title: String
    @Binding var entries: [CustomEntryModel]

    var body: some View {
        Section {
            ForEach($entries) { $entry in
                HStack {
                    TextField("Name".localized(), text: $entry.key)
                        .font(.system(.body, design: .monospaced))
                    TextField("Value".localized(), text: $entry.value)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            HStack {
                Text(title.localized())
                Spacer()
                Button {
                    entries.append(CustomEntryModel(key: "", value: ""))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct ImportCustomUploaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.uploadType) var uploadType
    @Default(.uploadDestination) var uploadDestination
    @State private var importError: ImportError?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Import Custom Uploader".localized())
                .font(.title3.weight(.semibold))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Drag and drop .iscu files here or click to select".localized())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: choose)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in importUploader(from: url) }
                    }
                    return true
                }
            Button("Cancel".localized()) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .alert(item: $importError) { error in
            Alert(title: Text("Error".localized()), message: Text(error.localizedDescription), dismissButton: .default(Text("OK".localized())))
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "iscu") ?? .json, .json]
        Task { @MainActor in
            if await panel.beginAsyncModal() == .OK, let url = panel.url {
                importUploader(from: url)
            }
        }
    }

    private func importUploader(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let uploader = try CustomUploader.fromJSON(Data(contentsOf: url))
            var uploaders = savedCustomUploaders ?? []
            uploaders.remove(uploader)
            uploaders.insert(uploader)
            savedCustomUploaders = uploaders
            activeCustomUploader = uploader.id
            uploadType = .CUSTOM
            uploadDestination = .custom(uploader.id)
            dismiss()
        } catch {
            importError = ImportError(error: error)
        }
    }
}

struct ImportError: Identifiable {
    let id = UUID()
    let error: any Error

    var localizedDescription: String {
        error.localizedDescription
    }
}

struct CustomEntryModel: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}
