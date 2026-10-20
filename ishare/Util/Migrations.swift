import Defaults
import Foundation

enum Migrations {
    static let currentVersion = 1
    static let versionKey = "ishareMigrationVersion"
    static let removedKeys = ["captureBinary"]

    static func run(defaults: UserDefaults = .standard) {
        let version = defaults.integer(forKey: versionKey)
        guard version < currentVersion else { return }
        if version < 1 {
            removedKeys.forEach(defaults.removeObject(forKey:))
            NSUbiquitousKeyValueStore.default.removeObject(forKey: "captureBinary")
        }
        defaults.set(currentVersion, forKey: versionKey)
    }
}
