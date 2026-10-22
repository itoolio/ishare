import Defaults
import Foundation

enum Migrations {
    static let currentVersion = 3
    static let versionKey = "ishareMigrationVersion"
    static let removedKeys = ["captureBinary"]
    static let removedInVersion2 = ["showMainMenu"]

    static func run(defaults: UserDefaults = .standard) {
        if RuntimeEnvironment.isRunningTests, defaults === UserDefaults.standard { return }
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
        if version < 3 {
            moveS3SecretsToKeychain(defaults: defaults)
        }
        defaults.set(currentVersion, forKey: versionKey)
    }

    static func moveS3SecretsToKeychain(defaults: UserDefaults) {
        let key = Defaults.Key<Set<CustomUploader>?>("savedCustomUploaders", suite: defaults)
        guard let uploaders = Defaults[key] else { return }
        let migrated = uploaders.map(S3SecretStore.movingSecretToKeychain)
        let secrets = Dictionary(uniqueKeysWithValues: uploaders.map { ($0.id, $0.s3?.secretAccessKey) })
        if migrated.contains(where: { secrets[$0.id] != $0.s3?.secretAccessKey }) {
            Defaults[key] = Set(migrated)
        }
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
