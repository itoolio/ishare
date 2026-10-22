import Defaults
import Foundation

enum Migrations {
    static let currentVersion = 2
    static let versionKey = "ishareMigrationVersion"
    static let removedKeys = ["captureBinary"]
    static let removedInVersion2 = ["showMainMenu"]

    static func run(defaults: UserDefaults = .standard) {
        let version = defaults.integer(forKey: versionKey)
        guard version < currentVersion else { return }
        if version < 1 {
            removedKeys.forEach(defaults.removeObject(forKey:))
            NSUbiquitousKeyValueStore.default.removeObject(forKey: "captureBinary")
        }
        if version < 2 {
            migrateStoredLanguage(defaults: defaults)
            removedInVersion2.forEach { key in
                defaults.removeObject(forKey: key)
                NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
            }
        }
        defaults.set(currentVersion, forKey: versionKey)
    }

    static func migrateStoredLanguage(defaults: UserDefaults) {
        let key = "storedlanguage"
        if let code = defaults.string(forKey: key), AppLanguage.override(in: defaults) == nil,
           let language = LanguageTypes(rawValue: code), language != .english {
            defaults.set([language.rawValue], forKey: AppLanguage.preferenceKey)
        }
        defaults.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
    }
}
