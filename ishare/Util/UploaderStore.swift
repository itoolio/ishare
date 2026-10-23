import Defaults
import Foundation
import ishareCore

@MainActor
enum UploaderStore {
    typealias StorageKey = Defaults.Key<Set<CustomUploader>?>

    static func isDefaultStorage(_ key: StorageKey) -> Bool {
        key.name == Defaults.Keys.savedCustomUploaders.name && key.suite === Defaults.Keys.savedCustomUploaders.suite
    }

    static func saveLocal(_ uploader: CustomUploader) {
        var local = Defaults[.savedLocalUploaders]
        local.remove(uploader)
        local.insert(uploader)
        Defaults[.savedLocalUploaders] = local
        var synced = Defaults[.savedCustomUploaders] ?? []
        if synced.remove(uploader) != nil {
            Defaults[.savedCustomUploaders] = synced
        }
    }

    static func separateLocalUploaders() {
        let synced = Defaults[.savedCustomUploaders] ?? []
        let local = synced.filter(\.isLocalOnly)
        guard !local.isEmpty else { return }
        Defaults[.savedLocalUploaders] = Defaults[.savedLocalUploaders].union(local)
        Defaults[.savedCustomUploaders] = synced.subtracting(local)
    }

    static func prepared(_ uploader: CustomUploader, at date: Date = .init()) -> CustomUploader {
        UploaderSecrets.movingSecretsToKeychain(S3SecretStore.movingSecretToKeychain(uploader)).touched(at: date)
    }

    @discardableResult
    static func save(_ uploader: CustomUploader, key: StorageKey = .savedCustomUploaders) -> CustomUploader {
        let stored = prepared(uploader)
        if stored.isLocalOnly, isDefaultStorage(key) {
            saveLocal(stored)
            return stored
        }
        var uploaders = Defaults[key] ?? []
        uploaders.remove(stored)
        uploaders.insert(stored)
        Defaults[key] = uploaders
        return stored
    }

    static func merge(_ incoming: [CustomUploader], key: StorageKey = .savedCustomUploaders) {
        guard !incoming.isEmpty else { return }
        var uploaders = Defaults[key] ?? []
        for uploader in incoming {
            let stored = prepared(uploader)
            if stored.isLocalOnly, isDefaultStorage(key) {
                saveLocal(stored)
                continue
            }
            uploaders.remove(stored)
            uploaders.insert(stored)
        }
        Defaults[key] = uploaders
    }

    static func duplicate(_ uploader: CustomUploader, key: StorageKey = .savedCustomUploaders) {
        let copy = UploaderSecrets.revealingSecrets(uploader).withID(UUID())
        if let token = UploaderSecrets.read(.oauthToken, for: uploader.id) {
            try? UploaderSecrets.write(token, .oauthToken, for: copy.id)
        }
        if uploader.kind == .s3, let secret = S3SecretStore.secret(for: uploader), var configuration = copy.s3 {
            configuration.secretAccessKey = secret
            var resolved = copy
            resolved.s3 = configuration
            save(resolved, key: key)
        } else {
            save(copy, key: key)
        }
    }

    static func delete(_ uploader: CustomUploader, key: StorageKey = .savedCustomUploaders) {
        Defaults[key] = (Defaults[key] ?? []).filter { $0.id != uploader.id }
        if isDefaultStorage(key) {
            Defaults[.savedLocalUploaders] = Defaults[.savedLocalUploaders].filter { $0.id != uploader.id }
        }
        S3SecretStore.removeSecret(for: uploader.id)
        UploaderSecrets.removeSecrets(for: uploader.id)
    }

    static func deleteAll(key: StorageKey = .savedCustomUploaders) {
        for uploader in Defaults[key] ?? [] {
            S3SecretStore.removeSecret(for: uploader.id)
            UploaderSecrets.removeSecrets(for: uploader.id)
        }
        Defaults[key] = nil
        if isDefaultStorage(key) {
            Defaults[.savedLocalUploaders] = []
        }
    }
}
