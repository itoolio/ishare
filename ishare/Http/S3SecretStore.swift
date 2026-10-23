import Foundation
import ishareCore
import Security
import Synchronization

protocol SecretBackend: Sendable {
    func read(account: String) -> String?
    func write(_ secret: String, account: String) throws
    func delete(account: String)
    func makeSynchronizable(account: String) -> Bool
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

protocol KeychainClient: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SecurityKeychainClient: KeychainClient {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

enum SharedKeychainGroup {
    static let suffix = "dev.adrian.ishare.shared"
    static let entitlement = "keychain-access-groups"

    static let current: String? = resolve(entitledGroups: entitledGroups())

    static func resolve(entitledGroups: [String]) -> String? {
        entitledGroups.first { $0 == suffix || $0.hasSuffix("." + suffix) }
    }

    static func entitledGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
        else { return [] }
        return (value as? [String]) ?? []
    }
}

enum KeychainQueries {
    static let label = "ishare S3 secret access key"

    static func legacy(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func synchronized(service: String, account: String, accessGroup: String?) -> [String: Any] {
        var query = legacy(service: service, account: account)
        query[kSecUseDataProtectionKeychain as String] = true
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    static func reading(_ query: [String: Any]) -> [String: Any] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        return request
    }

    static func synchronizedItem(service: String, account: String, accessGroup: String?, data: Data, label: String = KeychainQueries.label) -> [String: Any] {
        var item = legacy(service: service, account: account)
        item[kSecUseDataProtectionKeychain as String] = true
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrLabel as String] = label
        item[kSecValueData as String] = data
        if let accessGroup {
            item[kSecAttrAccessGroup as String] = accessGroup
        }
        return item
    }

    static func legacyItem(service: String, account: String, data: Data, label: String = KeychainQueries.label) -> [String: Any] {
        var item = legacy(service: service, account: account)
        item[kSecAttrLabel as String] = label
        item[kSecValueData as String] = data
        return item
    }
}

struct KeychainSecretBackend: SecretBackend {
    let service: String
    var accessGroup: String? = SharedKeychainGroup.current
    var client: any KeychainClient = SecurityKeychainClient()
    var label = KeychainQueries.label

    private func synchronizedQuery(_ account: String) -> [String: Any] {
        KeychainQueries.synchronized(service: service, account: account, accessGroup: accessGroup)
    }

    private func legacyQuery(_ account: String) -> [String: Any] {
        KeychainQueries.legacy(service: service, account: account)
    }

    private func data(matching query: [String: Any]) -> Data? {
        let (status, data) = client.copyMatching(KeychainQueries.reading(query))
        return status == errSecSuccess ? data : nil
    }

    func read(account: String) -> String? {
        if let data = data(matching: synchronizedQuery(account)) {
            return String(data: data, encoding: .utf8)
        }
        guard let data = data(matching: legacyQuery(account)) else { return nil }
        promoteToSynchronizable(data, account: account)
        return String(data: data, encoding: .utf8)
    }

    func write(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let status = client.update(synchronizedQuery(account), with: [kSecValueData as String: data])
        switch status {
        case errSecSuccess:
            _ = client.delete(legacyQuery(account))
        case errSecItemNotFound:
            try addSynchronized(data, account: account)
        case errSecMissingEntitlement:
            try writeLegacy(data, account: account)
        default:
            throw KeychainError(status: status)
        }
    }

    private func addSynchronized(_ data: Data, account: String) throws {
        let status = client.add(KeychainQueries.synchronizedItem(service: service, account: account, accessGroup: accessGroup, data: data, label: label))
        switch status {
        case errSecSuccess:
            _ = client.delete(legacyQuery(account))
        case errSecMissingEntitlement:
            try writeLegacy(data, account: account)
        default:
            throw KeychainError(status: status)
        }
    }

    private func writeLegacy(_ data: Data, account: String) throws {
        let status = client.update(legacyQuery(account), with: [kSecValueData as String: data])
        if status == errSecItemNotFound {
            let addStatus = client.add(KeychainQueries.legacyItem(service: service, account: account, data: data, label: label))
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func delete(account: String) {
        _ = client.delete(synchronizedQuery(account))
        _ = client.delete(legacyQuery(account))
    }

    func makeSynchronizable(account: String) -> Bool {
        guard data(matching: synchronizedQuery(account)) == nil, let data = data(matching: legacyQuery(account)) else { return false }
        return promoteToSynchronizable(data, account: account)
    }

    @discardableResult
    private func promoteToSynchronizable(_ data: Data, account: String) -> Bool {
        let item = KeychainQueries.synchronizedItem(service: service, account: account, accessGroup: accessGroup, data: data, label: label)
        let status = client.add(item)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            guard status != errSecMissingEntitlement else { return false }
            Log.upload.error("Moving the S3 secret to iCloud Keychain failed: \(KeychainError(status: status).localizedDescription, privacy: .public)")
            return false
        }
        _ = client.delete(legacyQuery(account))
        return true
    }
}

final class InMemorySecretBackend: SecretBackend {
    private struct State {
        var secrets: [String: String] = [:]
        var localOnly: Set<String> = []
    }

    private let state = Mutex(State())

    func read(account: String) -> String? {
        state.withLock { state in
            state.localOnly.remove(account)
            return state.secrets[account]
        }
    }

    func write(_ secret: String, account: String) throws {
        state.withLock { state in
            state.secrets[account] = secret
            state.localOnly.remove(account)
        }
    }

    func delete(account: String) {
        state.withLock { state in
            _ = state.secrets.removeValue(forKey: account)
            state.localOnly.remove(account)
        }
    }

    func storeLocalOnly(_ secret: String, account: String) {
        state.withLock { state in
            state.secrets[account] = secret
            state.localOnly.insert(account)
        }
    }

    func isSynchronizable(account: String) -> Bool {
        state.withLock { $0.secrets[account] != nil && !$0.localOnly.contains(account) }
    }

    func makeSynchronizable(account: String) -> Bool {
        state.withLock { $0.secrets[account] != nil && $0.localOnly.remove(account) != nil }
    }
}

final class SecretBackendSlot: Sendable {
    private let backend: Mutex<any SecretBackend>

    init(_ backend: any SecretBackend) {
        self.backend = Mutex(backend)
    }

    var current: any SecretBackend {
        get { backend.withLock { $0 } }
        set { backend.withLock { $0 = newValue } }
    }
}

enum S3SecretError: LocalizedError, Equatable {
    case missingSecret(String)

    var errorDescription: String? {
        switch self {
        case let .missingSecret(name):
            String(
                format: "The secret access key for “%@” isn't on this Mac yet. It may still be syncing via iCloud Keychain; if it doesn't appear, edit the uploader and enter it again.".localized(),
                name
            )
        }
    }
}

enum S3SecretStore {
    static let service = "dev.adrian.ishare.s3"
    static let placeholder = "@keychain"
    private static let backendSlot = SecretBackendSlot(
        RuntimeEnvironment.isRunningTests ? InMemorySecretBackend() : KeychainSecretBackend(service: service)
    )

    static var backend: any SecretBackend {
        get { backendSlot.current }
        set { backendSlot.current = newValue }
    }

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

    @discardableResult
    static func makeSynchronizable(_ uploaders: some Sequence<CustomUploader>) -> [UUID] {
        uploaders
            .filter { $0.kind == .s3 && isPlaceholder($0.s3?.secretAccessKey ?? "") }
            .filter { backend.makeSynchronizable(account: $0.id.uuidString) }
            .map(\.id)
    }
}
