import Defaults
import Foundation

@MainActor
enum UploaderStore {
    typealias StorageKey = Defaults.Key<Set<CustomUploader>?>

    static func prepared(_ uploader: CustomUploader, at date: Date = .init()) -> CustomUploader {
        S3SecretStore.movingSecretToKeychain(uploader).touched(at: date)
    }

    @discardableResult
    static func save(_ uploader: CustomUploader, key: StorageKey = .savedCustomUploaders) -> CustomUploader {
        let stored = prepared(uploader)
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
            uploaders.remove(stored)
            uploaders.insert(stored)
        }
        Defaults[key] = uploaders
    }

    static func duplicate(_ uploader: CustomUploader, key: StorageKey = .savedCustomUploaders) {
        let copy = uploader.withID(UUID())
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
        S3SecretStore.removeSecret(for: uploader.id)
    }

    static func deleteAll(key: StorageKey = .savedCustomUploaders) {
        for uploader in Defaults[key] ?? [] {
            S3SecretStore.removeSecret(for: uploader.id)
        }
        Defaults[key] = nil
    }
}
