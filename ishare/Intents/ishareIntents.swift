import AppIntents
import Defaults
import Foundation
import UniformTypeIdentifiers

struct UploaderEntity: AppEntity, Identifiable, Hashable {
    static let imgurID = "imgur"
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Uploader" }
    static var defaultQuery: UploaderQuery { UploaderQuery() }

    let id: String
    let name: String
    let kind: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kind)")
    }

    static let imgur = UploaderEntity(id: imgurID, name: "Imgur", kind: "Imgur")

    init(id: String, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    init(_ uploader: CustomUploader) {
        id = uploader.id.uuidString
        name = uploader.name
        kind = uploader.kind == .s3 ? "S3" : "Custom"
    }

    @MainActor static var all: [UploaderEntity] {
        [.imgur] + CustomUploader.allCases.map(UploaderEntity.init)
    }

    @MainActor var target: UploadTarget? {
        if id == Self.imgurID {
            return .imgur(clientID: Defaults[.imgurClientId])
        }
        return UploadCoordinator.target(forUploaderID: UUID(uuidString: id))
    }
}

struct UploaderQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UploaderEntity.ID]) async throws -> [UploaderEntity] {
        UploaderEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [UploaderEntity] {
        UploaderEntity.all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [UploaderEntity] {
        UploaderEntity.all
    }
}

enum CaptureKindEnum: String, AppEnum {
    case region
    case window
    case screen
    case scrolling

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Capture Type" }
    static var caseDisplayRepresentations: [CaptureKindEnum: DisplayRepresentation] {
        [
            .region: DisplayRepresentation(title: "Region", image: .init(systemName: "rectangle.dashed")),
            .window: DisplayRepresentation(title: "Window", image: .init(systemName: "macwindow")),
            .screen: DisplayRepresentation(title: "Screen", image: .init(systemName: "display")),
            .scrolling: DisplayRepresentation(title: "Scrolling", image: .init(systemName: "arrow.up.and.down.text.horizontal")),
        ]
    }

    var captureType: CaptureType {
        switch self {
        case .region: .REGION
        case .window: .WINDOW
        case .screen: .SCREEN
        case .scrolling: .SCROLLING
        }
    }
}

enum IntentError: LocalizedError {
    case noUploader
    case cancelled
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .noUploader: "The selected uploader no longer exists"
        case .cancelled: "The capture was cancelled"
        case .unreadableFile: "The file could not be read"
        }
    }
}

struct UploadFileIntent: AppIntent {
    static var title: LocalizedStringResource { "Upload with ishare" }
    static var description: IntentDescription { IntentDescription("Uploads an image or video with one of your ishare uploaders and returns its URL.") }

    @Parameter(title: "File", supportedContentTypes: [.image, .movie, .gif])
    var file: IntentFile

    @Parameter(title: "Uploader")
    var uploader: UploaderEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Upload \(\.$file) with \(\.$uploader)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<URL> & ProvidesDialog {
        let fileURL = try IntentFileStaging.stage(file)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let target: UploadTarget?
        if let uploader {
            target = uploader.target
        } else {
            target = UploadCoordinator.currentTarget()
        }
        guard let target else { throw IntentError.noUploader }
        let outcome = try await UploadService.upload(fileURL: fileURL, to: target)
        UploadCoordinator.record(outcome, localFileURL: nil)
        return .result(value: outcome.url, dialog: "\(outcome.url.absoluteString)")
    }
}

struct CaptureIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture with ishare" }
    static var description: IntentDescription { IntentDescription("Takes a screenshot and returns the image. ishare runs its usual post-capture actions, such as copying and uploading.") }

    @Parameter(title: "Type", default: .region)
    var type: CaptureKindEnum

    @Parameter(title: "Upload", default: false)
    var upload: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$type)") {
            \.$upload
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let captured = await ImageCaptureFlow.capture(type: type.captureType) else { throw IntentError.cancelled }
        let fileURL = try ImageCaptureFlow.save(captured)
        let result = IntentFile(fileURL: fileURL, filename: fileURL.lastPathComponent, type: ImageEncoder.contentType(for: Defaults[.captureFileType]))
        Task { @MainActor in
            await CaptureSession.finish(fileURL: fileURL, kind: .image, options: CaptureOptions(forceUpload: upload))
        }
        return .result(value: result)
    }
}

struct RecordIntent: AppIntent {
    static var title: LocalizedStringResource { "Start or Stop Recording with ishare" }
    static var description: IntentDescription { IntentDescription("Starts a screen recording, or stops the one in progress.") }

    @Parameter(title: "Region", default: false)
    var region: Bool

    @Parameter(title: "GIF", default: false)
    var gif: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureSession.toggleRecording(gif: gif, region: region)
        return .result()
    }
}

struct SetUploaderIntent: AppIntent {
    static var title: LocalizedStringResource { "Set ishare Uploader" }
    static var description: IntentDescription { IntentDescription("Chooses where ishare uploads captures.") }

    @Parameter(title: "Uploader")
    var uploader: UploaderEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Upload with \(\.$uploader)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if uploader.id == UploaderEntity.imgurID {
            Defaults[.uploadType] = .IMGUR
            Defaults[.activeCustomUploader] = nil
            Defaults[.uploadDestination] = .builtIn(.IMGUR)
        } else if let id = UUID(uuidString: uploader.id), CustomUploader.allCases.contains(where: { $0.id == id }) {
            Defaults[.uploadType] = .CUSTOM
            Defaults[.activeCustomUploader] = id
            Defaults[.uploadDestination] = .custom(id)
        } else {
            throw IntentError.noUploader
        }
        return .result()
    }
}

enum IntentFileStaging {
    static func stage(_ file: IntentFile) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-intent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = file.type?.preferredFilenameExtension ?? URL(fileURLWithPath: file.filename).pathExtension
        let baseName = URL(fileURLWithPath: file.filename).deletingPathExtension().lastPathComponent
        let name = (baseName.isEmpty ? "ishare" : baseName) + (ext.isEmpty ? "" : ".\(ext)")
        let destination = directory.appending(path: name)
        if let source = file.fileURL {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            guard !file.data.isEmpty else { throw IntentError.unreadableFile }
            try file.data.write(to: destination)
        }
        return destination
    }
}

struct ishareShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["Capture with \(.applicationName)", "Take a screenshot with \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: UploadFileIntent(),
            phrases: ["Upload with \(.applicationName)"],
            shortTitle: "Upload File",
            systemImageName: "icloud.and.arrow.up"
        )
        AppShortcut(
            intent: RecordIntent(),
            phrases: ["Record with \(.applicationName)", "Stop recording with \(.applicationName)"],
            shortTitle: "Record",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: SetUploaderIntent(),
            phrases: ["Change the \(.applicationName) uploader"],
            shortTitle: "Set Uploader",
            systemImageName: "server.rack"
        )
        AppShortcut(intent: CaptureWithPresetIntent(), phrases: ["Capture with an \(.applicationName) preset"], shortTitle: "Capture with Preset", systemImageName: "square.stack.3d.up")
    }
}
