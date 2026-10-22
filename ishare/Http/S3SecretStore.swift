import Foundation
import Security

protocol SecretBackend: Sendable {
    func read(account: String) -> String?
    func write(_ secret: String, account: String) throws
    func delete(account: String)
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

struct KeychainSecretBackend: SecretBackend {
    let service: String

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(account: String) -> String? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account: account)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "ishare S3 secret access key"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}

final class InMemorySecretBackend: SecretBackend, @unchecked Sendable {
    private var secrets: [String: String] = [:]
    private let lock = NSLock()

    func read(account: String) -> String? {
        lock.withLock { secrets[account] }
    }

    func write(_ secret: String, account: String) throws {
        lock.withLock { secrets[account] = secret }
    }

    func delete(account: String) {
        lock.withLock { _ = secrets.removeValue(forKey: account) }
    }
}

enum S3SecretError: LocalizedError, Equatable {
    case missingSecret(String)

    var errorDescription: String? {
        switch self {
        case let .missingSecret(name):
            "The secret access key for “\(name)” isn't in this Mac's Keychain. Edit the uploader and enter it again."
        }
    }
}

enum S3SecretStore {
    static let service = "dev.adrian.ishare.s3"
    static let placeholder = "@keychain"
    nonisolated(unsafe) static var backend: any SecretBackend = KeychainSecretBackend(service: service)

    static func isPlaceholder(_ secret: String) -> Bool {
        secret == placeholder
    }

    static func hasSecret(for id: UUID) -> Bool {
        backend.read(account: id.uuidString) != nil
    }

    static func secret(for uploader: CustomUploader) -> String? {
        guard let configuration = uploader.s3 else { return nil }
        guard isPlaceholder(configuration.secretAccessKey) else { return configuration.secretAccessKey }
        return backend.read(account: uploader.id.uuidString)
    }

    static func movingSecretToKeychain(_ uploader: CustomUploader) -> CustomUploader {
        guard uploader.kind == .s3, var configuration = uploader.s3 else { return uploader }
        let secret = configuration.secretAccessKey
        if secret.isEmpty, hasSecret(for: uploader.id) {
            configuration.secretAccessKey = placeholder
        } else if !secret.isEmpty, !isPlaceholder(secret) {
            do {
                try backend.write(secret, account: uploader.id.uuidString)
                configuration.secretAccessKey = placeholder
            } catch {
                Log.upload.error("Storing the S3 secret in the Keychain failed: \(error.localizedDescription, privacy: .public)")
                return uploader
            }
        }
        var copy = uploader
        copy.s3 = configuration
        return copy
    }

    static func resolvingSecret(_ uploader: CustomUploader) throws -> CustomUploader {
        guard var configuration = uploader.s3, isPlaceholder(configuration.secretAccessKey) else { return uploader }
        guard let secret = backend.read(account: uploader.id.uuidString) else {
            throw S3SecretError.missingSecret(uploader.name)
        }
        configuration.secretAccessKey = secret
        var copy = uploader
        copy.s3 = configuration
        return copy
    }

    static func exporting(_ uploader: CustomUploader, includeSecret: Bool) -> CustomUploader {
        guard var configuration = uploader.s3 else { return uploader }
        configuration.secretAccessKey = includeSecret ? (secret(for: uploader) ?? "") : ""
        var copy = uploader
        copy.s3 = configuration
        return copy
    }

    static func copySecret(from source: UUID, to destination: UUID) {
        guard let secret = backend.read(account: source.uuidString) else { return }
        try? backend.write(secret, account: destination.uuidString)
    }

    static func removeSecret(for id: UUID) {
        backend.delete(account: id.uuidString)
    }
}
