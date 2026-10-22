import Defaults
import Foundation

extension Defaults.Keys {
    static let uploadHistory = Key<[HistoryItem]>("uploadHistory", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
