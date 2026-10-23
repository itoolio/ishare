import Defaults
import ishareCore
import KeyboardShortcuts
import SwiftUI

enum UploadDestinationOptions {
    @MainActor static var all: [(title: String, destination: UploadDestination)] {
        [("Imgur", UploadDestination.builtIn(.IMGUR))] + CustomUploader.allCases.map { ($0.name, UploadDestination.custom($0.id)) }
    }

    @MainActor static func title(for destination: UploadDestination) -> String {
        switch destination {
        case .builtIn(.IMGUR): "Imgur"
        case .builtIn(.CUSTOM): "Active uploader".localized()
        case let .custom(id): CustomUploader.allCases.first { $0.id == id }?.name ?? "Missing uploader".localized()
        case .localNetwork: "Local Network".localized()
        }
    }
}

struct URLShortenerSettings: View {
    @Default(.urlShortener) var urlShortener

    var body: some View {
        Section {
            ShortenerPicker(title: "Shorten URLs with".localized(), configuration: $urlShortener)
        } header: {
            Text("URL Shortener".localized())
        } footer: {
            Text("The short link is copied or opened instead of the uploaded URL. History keeps both. If shortening fails, the long URL is used.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShortenerPicker: View {
    let title: String
    @Binding var configuration: URLShortenerConfiguration
    @State private var isEditingCustom = false

    var body: some View {
        Picker(title, selection: $configuration.kind) {
            ForEach(URLShortenerKind.allCases) { kind in
                Text(kind.title.localized()).tag(kind)
            }
        }
        if configuration.kind == .custom {
            LabeledContent("Custom shortener".localized()) {
                Button("Configure…".localized()) { isEditingCustom = true }
            }
            .sheet(isPresented: $isEditingCustom) {
                CustomShortenerEditor(shortener: configuration.custom) { saved in
                    configuration.custom = saved
                    isEditingCustom = false
                } onCancel: {
                    isEditingCustom = false
                }
                .frame(width: 520, height: 520)
            }
        }
    }
}

struct CustomShortenerEditor: View {
    let onSave: (CustomShortener) -> Void
    let onCancel: () -> Void

    @State private var requestURL: String
    @State private var method: ShortenerRequestMethod
    @State private var headers: [CustomEntryModel]
    @State private var requestBody: String
    @State private var responseTemplate: String

    init(shortener: CustomShortener, onSave: @escaping (CustomShortener) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _requestURL = State(initialValue: shortener.requestURL)
        _method = State(initialValue: shortener.method)
        _headers = State(initialValue: shortener.headers.sorted { $0.key < $1.key }.map { CustomEntryModel(key: $0.key, value: $0.value) })
        _requestBody = State(initialValue: shortener.body)
        _responseTemplate = State(initialValue: shortener.responseTemplate)
    }

    private var shortener: CustomShortener {
        CustomShortener(
            requestURL: requestURL.trimmingCharacters(in: .whitespaces),
            method: method,
            headers: Dictionary(headers.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last }),
            body: requestBody,
            responseTemplate: responseTemplate
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Request URL".localized(), text: $requestURL, prompt: Text(verbatim: "https://example.com/api?url={{url_encoded}}"))
                        .font(.system(.body, design: .monospaced))
                    Picker("Method".localized(), selection: $method) {
                        ForEach(ShortenerRequestMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                } header: {
                    Text("Request".localized())
                } footer: {
                    Text("Use {{url}} for the uploaded URL or {{url_encoded}} for it percent-encoded.".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                EntrySection(title: "Headers", entries: $headers)
                if method == .post {
                    Section("Body".localized()) {
                        TextEditor(text: $requestBody)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 60)
                    }
                }
                Section {
                    TextField("Short URL".localized(), text: $responseTemplate, prompt: Text(verbatim: "{{response}}"))
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Response".localized())
                } footer: {
                    Text("Use {{response}} for a plain-text reply or a JSON path such as {{data.short}}.".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel".localized(), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save".localized()) { onSave(shortener) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(requestURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }
}

struct UploadPresetsSettings: View {
    @Default(.uploadPresets) var presets
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.savedLocalUploaders) var savedLocalUploaders
    @State private var editing: UploadPreset?
    @State private var pendingDeletion: UploadPreset?

    var body: some View {
        Section {
            if presets.isEmpty {
                Text("You have no upload presets".localized())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(presets) { preset in
                    row(for: preset)
                }
                .onMove(perform: UploadPresets.move)
            }
        } header: {
            Text("Upload Presets".localized())
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("A preset bundles a destination, extra destinations, a URL shortener and after-capture overrides. Give it a shortcut to capture a region with it.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    editing = UploadPreset(name: "", destination: Defaults[.uploadDestination])
                } label: {
                    Label("Add Preset".localized(), systemImage: "plus")
                }
            }
            .padding(.top, 6)
        }
        .sheet(item: $editing) { preset in
            UploadPresetEditor(preset: preset) { saved in
                UploadPresets.save(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
            .frame(width: 540, height: 620)
        }
        .confirmationDialog(
            String(format: "Delete “%@”?".localized(), pendingDeletion?.name ?? ""),
            isPresented: Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } }
        ) {
            Button("Delete".localized(), role: .destructive) {
                if let pendingDeletion { UploadPresets.delete(pendingDeletion) }
                pendingDeletion = nil
            }
        }
    }

    private func row(for preset: UploadPreset) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.indigo.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                Text(UploadDestinationOptions.title(for: preset.destination))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let shortcut = KeyboardShortcuts.getShortcut(for: preset.shortcutName) {
                Text(shortcut.description)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Edit…".localized()) { editing = preset }
                Button("Move Up".localized()) { move(preset, by: -1) }
                    .disabled(presets.first?.id == preset.id)
                Button("Move Down".localized()) { move(preset, by: 1) }
                    .disabled(presets.last?.id == preset.id)
                Divider()
                Button("Delete".localized(), role: .destructive) { pendingDeletion = preset }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .helpAndAccessibilityLabel("More".localized())
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = preset }
    }

    private func move(_ preset: UploadPreset, by offset: Int) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        let target = index + offset
        guard presets.indices.contains(target) else { return }
        UploadPresets.move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
    }
}

struct UploadPresetEditor: View {
    let onSave: (UploadPreset) -> Void
    let onCancel: () -> Void
    @State private var preset: UploadPreset

    init(preset: UploadPreset, onSave: @escaping (UploadPreset) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _preset = State(initialValue: preset)
    }

    private var trimmedName: String {
        preset.name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name".localized(), text: $preset.name, prompt: Text("Work S3".localized()))
                    Picker("Upload to".localized(), selection: $preset.destination) {
                        ForEach(UploadDestinationOptions.all, id: \.destination) { entry in
                            Text(entry.title).tag(entry.destination)
                        }
                    }
                    KeyboardShortcuts.Recorder("Shortcut:".localized(), name: preset.shortcutName)
                }
                Section("Also upload to".localized()) {
                    ForEach(UploadDestinationOptions.all.filter { $0.destination != preset.destination }, id: \.destination) { entry in
                        Toggle(entry.title, isOn: additionalBinding(for: entry.destination))
                    }
                }
                Section("URL Shortener".localized()) {
                    Toggle("Use the default shortener".localized(), isOn: usesDefaultShortener)
                    if preset.shortener != nil {
                        ShortenerPicker(title: "Shorten URLs with".localized(), configuration: shortenerBinding)
                    }
                }
                Section {
                    ForEach(AfterCaptureStep.allCases) { step in
                        Picker(selection: overrideBinding(for: step)) {
                            Text("Default".localized()).tag(Bool?.none)
                            Text("On".localized()).tag(Bool?.some(true))
                            Text("Off".localized()).tag(Bool?.some(false))
                        } label: {
                            Label(step.title.localized(), systemImage: step.symbol)
                        }
                    }
                } header: {
                    Text("After Capture".localized())
                } footer: {
                    Text("Default follows your After Capture settings. Uploading is on for presets unless you turn it off here.".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel".localized(), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save".localized()) {
                    var saved = preset
                    saved.name = trimmedName
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding()
        }
    }

    private func additionalBinding(for destination: UploadDestination) -> Binding<Bool> {
        Binding {
            preset.additionalDestinations.contains(destination)
        } set: { enabled in
            preset.additionalDestinations.removeAll { $0 == destination }
            if enabled {
                preset.additionalDestinations.append(destination)
            }
        }
    }

    private var usesDefaultShortener: Binding<Bool> {
        Binding {
            preset.shortener == nil
        } set: { usesDefault in
            preset.shortener = usesDefault ? nil : Defaults[.urlShortener]
        }
    }

    private var shortenerBinding: Binding<URLShortenerConfiguration> {
        Binding {
            preset.shortener ?? .none
        } set: { configuration in
            preset.shortener = configuration
        }
    }

    private func overrideBinding(for step: AfterCaptureStep) -> Binding<Bool?> {
        Binding {
            preset.override(for: step)
        } set: { value in
            preset.setOverride(value, for: step)
        }
    }
}

struct UploadPresetKeybindSection: View {
    @Default(.uploadPresets) var presets

    var body: some View {
        if !presets.isEmpty {
            Section("Upload Presets".localized()) {
                ForEach(presets) { preset in
                    KeyboardShortcuts.Recorder(preset.name + ":", name: preset.shortcutName)
                }
            }
        }
    }
}
