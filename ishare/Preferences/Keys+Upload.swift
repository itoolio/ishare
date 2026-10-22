import Defaults
import Foundation

extension Defaults.Keys {
    static let imgurClientId = Key<String>("imgurClientId", default: "867afe9433c0a53", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let activeCustomUploader = Key<UUID?>("activeCustomUploader", default: nil, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let savedCustomUploaders = Key<Set<CustomUploader>?>("savedCustomUploaders", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadType = Key<UploadType>("uploadType", default: .IMGUR, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadDestination = Key<UploadDestination>("uploadDestination", default: .builtIn(.IMGUR), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let copyURLAfterUpload = Key<Bool>("copyURLAfterUpload", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let openURLAfterUpload = Key<Bool>("openURLAfterUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let additionalUploadDestinations = Key<[UploadDestination]>("additionalUploadDestinations", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let destinationChooserModifier = Key<ForceUploadModifier?>("destinationChooserModifier", suite: .ishare)
    static let watchFolderEnabled = Key<Bool>("watchFolderEnabled", default: false, suite: .ishare)
    static let watchFolderPath = Key<String>("watchFolderPath", default: "", suite: .ishare)
    static let watchFolderBookmark = Key<Data?>("watchFolderBookmark", default: nil, suite: .ishare)
    static let watchFolderFilter = Key<WatchFolderFilter>("watchFolderFilter", default: .images, suite: .ishare)
    static let watchFolderProcessed = Key<[String]>("watchFolderProcessed", default: [], suite: .ishare)
    static let uploadersLastSyncedAt = Key<Date?>("uploadersLastSyncedAt", default: nil, suite: .ishare)
}
