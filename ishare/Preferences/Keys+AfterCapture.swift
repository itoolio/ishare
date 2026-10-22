import Defaults
import Foundation

extension Defaults.Keys {
    static let copyToClipboard = Key<Bool>("copyToClipboard", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let openInFinder = Key<Bool>("openInFinder", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let saveToDisk = Key<Bool>("saveToDisk", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadMedia = Key<Bool>("uploadMedia", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let builtInShare = Key<SharingPreferences>("builtInShare", default: .init(), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let openEditorAfterCapture = Key<Bool>("openEditorAfterCapture", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let forceUploadModifier = Key<ForceUploadModifier>("forceUploadModifier", default: .shift, suite: .ishare)
}
