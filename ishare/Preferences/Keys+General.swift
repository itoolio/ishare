import Defaults
import Foundation

extension Defaults.Keys {
    static let toastTimeout = Key<Double>("toastTimeout", default: 2, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let menuBarIcon = Key<MenuBarIcon>("menuBarIcon", default: .DEFAULT, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let aussieMode = Key<Bool>("aussieMode", default: Locale.current.identifier.starts(with: "en-AU"), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let copyImageToClipboard = Key<Bool>("copyImageToClipboard", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let menuRecordsGIF = Key<Bool>("menuRecordsGIF", default: false, suite: .ishare)
    static let captureSound = Key<SoundChoice>("captureSound", default: .beep, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadCompleteSound = Key<SoundChoice>("uploadCompleteSound", default: .none, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false, suite: .ishare)
}
