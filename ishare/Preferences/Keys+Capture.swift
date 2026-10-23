import Defaults
import Foundation

extension Defaults.Keys {
    static let capturePath = Key<String>("capturePath", default: "~/Pictures/", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileType = Key<FileType>("captureFileType", default: .PNG, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileName = Key<String>("captureFileName", default: "ishare", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let screenshotShowsCursor = Key<Bool>("screenshotShowsCursor", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let windowShadow = Key<Bool>("windowShadow", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let showMagnifier = Key<Bool>("showMagnifier", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let scrollingAutoScroll = Key<Bool>("scrollingAutoScroll", default: ScrollingCapture.autoScrollsByDefault, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let capturePathBookmark = Key<Data?>("capturePathBookmark", default: nil, suite: .ishare)
    static let ignoredBundleIdentifiers = Key<[String]>("ignoredApps", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let hideMenuBarInCaptures = Key<Bool>("hideMenuBarInCaptures", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let blurredBundleIdentifiers = Key<[String]>("blurredBundleIdentifiers", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyEnabled = Key<Bool>("beautifyEnabled", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyWindowsOnly = Key<Bool>("beautifyWindowsOnly", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyPadding = Key<Double>("beautifyPadding", default: 48, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyCornerRadius = Key<Double>("beautifyCornerRadius", default: 12, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyShadow = Key<Bool>("beautifyShadow", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyBackground = Key<BeautifyBackground>("beautifyBackground", default: .ocean, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifySolidColor = Key<String>("beautifySolidColor", default: "#1E1E2E", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let lastCaptureRegions = Key<LastRegions>("lastCaptureRegions", default: LastRegions(), suite: .ishare)
}
