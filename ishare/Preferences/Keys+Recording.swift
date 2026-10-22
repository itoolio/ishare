import Defaults
import Foundation

extension Defaults.Keys {
    static let recordingPath = Key<String>("recordingPath", default: "~/Pictures/", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordingFileName = Key<String>("recordingFileName", default: "ishare", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordMP4 = Key<Bool>("recordMP4", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let useHEVC = Key<Bool>("useHEVC", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let useHDR = Key<Bool>("useHDR", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordAudio = Key<Bool>("recordAudio", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordMic = Key<Bool>("recordMic", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordPointer = Key<Bool>("recordPointer", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordClicks = Key<Bool>("recordClicks", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordingPathBookmark = Key<Data?>("recordingPathBookmark", default: nil, suite: .ishare)
    static let recordingResolution = Key<RecordingResolution>("recordingResolution", default: .native, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let recordingFrameRate = Key<RecordingFrameRate>("recordingFrameRate", default: .fps60, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let gifFrameRate = Key<GIFFrameRate>("gifFrameRate", default: .fps20, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let compressBeforeUpload = Key<Bool>("compressBeforeUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let compressionThresholdMB = Key<Int>("compressionThresholdMB", default: 25, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let compressionPreset = Key<CompressionPreset>("compressionPreset", default: .p1080, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
