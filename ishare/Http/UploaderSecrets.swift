import Foundation
import ishareCore

enum UploaderSecretField: String, CaseIterable, Sendable {
    case password
    case privateKey = "privatekey"
    case passphrase
    case oauthToken = "oauth"
    case accessToken = "token"
}

enum UploaderSecretError: LocalizedError, Equatable {
    case missingSecret(String)

    var errorDescription: String? {
        switch self {
        case let .missingSecret(name):
            String(
                format:
                    "The credentials for “%@” aren't on this Mac yet. They may still be syncing via iCloud Keychain; if they don't appear, edit the uploader and enter them again."
                    .localized(),
                name
            )
        }
    }
}

enum UploaderSecrets {
    static let service = "dev.adrian.ishare.uploader-credentials"
    static let placeholder = S3SecretStore.placeholder
    private static let backendSlot = SecretBackendSlot(
        RuntimeEnvironment.isRunningTests
            ? InMemorySecretBackend()
            : KeychainSecretBackend(service: service, label: "ishare uploader credential")
    )

    static var backend: any SecretBackend {
        get { backendSlot.current }
        set { backendSlot.current = newValue }
    }

    static func account(_ id: UUID, _ field: UploaderSecretField) -> String {
        "\(id.uuidString).\(field.rawValue)"
    }

    static func read(_ field: UploaderSecretField, for id: UUID) -> String? {
        backend.read(account: account(id, field))
    }

    static func write(_ value: String?, _ field: UploaderSecretField, for id: UUID) throws {
        guard let value, !value.isEmpty else {
            backend.delete(account: account(id, field))
            return
        }
        try backend.write(value, account: account(id, field))
    }

    static func isPlaceholder(_ value: String?) -> Bool {
        value == placeholder
    }

    static func stored(_ value: String?, _ field: UploaderSecretField, for id: UUID) -> String? {
        guard let value, !value.isEmpty else { return read(field, for: id) == nil ? nil : placeholder }
        guard !isPlaceholder(value) else { return value }
        do {
            try backend.write(value, account: account(id, field))
            return placeholder
        } catch {
            Log.upload.error("Storing an uploader credential in the Keychain failed: \(error.localizedDescription, privacy: .public)")
            return value
        }
    }

    static func resolved(_ value: String?, _ field: UploaderSecretField, for uploader: CustomUploader) throws -> String? {
        guard isPlaceholder(value) else { return value }
        guard let secret = read(field, for: uploader.id) else { throw UploaderSecretError.missingSecret(uploader.name) }
        return secret
    }

    static func revealed(_ value: String?, _ field: UploaderSecretField, for id: UUID) -> String? {
        isPlaceholder(value) ? read(field, for: id) : value
    }

    static func movingSecretsToKeychain(_ uploader: CustomUploader) -> CustomUploader {
        var copy = uploader
        let id = uploader.id
        switch uploader.kind {
        case .webdav:
            copy.webdav?.password = stored(uploader.webdav?.password, .password, for: id)
        case .sftp:
            copy.sftp?.password = stored(uploader.sftp?.password, .password, for: id)
            copy.sftp?.privateKey = stored(uploader.sftp?.privateKey, .privateKey, for: id)
            copy.sftp?.passphrase = stored(uploader.sftp?.passphrase, .passphrase, for: id)
        case .github:
            copy.github?.token = stored(uploader.github?.token, .accessToken, for: id)
        default:
            break
        }
        return copy
    }

    static func resolvingSecrets(_ uploader: CustomUploader) throws -> CustomUploader {
        var copy = uploader
        switch uploader.kind {
        case .webdav:
            copy.webdav?.password = try resolved(uploader.webdav?.password, .password, for: uploader)
        case .sftp:
            copy.sftp?.password = try resolved(uploader.sftp?.password, .password, for: uploader)
            copy.sftp?.privateKey = try resolved(uploader.sftp?.privateKey, .privateKey, for: uploader)
            copy.sftp?.passphrase = try resolved(uploader.sftp?.passphrase, .passphrase, for: uploader)
        case .github:
            copy.github?.token = try resolved(uploader.github?.token, .accessToken, for: uploader)
        default:
            break
        }
        return copy
    }

    static func exporting(_ uploader: CustomUploader, includeSecrets: Bool) -> CustomUploader {
        var copy = uploader
        let id = uploader.id
        func exported(_ value: String?, _ field: UploaderSecretField) -> String? {
            guard includeSecrets else { return nil }
            return revealed(value, field, for: id)
        }
        copy.webdav?.password = exported(uploader.webdav?.password, .password)
        copy.sftp?.password = exported(uploader.sftp?.password, .password)
        copy.sftp?.privateKey = exported(uploader.sftp?.privateKey, .privateKey)
        copy.sftp?.passphrase = exported(uploader.sftp?.passphrase, .passphrase)
        copy.github?.token = exported(uploader.github?.token, .accessToken)
        return copy
    }

    static func revealingSecrets(_ uploader: CustomUploader) -> CustomUploader {
        exporting(uploader, includeSecrets: true)
    }

    static func hasExportableSecrets(_ uploader: CustomUploader) -> Bool {
        switch uploader.kind {
        case .webdav: uploader.webdav?.password != nil
        case .sftp: uploader.sftp?.password != nil || uploader.sftp?.privateKey != nil
        case .github: uploader.github?.token != nil
        default: false
        }
    }

    static func copySecrets(from source: UUID, to destination: UUID) {
        for field in UploaderSecretField.allCases {
            if let secret = read(field, for: source) {
                try? write(secret, field, for: destination)
            }
        }
    }

    static func removeSecrets(for id: UUID) {
        for field in UploaderSecretField.allCases {
            backend.delete(account: account(id, field))
        }
    }
}
