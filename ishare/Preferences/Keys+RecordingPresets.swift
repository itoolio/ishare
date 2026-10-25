import Defaults
import Foundation

extension Defaults.Keys {
    static let recordingPresets = Key<[RecordingPreset]>("recordingPresets", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
