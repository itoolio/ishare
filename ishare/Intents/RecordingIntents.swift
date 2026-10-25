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
