import ishareCore
import SwiftUI

enum UploaderEditorTarget: Identifiable {
    case new(UploaderKind)
    case iCloudDrive
    case edit(CustomUploader)

    var id: String {
        switch self {
        case let .new(kind): "new-\(kind.rawValue)"
        case .iCloudDrive: "new-icloud-drive"
        case let .edit(uploader): uploader.id.uuidString
        }
    }
}

struct UploaderEditorView: View {
    let target: UploaderEditorTarget
    let onSave: (CustomUploader) -> Void
    let onCancel: () -> Void

    @State var id = UUID()
    @State var kind: UploaderKind = .custom
    @State var name = ""
    @State var requestURL = ""
    @State var responseURL = ""
    @State var deletionURL = ""
    @State var fileFormName = ""
    @State var bodyType: RequestBodyType = .multipartFormData
    @State var deleteMethod: DeleteRequestType = .get
    @State var headers: [CustomEntryModel] = []
    @State var formData: [CustomEntryModel] = []
    @State var endpoint = ""
    @State var region = "us-east-1"
    @State var bucket = ""
    @State var accessKeyId = ""
    @State var secretAccessKey = ""
    @State var pathStyle = true
    @State var keyTemplate = "{{date}}/{{uuid}}.{{ext}}"
    @State var acl = ""
    @State var publicURL = ""
    @State var requestMethod: UploadRequestMethod = .post
    @State var expiringLinks = false
    @State var presignedExpiry = 86400
    @State var testedUploader: CustomUploader?
    @State var linkDraft = LinkOptionsDraft()
    @State var linkPreferences = LinkOptionPreferences()
    @State var defaultLinkPassword = ""
    @State var folderDraft = FolderDraft()
    @State var photosDraft = PhotosDraft()
    @State var suggestsICloudDrive = false
    @State var webdavDraft = WebDAVDraft()
    @State var sftpDraft = SFTPDraft()
    @State var cloudDraft = CloudDraft()
    @State var githubDraft = GitHubDraft()
    @State var optimizationOverride = ImageOptimizationOverride()
    @State var linkRewriteDraft = LinkRewriteDraft()
    @State var autoDeletePreset: AutoDeletePreset = .off
    @State var autoDeleteCustomDays = 14

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name".localized(), text: $name)
                        .accessibilityIdentifier("uploaderEditor.name")
                    Picker("Type".localized(), selection: $kind) {
                        ForEach(UploaderKind.allCases, id: \.self) { Text($0.titleKey.localized()).tag($0) }
                    }
                }
                switch kind {
                case .custom:
                    customSections
                case .s3:
                    s3Sections
                case .folder:
                    FolderDestinationSection(draft: $folderDraft, suggestsICloudDrive: suggestsICloudDrive)
                case .photos:
                    PhotosDestinationSection(draft: $photosDraft)
                case .webdav:
                    WebDAVSections(draft: $webdavDraft)
                case .sftp:
                    SFTPSections(draft: $sftpDraft)
                case .dropbox, .googleDrive, .oneDrive:
                    if let provider = kind.cloudProvider {
                        CloudSections(provider: provider, uploaderID: id, draft: $cloudDraft)
                    }
                case .github:
                    GitHubSections(draft: $githubDraft)
                }
                if kind != .photos {
                    ImageOptimizationOverrideSection(override: $optimizationOverride)
                }
                maintenanceSections
                if case let .edit(uploader) = target {
                    UploaderStatisticsSection(key: uploader.id.uuidString)
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
                Button("Test Upload".localized()) { testedUploader = build() }
                    .disabled(!issues.isEmpty)
                Button("Save".localized(), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!issues.isEmpty)
                    .accessibilityIdentifier("uploaderEditor.save")
            }
            .padding(14)
        }
        .onAppear(perform: load)
        .sheet(item: $testedUploader) { uploader in
            UploadTestSheet(uploader: uploader) { testedUploader = nil }
                .frame(width: 540, height: 520)
        }
    }

}
