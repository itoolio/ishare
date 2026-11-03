import Defaults
import Foundation
import ishareCore

extension Defaults.Keys {
    static let historyGrouping = Key<HistoryGrouping>("historyGrouping", default: .day, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadHistory = Key<[HistoryItem]>("uploadHistory", default: [], suite: .ishare)
    static let historyLimit = Key<HistoryLimit>("historyLimit", default: .items50, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let historySyncEnabled = Key<Bool>("historySyncEnabled", default: false, suite: .ishare)
    static let historySyncTombstones = Key<[String: Date]>("historySyncTombstones", default: [:], suite: .ishare)
    static let historyRetention = Key<HistoryRetention>("historyRetention", default: .never, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}

extension HistoryGrouping: @retroactive Defaults.Serializable {}
