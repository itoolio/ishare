import Foundation

enum SettingsStorage {
    static let screenshotSuiteName = "dev.adrian.ishare.screenshots"
    static let syncsToCloud = !ScreenshotMode.isActive && !ProcessInfo.processInfo.arguments.contains("-ishareDisableCloudSync")
}

extension UserDefaults {
    nonisolated(unsafe) static let ishare: UserDefaults = ScreenshotMode.isActive
        ? UserDefaults(suiteName: SettingsStorage.screenshotSuiteName) ?? .standard
        : .standard
}
