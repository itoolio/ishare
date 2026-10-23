import AppIntents
import Foundation

struct UploadPresetEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Upload Preset" }
    static var defaultQuery: UploadPresetQuery { UploadPresetQuery() }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ preset: UploadPreset) {
        id = preset.id.uuidString
        name = preset.name
    }

    @MainActor static var all: [UploadPresetEntity] {
        UploadPresets.all.map(UploadPresetEntity.init)
    }

    @MainActor var preset: UploadPreset? {
        UUID(uuidString: id).flatMap(UploadPresets.preset(id:))
    }
}

struct UploadPresetQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UploadPresetEntity.ID]) async throws -> [UploadPresetEntity] {
        UploadPresetEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [UploadPresetEntity] {
        UploadPresetEntity.all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [UploadPresetEntity] {
        UploadPresetEntity.all
    }
}

enum PresetIntentError: LocalizedError {
    case missingPreset

    var errorDescription: String? {
        switch self {
        case .missingPreset: "The selected preset no longer exists".localized()
        }
    }
}

struct CaptureWithPresetIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture with Preset" }
    static var description: IntentDescription { IntentDescription("Takes a screenshot and uploads it with one of your ishare upload presets.") }

    @Parameter(title: "Preset")
    var preset: UploadPresetEntity

    @Parameter(title: "Type", default: .region)
    var type: CaptureKindEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$type) with \(\.$preset)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let resolved = preset.preset else { throw PresetIntentError.missingPreset }
        await UploadPresets.capture(resolved, type: type.captureType)
        return .result()
    }
}
