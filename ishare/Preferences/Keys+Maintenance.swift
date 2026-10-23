import Defaults
import Foundation

extension Defaults.Keys {
    static let localCaptureRetention = Key<HistoryRetention>("localCaptureRetention", default: .never, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let keepUploadedLocalCaptures = Key<Bool>("keepUploadedLocalCaptures", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
