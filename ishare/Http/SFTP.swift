import Citadel
import Crypto
import Foundation
import ishareCore
import NIOCore
import NIOSSH
import Synchronization

enum SFTPError: LocalizedError, Equatable {
    case missingCredentials
    case unsupportedKey(String)
    case hostKeyMismatch(expected: String, presented: String)
    case connectionFailed(String)
    case operationFailed(path: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Enter a password or a private key for the SFTP server".localized()
        case let .unsupportedKey(detail):
            String(format: "The private key couldn't be read (%@). Use an unencrypted or passphrase-protected OpenSSH Ed25519 or RSA key.".localized(), detail)
        case let .hostKeyMismatch(expected, presented):
            String(
                format:
                    "The SFTP server's host key changed. ishare expected %@ but the server presented %@. If the server was reinstalled, clear the trusted fingerprint in the uploader settings."
                    .localized(),
                expected, presented
            )
        case let .connectionFailed(detail):
            String(format: "Couldn't connect to the SFTP server: %@".localized(), detail)
        case let .operationFailed(path, detail):
            String(format: "The SFTP server couldn't write %@: %@".localized(), path, detail)
        }
    }
}

enum SSHFingerprint {
    static func sha256(ofWireKey bytes: Data) -> String {
        let digest = Data(SHA256.hash(data: bytes))
        return "SHA256:" + digest.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    static func sha256(openSSHPublicKey: String) -> String? {
        let parts = openSSHPublicKey.split(separator: " ")
        guard parts.count >= 2, let bytes = Data(base64Encoded: String(parts[1])) else { return nil }
        return sha256(ofWireKey: bytes)
    }

    static func fingerprint(of key: NIOSSHPublicKey) -> String {
        sha256(openSSHPublicKey: String(openSSHPublicKey: key)) ?? String(openSSHPublicKey: key)
    }

    static func matches(_ expected: String, _ presented: String) -> Bool {
        normalized(expected) == normalized(presented)
    }

    static func normalized(_ fingerprint: String) -> String {
        let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.lowercased().hasPrefix("sha256:") ? String(trimmed.dropFirst(7)) : trimmed
        return body.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

enum SFTPHostKeyDecision: Equatable, Sendable {
    case trusted
    case trustOnFirstUse(String)
    case mismatch(expected: String, presented: String)

    static func evaluate(expected: String?, presented: String) -> SFTPHostKeyDecision {
        guard let expected = expected?.trimmingCharacters(in: .whitespaces), !expected.isEmpty else {
            return .trustOnFirstUse(presented)
        }
        return SSHFingerprint.matches(expected, presented) ? .trusted : .mismatch(expected: expected, presented: presented)
    }
}

final class SFTPHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let expected: String?
    private let presented = Mutex<String?>(nil)

    init(expected: String?) {
        self.expected = expected
    }

    var presentedFingerprint: String? {
        presented.withLock { $0 }
    }

    var decision: SFTPHostKeyDecision? {
        presentedFingerprint.map { SFTPHostKeyDecision.evaluate(expected: expected, presented: $0) }
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = SSHFingerprint.fingerprint(of: hostKey)
        presented.withLock { $0 = fingerprint }
        switch SFTPHostKeyDecision.evaluate(expected: expected, presented: fingerprint) {
        case .trusted, .trustOnFirstUse:
            validationCompletePromise.succeed(())
        case let .mismatch(expected, presented):
            validationCompletePromise.fail(SFTPError.hostKeyMismatch(expected: expected, presented: presented))
        }
    }
}

enum SFTPAuthentication {
    static func method(for configuration: SFTPConfiguration) throws -> SSHAuthenticationMethod {
        let username = configuration.username
        if configuration.usesPrivateKey, let key = configuration.privateKey?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let passphrase = configuration.passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
            do {
                switch try SSHKeyDetection.detectPrivateKeyType(from: key) {
                case .ed25519:
                    return .ed25519(username: username, privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: passphrase))
                case .rsa:
                    return .rsa(username: username, privateKey: try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: passphrase))
                case let other:
                    throw SFTPError.unsupportedKey(other.description)
                }
            } catch let error as SFTPError {
                throw error
            } catch {
                throw SFTPError.unsupportedKey(String(describing: error))
            }
        }
        guard let password = configuration.password, !password.isEmpty else { throw SFTPError.missingCredentials }
        return .passwordBased(username: username, password: password)
    }
}

struct SFTPConnectionResult: Sendable {
    let fingerprint: String?
    let newlyTrusted: Bool
}

enum SFTPTransport {
    static let chunkSize = 256 * 1024

    static func connect(_ configuration: SFTPConfiguration, validator: SFTPHostKeyValidator) async throws -> SSHClient {
        let authentication = try SFTPAuthentication.method(for: configuration)
        do {
            return try await SSHClient.connect(
                host: configuration.trimmedHost, port: configuration.resolvedPort, authenticationMethod: authentication,
                hostKeyValidator: .custom(validator), reconnect: .never, connectTimeout: .seconds(20)
            )
        } catch {
            if case let .mismatch(expected, presented) = validator.decision {
                throw SFTPError.hostKeyMismatch(expected: expected, presented: presented)
            }
            throw SFTPError.connectionFailed(String(describing: error))
        }
    }

    static func withSFTP<T: Sendable>(
        _ configuration: SFTPConfiguration, validator: SFTPHostKeyValidator, _ body: @Sendable (SFTPClient) async throws -> T
    ) async throws -> T {
        let client = try await connect(configuration, validator: validator)
        do {
            let sftp = try await client.openSFTP()
            let result: T
            do {
                result = try await body(sftp)
            } catch {
                try? await sftp.close()
                throw error
            }
            try? await sftp.close()
            try? await client.close()
            return result
        } catch {
            try? await client.close()
            throw error
        }
    }

    static func makeDirectories(_ directories: [String], in sftp: SFTPClient) async {
        for directory in directories {
            if (try? await sftp.getAttributes(at: directory)) != nil { continue }
            try? await sftp.createDirectory(atPath: directory)
        }
    }

    static func write(_ fileURL: URL, to remotePath: String, in sftp: SFTPClient, progress: @Sendable (Double) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let total = max(1, (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1)
        let file: SFTPFile
        do {
            file = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        } catch {
            throw SFTPError.operationFailed(path: remotePath, detail: String(describing: error))
        }
        do {
            var offset: UInt64 = 0
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                try await file.write(ByteBuffer(bytes: chunk), at: offset)
                offset += UInt64(chunk.count)
                progress(min(1, Double(offset) / Double(total)))
            }
            try await file.close()
        } catch {
            try? await file.close()
            throw SFTPError.operationFailed(path: remotePath, detail: String(describing: error))
        }
    }

    static func contents(of remotePath: String, configuration: SFTPConfiguration) async throws -> Data {
        let validator = SFTPHostKeyValidator(expected: configuration.hostKeyFingerprint)
        return try await withSFTP(configuration, validator: validator) { sftp in
            let buffer = try await sftp.withFile(filePath: remotePath, flags: .read) { file in
                try await file.readAll()
            }
            return Data(buffer.readableBytesView)
        }
    }

    static func exists(_ remotePath: String, configuration: SFTPConfiguration) async throws -> Bool {
        let validator = SFTPHostKeyValidator(expected: configuration.hostKeyFingerprint)
        return try await withSFTP(configuration, validator: validator) { sftp in
            (try? await sftp.getAttributes(at: remotePath)) != nil
        }
    }

    static func probe(_ configuration: SFTPConfiguration) async throws -> String {
        let validator = SFTPHostKeyValidator(expected: configuration.hostKeyFingerprint)
        do {
            try await withSFTP(configuration, validator: validator) { sftp in
                _ = try await sftp.getRealPath(atPath: ".")
            }
        } catch {
            if let fingerprint = validator.presentedFingerprint, case .connectionFailed = error as? SFTPError {
                throw SFTPProbeError(fingerprint: fingerprint, underlying: error.localizedDescription)
            }
            throw error
        }
        return validator.presentedFingerprint ?? ""
    }
}

struct SFTPProbeError: LocalizedError {
    let fingerprint: String
    let underlying: String

    var errorDescription: String? { underlying }
}

@MainActor
enum SFTPHostKeyTrust {
    static var persist: @MainActor (UUID, String) -> Void = { id, fingerprint in
        guard var uploader = CustomUploader.allCases.first(where: { $0.id == id }), uploader.sftp != nil else { return }
        guard uploader.sftp?.hostKeyFingerprint?.isEmpty ?? true else { return }
        uploader.sftp?.hostKeyFingerprint = fingerprint
        UploaderStore.save(uploader)
        Log.upload.info("Trusted the SFTP host key \(fingerprint, privacy: .public) for \(uploader.name, privacy: .public)")
    }
}

struct SFTPUploader: Uploader {
    let uploader: CustomUploader
    var now: @Sendable () -> Date = { Date() }

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let configuration = try resolvedConfiguration()
        let plan = try SFTPPlanner.plan(configuration: configuration, fileName: fileURL.lastPathComponent, date: now())
        let validator = SFTPHostKeyValidator(expected: configuration.hostKeyFingerprint)
        try await SFTPTransport.withSFTP(configuration, validator: validator) { sftp in
            await SFTPTransport.makeDirectories(plan.directories, in: sftp)
            try await SFTPTransport.write(fileURL, to: plan.remotePath, in: sftp, progress: progress)
        }
        if case let .trustOnFirstUse(fingerprint) = validator.decision {
            SFTPHostKeyTrust.persist(uploader.id, fingerprint)
        }
        guard let url = plan.resultURL ?? SFTPPlanner.fileURL(configuration: configuration, remotePath: plan.remotePath) else {
            throw RemotePathError.emptyPath
        }
        return UploadOutcome(
            url: url, deletionURL: nil, uploaderID: uploader.id, s3Key: plan.remotePath, isShareable: plan.resultURL != nil
        )
    }

    func delete(_ item: HistoryItem) async throws {
        guard let remotePath = item.s3Key else { return }
        let configuration = try resolvedConfiguration()
        let validator = SFTPHostKeyValidator(expected: configuration.hostKeyFingerprint)
        try await SFTPTransport.withSFTP(configuration, validator: validator) { sftp in
            try await sftp.remove(at: remotePath)
        }
    }

    private func resolvedConfiguration() throws -> SFTPConfiguration {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let configuration = try UploaderSecrets.resolvingSecrets(uploader).sftp else {
            throw UploadFailure.invalidSpecification([.missingRemoteConfiguration])
        }
        return configuration
    }
}
