import Defaults
import Foundation

extension Defaults.Keys {
    static let uploadHistory = Key<[HistoryItem]>("uploadHistory", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let historyLimit = Key<HistoryLimit>("historyLimit", default: .items50, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let historyRetention = Key<HistoryRetention>("historyRetention", default: .never, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
