import Defaults
import Foundation

extension Defaults.Keys {
    static let capturePath = Key<String>("capturePath", default: "~/Pictures/", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileType = Key<FileType>("captureFileType", default: .PNG, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileName = Key<String>("captureFileName", default: "ishare", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let screenshotShowsCursor = Key<Bool>("screenshotShowsCursor", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let windowShadow = Key<Bool>("windowShadow", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let showMagnifier = Key<Bool>("showMagnifier", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let scrollingAutoScroll = Key<Bool>("scrollingAutoScroll", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let capturePathBookmark = Key<Data?>("capturePathBookmark", default: nil, suite: .ishare)
    static let ignoredBundleIdentifiers = Key<[String]>("ignoredApps", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
