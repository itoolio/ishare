import Foundation

enum SettingsStorage {
    static let screenshotSuiteName = "dev.adrian.ishare.screenshots"
    static let testSuiteName = "dev.adrian.ishare.tests"
    static let automationSuiteName = "dev.adrian.ishare.automation"
    static let syncsToCloud =
        !ScreenshotMode.isActive
        && !RuntimeEnvironment.isRunningTests
        && !AutomationTestMode.isActive
        && !ProcessInfo.processInfo.arguments.contains("-ishareDisableCloudSync")

    static var isolatedSuiteName: String? {
        if RuntimeEnvironment.isRunningTests { return testSuiteName }
        if ScreenshotMode.isActive { return screenshotSuiteName }
        if AutomationTestMode.isActive { return automationSuiteName }
        return nil
    }

    static func makeDefaults() -> UserDefaults {
        guard let name = isolatedSuiteName, let defaults = UserDefaults(suiteName: name) else { return .standard }
        if RuntimeEnvironment.isRunningTests || AutomationTestMode.isActive {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }
}

extension UserDefaults {
    nonisolated(unsafe) static let ishare: UserDefaults = SettingsStorage.makeDefaults()
}
