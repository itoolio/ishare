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
    static let editorShowsLayers = Key<Bool>("editorShowsLayers", default: false, suite: .ishare)
    static let menuSectionOrder = Key<[MenuSection]>("menuSectionOrder", default: MenuSection.allCases, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let hiddenMenuSections = Key<Set<MenuSection>>("hiddenMenuSections", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let menuDensity = Key<MenuDensity>("menuDensity", default: .comfortable, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let menuTheme = Key<MenuTheme>("menuTheme", default: .system, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let highContrastMenu = Key<Bool>("highContrastMenu", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let toastCorner = Key<ToastCorner>("toastCorner", default: .topRight, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let toastScreen = Key<ToastScreenChoice>("toastScreen", default: .main, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let resultPresentation = Key<ResultPresentation>("resultPresentation", default: .toast, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
