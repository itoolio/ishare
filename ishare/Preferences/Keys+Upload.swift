import Defaults
import Foundation

extension Defaults.Keys {
    static let imgurClientId = Key<String>("imgurClientId", default: "867afe9433c0a53", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let activeCustomUploader = Key<UUID?>("activeCustomUploader", default: nil, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let savedCustomUploaders = Key<Set<CustomUploader>?>("savedCustomUploaders", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadType = Key<UploadType>("uploadType", default: .IMGUR, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadDestination = Key<UploadDestination>("uploadDestination", default: .builtIn(.IMGUR), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
