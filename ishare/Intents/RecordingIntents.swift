import AppIntents
import Foundation

enum RecordingIntentError: LocalizedError {
    case notRecording

    var errorDescription: String? {
        switch self {
        case .notRecording: "No recording is in progress".localized()
        }
    }
}

struct PauseRecordingIntent: AppIntent {
    static var title: LocalizedStringResource { "Pause ishare Recording" }
    static var description: IntentDescription { IntentDescription("Pauses the screen recording in progress. Paused time is left out of the video.") }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard CaptureSession.isRecording else { throw RecordingIntentError.notRecording }
        AppModel.shared.recorder.pause()
        return .result()
    }
}

struct ResumeRecordingIntent: AppIntent {
    static var title: LocalizedStringResource { "Resume ishare Recording" }
    static var description: IntentDescription { IntentDescription("Resumes a paused screen recording.") }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard CaptureSession.isRecording else { throw RecordingIntentError.notRecording }
        AppModel.shared.recorder.resume()
        return .result()
    }
}

struct RecordingPresetEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Recording Preset" }
    static var defaultQuery: RecordingPresetQuery { RecordingPresetQuery() }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ preset: RecordingPreset) {
        id = preset.id.uuidString
        name = preset.name
    }

    @MainActor static var all: [RecordingPresetEntity] {
        RecordingPresets.all.map(RecordingPresetEntity.init)
    }

    @MainActor var preset: RecordingPreset? {
        UUID(uuidString: id).flatMap(RecordingPresets.preset(id:))
    }
}

struct RecordingPresetQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [RecordingPresetEntity.ID]) async throws -> [RecordingPresetEntity] {
        RecordingPresetEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [RecordingPresetEntity] {
        RecordingPresetEntity.all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [RecordingPresetEntity] {
        RecordingPresetEntity.all
    }
}

struct RecordWithPresetIntent: AppIntent {
    static var title: LocalizedStringResource { "Record with Preset" }
    static var description: IntentDescription {
        IntentDescription("Starts a screen recording with one of your ishare recording presets. The preset's settings apply only to this recording.")
    }

    @Parameter(title: "Preset")
    var preset: RecordingPresetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Record with \(\.$preset)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let resolved = preset.preset else { throw PresetIntentError.missingPreset }
        guard !CaptureSession.isRecording else { return .result() }
        RecordingPresets.record(resolved)
        return .result()
    }
}
