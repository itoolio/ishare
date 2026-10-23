import Foundation

enum SettingsStorage {
    static let screenshotSuiteName = "dev.adrian.ishare.screenshots"
    static let testSuiteName = "dev.adrian.ishare.tests"
    static let syncsToCloud = !ScreenshotMode.isActive
        && !RuntimeEnvironment.isRunningTests
        && !ProcessInfo.processInfo.arguments.contains("-ishareDisableCloudSync")

    static var isolatedSuiteName: String? {
        if RuntimeEnvironment.isRunningTests { return testSuiteName }
        if ScreenshotMode.isActive { return screenshotSuiteName }
        return nil
    }

    static func makeDefaults() -> UserDefaults {
        guard let name = isolatedSuiteName, let defaults = UserDefaults(suiteName: name) else { return .standard }
        if RuntimeEnvironment.isRunningTests {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }
}

extension UserDefaults {
    nonisolated(unsafe) static let ishare: UserDefaults = SettingsStorage.makeDefaults()
}
