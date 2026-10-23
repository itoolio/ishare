import Defaults
import ishareCore
import SwiftUI

struct UploaderSettingsView: View {
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.savedLocalUploaders) var savedLocalUploaders
    @Default(.uploadType) var uploadType
    @Default(.uploadDestination) var uploadDestination

    @State var editor: UploaderEditorTarget?
    @State private var isImportSheetPresented = false
    @State private var isAssistantPresented = false
    @State var testedUploader: CustomUploader?
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
                        Button("WebDAV".localized()) { editor = .new(.webdav) }
                        Button("SFTP".localized()) { editor = .new(.sftp) }
                        Button("GitHub".localized()) { editor = .new(.github) }
                        Divider()
                        ForEach(CloudProvider.allCases.filter(\.hasBuiltInClientID), id: \.self) { provider in
                            Button(provider.title.localized()) { editor = .new(provider.kind) }
                        }
                        let ownAppProviders = CloudProvider.allCases.filter { !$0.hasBuiltInClientID }
                        if !ownAppProviders.isEmpty {
                            Menu("With your own app".localized()) {
                                ForEach(ownAppProviders, id: \.self) { provider in
                                    Button(provider.title.localized()) { editor = .new(provider.kind) }
                                }
                            }
                        }
                        Divider()
                        Button("Folder".localized()) { editor = .new(.folder) }
                        Button("iCloud Drive folder".localized()) { editor = .iCloudDrive }
                        Button("Photos".localized()) { editor = .new(.photos) }
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

            UploadBehaviorSettings()
            ImageUploadSettings()
            WebhookSettings()
            URLShortenerSettings()
            UploadPresetsSettings()
            WatchFolderSettings()
            UploadQueueSettings()
            UploadStatisticsSettings()

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
        .sheet(item: $testedUploader) { uploader in
            UploadTestSheet(uploader: uploader) { testedUploader = nil }
                .frame(width: 560, height: 560)
        }
        .sheet(isPresented: $isImportSheetPresented) {
            ImportCustomUploaderView()
                .frame(width: 380, height: 300)
        }
        .sheet(isPresented: $isAssistantPresented) {
            UploaderAssistantSheet { outcome in
                isAssistantPresented = false
                switch outcome {
                case let .save(uploader):
                    save(uploader)
                    activate(uploader)
                case let .edit(uploader):
                    editor = .edit(uploader)
                case nil:
                    break
                }
            }
            .frame(width: 560, height: 640)
        }
        .confirmationDialog("Remove all uploaders?".localized(), isPresented: $confirmClear) {
            Button("Clear All".localized(), role: .destructive) { clearAllUploaders() }
        }
    }
}

extension UploaderSettingsView: SettingsSearchable {
    static let searchEntries: [SettingsSearchEntry] = [
        ImageUploadSettings.optimization, ImageUploadSettings.metadata, WebhookSettings.entry,
        SettingsSearchEntry(
            "Upload", pane: .uploaders,
            keywords: [
                "Uploader", "Destination", "Imgur", "Custom uploader", "Server", "S3", "R2", "ISCU", "Import", "Export",
                "Assistant", "Apple Intelligence", "Delete", "Deletion URL", "Headers",
                "WebDAV", "SFTP", "SSH", "Host key", "Fingerprint", "Dropbox", "Google Drive", "OneDrive", "GitHub", "Gist",
                "Personal access token", "Sign in",
            ]),
        SettingsSearchEntry(
            "Also upload to", pane: .uploaders,
            keywords: [
                "Copy URL after upload", "Open URL in browser after upload", "Watch Folder", "Folder", "Upload Queue",
                "Retry", "Expiring links", "Presigned", "ShareX", "SXCU", "Test Upload", "Method",
            ]),
        SettingsSearchEntry(
            "Upload Presets", pane: .uploaders,
            keywords: [
                "Preset", "URL Shortener", "Shorten", "Short link", "is.gd", "v.gd",
            ]),
        SettingsSearchEntry(
            "Upload Statistics", pane: .uploaders,
            keywords: [
                "Statistics", "Stats", "Upload duration", "Failure rate", "Percentile", "CSV", "Reset statistics",
            ]),
    ]
}
