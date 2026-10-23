import Alamofire
import Foundation
import ishareCore
import Testing
@testable import ishare

enum RemoteIntegrationEnvironment {
    static let values = ProcessInfo.processInfo.environment

    static func nonEmpty(_ name: String) -> String? {
        guard let value = values[name]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    static var webdavURL: String? { nonEmpty("ISHARE_WEBDAV_URL") }
    static var webdavDigestURL: String? { nonEmpty("ISHARE_WEBDAV_DIGEST_URL") }
    static var webdavUser: String { nonEmpty("ISHARE_WEBDAV_USER") ?? "ishare" }
    static var webdavPassword: String { nonEmpty("ISHARE_WEBDAV_PASSWORD") ?? "ishare-ci-secret" }

    static var sftpHost: String? { nonEmpty("ISHARE_SFTP_HOST") }
    static var sftpPort: Int { nonEmpty("ISHARE_SFTP_PORT").flatMap(Int.init) ?? 2222 }
    static var sftpUser: String { nonEmpty("ISHARE_SFTP_USER") ?? "ishare" }
    static var sftpPassword: String? { nonEmpty("ISHARE_SFTP_PASSWORD") }
    static var sftpKeyPath: String? { nonEmpty("ISHARE_SFTP_KEY_PATH") }
    static var sftpDirectory: String { nonEmpty("ISHARE_SFTP_DIRECTORY") ?? "uploads" }

    static var hasWebDAV: Bool { webdavURL != nil }
    static var hasDigestWebDAV: Bool { webdavDigestURL != nil }
    static var hasSFTP: Bool { sftpHost != nil }
    static var hasSFTPKey: Bool { hasSFTP && sftpKeyPath != nil }

    static func payload(_ count: Int = 300_000) -> Data {
        Data((0 ..< count).map { UInt8(($0 * 37) % 253) })
    }
}

extension NetworkSuite {
    @MainActor
    @Suite(.enabled(if: RemoteIntegrationEnvironment.hasWebDAV, "Set ISHARE_WEBDAV_URL to run the WebDAV integration tests against a live server"))
    struct WebDAVIntegrationTests {
        let http: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }()

        let digestSession = Session(configuration: .ephemeral)

        init() {
            UploadService.session = Session(configuration: .ephemeral)
        }

        func uploader(url: String, authentication: WebDAVAuthentication? = nil) -> CustomUploader {
            .webdav(
                name: "dav-integration",
                configuration: WebDAVConfiguration(
                    url: url, username: RemoteIntegrationEnvironment.webdavUser, password: RemoteIntegrationEnvironment.webdavPassword,
                    authentication: authentication, pathTemplate: "integration/{{uuid}}/{{date}}/{{filename}}"
                ))
        }

        func get(_ url: URL, authenticated: Bool = true) async throws -> (Int, Data) {
            var request = URLRequest(url: url)
            if authenticated,
                let header = WebDAVRequestBuilder.authorizationHeader(
                    username: RemoteIntegrationEnvironment.webdavUser, password: RemoteIntegrationEnvironment.webdavPassword
                )
            {
                request.setValue(header, forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await http.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }

        @Test func uploadsIntoNewFoldersAndDeletes() async throws {
            let uploader = uploader(url: try #require(RemoteIntegrationEnvironment.webdavURL))
            let bytes = RemoteIntegrationEnvironment.payload()
            let file = try Fixtures.temporaryFile(named: "Dav Shot.PNG", contents: bytes)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            let path = try #require(outcome.s3Key)
            #expect(path.hasPrefix("integration/") && path.hasSuffix("/Dav Shot.png"))
            #expect(RemotePath.directories(of: path).count == 5)
            let (status, body) = try await get(outcome.url)
            #expect(status == 200)
            #expect(body == bytes)
            let second = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            #expect(second.s3Key != path)
            try await WebDAVUploader(uploader: uploader).delete(HistoryItem(fileUrl: outcome.url.absoluteString, s3Key: path))
            let (deleted, _) = try await get(outcome.url)
            #expect(deleted == 404)
        }

        @Test func rejectsWrongCredentials() async throws {
            var uploader = uploader(url: try #require(RemoteIntegrationEnvironment.webdavURL))
            uploader.webdav?.password = "wrong"
            let file = try Fixtures.temporaryFile(named: "denied.png", contents: TestUploaders.png)
            await #expect(throws: (any Error).self) {
                _ = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            }
        }

        @Test(.enabled(if: RemoteIntegrationEnvironment.hasDigestWebDAV, "Set ISHARE_WEBDAV_DIGEST_URL to test digest authentication"))
        func uploadsWithDigestAuthentication() async throws {
            let uploader = uploader(url: try #require(RemoteIntegrationEnvironment.webdavDigestURL), authentication: .digest)
            let bytes = RemoteIntegrationEnvironment.payload(50000)
            let file = try Fixtures.temporaryFile(named: "digest.png", contents: bytes)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            let (unauthenticated, _) = try await get(outcome.url, authenticated: false)
            #expect(unauthenticated == 401)
            let credential = URLCredential(user: RemoteIntegrationEnvironment.webdavUser, password: RemoteIntegrationEnvironment.webdavPassword, persistence: .forSession)
            let response = await digestSession.request(outcome.url).authenticate(with: credential).serializingData().response
            #expect(response.response?.statusCode == 200)
            #expect(response.data == bytes)
        }
    }

    @MainActor
    @Suite(.enabled(if: RemoteIntegrationEnvironment.hasSFTP, "Set ISHARE_SFTP_HOST to run the SFTP integration tests against a live server"))
    struct SFTPIntegrationTests {
        func configuration(password: String? = RemoteIntegrationEnvironment.sftpPassword, privateKey: String? = nil, fingerprint: String? = nil) throws -> SFTPConfiguration {
            SFTPConfiguration(
                host: try #require(RemoteIntegrationEnvironment.sftpHost), port: RemoteIntegrationEnvironment.sftpPort,
                username: RemoteIntegrationEnvironment.sftpUser, password: password, privateKey: privateKey,
                directory: RemoteIntegrationEnvironment.sftpDirectory, pathTemplate: "integration/{{uuid}}/{{year}}/{{filename}}",
                publicURL: "https://files.example.com/{{path}}", hostKeyFingerprint: fingerprint
            )
        }

        func read(_ remotePath: String, configuration: SFTPConfiguration) async throws -> Data {
            try await SFTPTransport.contents(of: remotePath, configuration: configuration)
        }

        func exists(_ remotePath: String, configuration: SFTPConfiguration) async throws -> Bool {
            try await SFTPTransport.exists(remotePath, configuration: configuration)
        }

        @Test(.enabled(if: RemoteIntegrationEnvironment.sftpPassword != nil, "Set ISHARE_SFTP_PASSWORD to test password sign-in"))
        func uploadsWithAPasswordTrustsTheHostKeyAndDeletes() async throws {
            let original = SFTPHostKeyTrust.persist
            var trusted: [String] = []
            SFTPHostKeyTrust.persist = { _, fingerprint in trusted.append(fingerprint) }
            defer { SFTPHostKeyTrust.persist = original }
            let configuration = try configuration()
            let uploader = CustomUploader.sftp(name: "sftp-integration", configuration: configuration)
            let bytes = RemoteIntegrationEnvironment.payload()
            let file = try Fixtures.temporaryFile(named: "SFTP Shot.PNG", contents: bytes)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            let remotePath = try #require(outcome.s3Key)
            #expect(remotePath.hasPrefix(RemoteIntegrationEnvironment.sftpDirectory + "/integration/"))
            #expect(remotePath.hasSuffix("/SFTP Shot.png"))
            #expect(outcome.url.absoluteString.hasPrefix("https://files.example.com/integration/"))
            let fingerprint = try #require(trusted.first)
            #expect(fingerprint.hasPrefix("SHA256:"))
            let pinned = try self.configuration(fingerprint: fingerprint)
            #expect(try await read(remotePath, configuration: pinned) == bytes)
            let probed = try await SFTPTransport.probe(pinned)
            #expect(SSHFingerprint.matches(probed, fingerprint))
            let pinnedUploader = CustomUploader.sftp(name: "sftp-integration", configuration: pinned)
            _ = try await UploadService.upload(fileURL: file, to: .custom(pinnedUploader))
            #expect(trusted.count == 1)
            try await SFTPUploader(uploader: pinnedUploader).delete(HistoryItem(fileUrl: outcome.url.absoluteString, s3Key: remotePath))
            #expect(try await exists(remotePath, configuration: pinned) == false)
        }

        @Test(.enabled(if: RemoteIntegrationEnvironment.sftpPassword != nil, "Set ISHARE_SFTP_PASSWORD to test password sign-in"))
        func refusesAChangedHostKey() async throws {
            let configuration = try configuration(fingerprint: "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
            let file = try Fixtures.temporaryFile(named: "mitm.png", contents: TestUploaders.png)
            do {
                _ = try await UploadService.upload(fileURL: file, to: .custom(.sftp(name: "pinned", configuration: configuration)))
                Issue.record("The upload should fail when the host key doesn't match")
            } catch let SFTPError.hostKeyMismatch(expected, presented) {
                #expect(expected == "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                #expect(presented.hasPrefix("SHA256:"))
            }
        }

        @Test(.enabled(if: RemoteIntegrationEnvironment.hasSFTPKey, "Set ISHARE_SFTP_KEY_PATH to test private key sign-in"))
        func uploadsWithAPrivateKey() async throws {
            let key = try String(contentsOfFile: try #require(RemoteIntegrationEnvironment.sftpKeyPath), encoding: .utf8)
            let configuration = try configuration(password: nil, privateKey: key)
            let original = SFTPHostKeyTrust.persist
            SFTPHostKeyTrust.persist = { _, _ in }
            defer { SFTPHostKeyTrust.persist = original }
            let bytes = RemoteIntegrationEnvironment.payload(70000)
            let file = try Fixtures.temporaryFile(named: "key.png", contents: bytes)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(.sftp(name: "key", configuration: configuration)))
            #expect(try await read(try #require(outcome.s3Key), configuration: configuration) == bytes)
        }

        @Test(.enabled(if: RemoteIntegrationEnvironment.sftpPassword != nil, "Set ISHARE_SFTP_PASSWORD to test password sign-in"))
        func rejectsAWrongPassword() async throws {
            let configuration = try configuration(password: "wrong")
            let file = try Fixtures.temporaryFile(named: "denied.png", contents: TestUploaders.png)
            await #expect(throws: SFTPError.self) {
                _ = try await UploadService.upload(fileURL: file, to: .custom(.sftp(name: "denied", configuration: configuration)))
            }
        }
    }
}
