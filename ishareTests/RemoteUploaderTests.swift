import Foundation
import ishareCore
import Testing
@testable import ishare

@MainActor
struct RemoteUploaderDefinitionTests {
    let date = Date(timeIntervalSince1970: 1_767_225_600)

    @Test func decodesTheWebDAVExample() throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/webdav.iscu"))
        #expect(uploader.kind == .webdav)
        let webdav = try #require(uploader.webdav)
        #expect(webdav.baseURL?.absoluteString == "https://cloud.example.com/remote.php/dav/files/USERNAME/ishare")
        #expect(webdav.authenticationMethod == .basic)
        #expect(webdav.createsDirectories)
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }

    @Test func decodesTheSFTPExampleAndAcceptsAnSFTPURLAsTheHost() throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/sftp.iscu"))
        #expect(uploader.kind == .sftp)
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
        let parsed = try CustomUploader.fromJSON(Data(#"{"name": "box", "uploaderType": "sftp", "sftp": {"url": "sftp://deploy@files.example.com:2222/srv/i", "password": "x"}}"#.utf8))
        #expect(parsed.sftp?.host == "files.example.com")
        #expect(parsed.sftp?.resolvedPort == 2222)
        #expect(parsed.sftp?.username == "deploy")
        #expect(parsed.sftp?.directory == "/srv/i")
    }

    @Test func decodesTheCloudAndGitHubExamples() throws {
        for (file, kind) in [("dropbox", UploaderKind.dropbox), ("google-drive", .googleDrive), ("onedrive", .oneDrive), ("github", .github)] {
            let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/\(file).iscu"))
            #expect(uploader.kind == kind)
        }
        let drive = try CustomUploader.fromJSON(Data(#"{"name": "d", "uploaderType": "google-drive"}"#.utf8))
        #expect(drive.kind == .googleDrive)
    }

    @Test func roundTripsTheNewConfigurationsThroughJSON() throws {
        let uploader = CustomUploader.sftp(name: "box", configuration: SFTPConfiguration(
            host: "h", port: 2200, username: "u", password: "p", pathTemplate: "{{uuid}}.{{ext}}", publicURL: "https://h/{{path}}",
            hostKeyFingerprint: "SHA256:abc"
        ))
        var withOverride = uploader
        withOverride.imageOptimization = ImageOptimizationOverride(enabled: true, format: .lossless)
        let decoded = try CustomUploader.fromJSON(withOverride.toJSON())
        #expect(decoded.sftp == withOverride.sftp)
        #expect(decoded.imageOptimization == withOverride.imageOptimization)
        #expect(decoded.renamed("other").sftp == withOverride.sftp)
        #expect(decoded.renamed("other").imageOptimization == withOverride.imageOptimization)
    }

    @Test func reportsMissingSFTPCredentialsAndBadPorts() {
        let uploader = CustomUploader.sftp(name: "box", configuration: SFTPConfiguration(host: "", port: 70000, username: ""))
        let issues = UploaderValidator.issues(for: uploader)
        #expect(issues.contains(.missingRemoteField("host")))
        #expect(issues.contains(.missingRemoteField("username")))
        #expect(issues.contains(.invalidPort))
        #expect(issues.contains(.missingSFTPCredentials))
        let webdav = CustomUploader.webdav(name: "dav", configuration: WebDAVConfiguration(url: "ftp://nope", publicURL: "files/{{path}}"))
        #expect(UploaderValidator.issues(for: webdav) == [.invalidWebDAVURL, .invalidPublicURLTemplate])
    }

    @Test func rendersRemotePathsAndTheirParentFolders() throws {
        let path = try RemotePath.render("{{date}}/{{filename}}", fileName: "Shot.PNG", date: date)
        #expect(path == "2026/01/01/Shot.png")
        #expect(RemotePath.directories(of: path) == ["2026", "2026/01", "2026/01/01"])
        #expect(try RemotePath.render("/../{{name}}/./x.{{ext}}", fileName: "a b.png", date: date) == "a b/x.png")
        let url = try RemotePath.publicURL("https://cdn.example.com/{{path}}", path: "2026/a b.png", fallback: nil)
        #expect(url?.absoluteString == "https://cdn.example.com/2026/a%20b.png")
    }

    @Test func movesRemoteSecretsIntoTheKeychainAndBack() throws {
        let uploader = CustomUploader.sftp(name: "box", configuration: SFTPConfiguration(
            host: "h", username: "u", privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----", passphrase: "pp"
        ))
        let stored = UploaderStore.prepared(uploader)
        #expect(stored.sftp?.privateKey == UploaderSecrets.placeholder)
        #expect(stored.sftp?.passphrase == UploaderSecrets.placeholder)
        #expect(stored.sftp?.password == nil)
        #expect(!String(decoding: try stored.toJSON(), as: UTF8.self).contains("BEGIN OPENSSH"))
        let resolved = try UploaderSecrets.resolvingSecrets(stored)
        #expect(resolved.sftp?.privateKey == "-----BEGIN OPENSSH PRIVATE KEY-----")
        #expect(resolved.sftp?.passphrase == "pp")
        #expect(UploaderSecrets.exporting(stored, includeSecrets: false).sftp?.privateKey == nil)
        #expect(UploaderSecrets.exporting(stored, includeSecrets: true).sftp?.privateKey == "-----BEGIN OPENSSH PRIVATE KEY-----")
        UploaderSecrets.removeSecrets(for: stored.id)
        #expect(throws: UploaderSecretError.missingSecret("box")) { try UploaderSecrets.resolvingSecrets(stored) }
    }

    @Test func storesGitHubTokensInTheKeychain() throws {
        let uploader = CustomUploader.github(name: "gh", configuration: GitHubConfiguration(repository: "me/shots", token: "github_pat_123"))
        let stored = UploaderStore.prepared(uploader)
        #expect(stored.github?.token == UploaderSecrets.placeholder)
        #expect(try UploaderSecrets.resolvingSecrets(stored).github?.token == "github_pat_123")
        #expect(UploaderSecrets.hasExportableSecrets(stored))
    }
}

@MainActor
struct SFTPPlanningTests {
    @Test func plansTheRemotePathFoldersAndPublicURL() throws {
        let configuration = SFTPConfiguration(
            host: "files.example.com", username: "deploy", password: "x", directory: "/srv/www/", pathTemplate: "{{year}}/{{month}}/{{filename}}",
            publicURL: "https://i.example.com/{{path}}"
        )
        let plan = try SFTPPlanner.plan(configuration: configuration, fileName: "Shot.png", date: Date(timeIntervalSince1970: 1_767_225_600))
        #expect(plan.remotePath == "/srv/www/2026/01/Shot.png")
        #expect(plan.directories == ["/srv/www/2026", "/srv/www/2026/01"])
        #expect(plan.resultURL?.absoluteString == "https://i.example.com/2026/01/Shot.png")
        let noFolders = try SFTPPlanner.plan(configuration: SFTPConfiguration(host: "h", username: "u", createDirectories: false), fileName: "a.png")
        #expect(noFolders.directories.isEmpty)
        #expect(noFolders.resultURL == nil)
        #expect(SFTPPlanner.fileURL(configuration: configuration, remotePath: plan.remotePath)?.absoluteString == "sftp://deploy@files.example.com/srv/www/2026/01/Shot.png")
    }

    @Test func formatsFingerprintsLikeOpenSSH() throws {
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test@example"
        let fingerprint = try #require(SSHFingerprint.sha256(openSSHPublicKey: key))
        #expect(fingerprint.hasPrefix("SHA256:"))
        #expect(!fingerprint.hasSuffix("="))
        #expect(SSHFingerprint.matches(fingerprint, fingerprint.replacingOccurrences(of: "SHA256:", with: "") + "="))
    }

    @Test func trustsOnFirstUseAndRejectsChangedHostKeys() {
        #expect(SFTPHostKeyDecision.evaluate(expected: nil, presented: "SHA256:new") == .trustOnFirstUse("SHA256:new"))
        #expect(SFTPHostKeyDecision.evaluate(expected: " ", presented: "SHA256:new") == .trustOnFirstUse("SHA256:new"))
        #expect(SFTPHostKeyDecision.evaluate(expected: "SHA256:abc", presented: "SHA256:abc") == .trusted)
        #expect(SFTPHostKeyDecision.evaluate(expected: "SHA256:abc", presented: "SHA256:xyz") == .mismatch(expected: "SHA256:abc", presented: "SHA256:xyz"))
    }

    @Test func persistsAFingerprintTrustedOnFirstUse() {
        let original = SFTPHostKeyTrust.persist
        defer { SFTPHostKeyTrust.persist = original }
        var persisted: [(UUID, String)] = []
        SFTPHostKeyTrust.persist = { persisted.append(($0, $1)) }
        let id = UUID()
        SFTPHostKeyTrust.persist(id, "SHA256:abc")
        #expect(persisted.first?.0 == id)
    }

    @Test func refusesKeysItCannotRead() {
        let configuration = SFTPConfiguration(host: "h", username: "u", privateKey: "not a key")
        #expect(throws: SFTPError.self) { try SFTPAuthentication.method(for: configuration) }
        #expect(throws: SFTPError.missingCredentials) { try SFTPAuthentication.method(for: SFTPConfiguration(host: "h", username: "u")) }
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct WebDAVUploaderTests {
        let date = Date(timeIntervalSince1970: 1_767_225_600)

        init() {
            UploadService.session = StubURLProtocol.makeSession()
        }

        func uploader(authentication: WebDAVAuthentication? = nil, publicURL: String? = "https://files.example.com/{{path}}", createDirectories: Bool? = nil) -> CustomUploader {
            .webdav(name: "dav", configuration: WebDAVConfiguration(
                url: "https://dav.example.com/remote.php/dav/files/me/", username: "me", password: "secret", authentication: authentication,
                pathTemplate: "{{date}}/{{filename}}", createDirectories: createDirectories, publicURL: publicURL
            ))
        }

        @Test func buildsMKCOLRequestsForEveryFolderAndAPUTForTheFile() throws {
            let plan = try WebDAVRequestBuilder.plan(
                configuration: try #require(uploader().webdav), fileName: "Shot 1.png", contentType: "image/png", date: date
            )
            #expect(plan.directories.map(\.method) == ["MKCOL", "MKCOL", "MKCOL"])
            #expect(plan.directories.map(\.url.absoluteString) == [
                "https://dav.example.com/remote.php/dav/files/me/2026/",
                "https://dav.example.com/remote.php/dav/files/me/2026/01/",
                "https://dav.example.com/remote.php/dav/files/me/2026/01/01/",
            ])
            #expect(plan.upload.url.absoluteString == "https://dav.example.com/remote.php/dav/files/me/2026/01/01/Shot%201.png")
            #expect(plan.upload.headers["Authorization"] == "Basic bWU6c2VjcmV0")
            #expect(plan.upload.headers["Content-Type"] == "image/png")
            #expect(plan.resultURL.absoluteString == "https://files.example.com/2026/01/01/Shot%201.png")
        }

        @Test func uploadsWithBasicAuthAndToleratesExistingFolders() async throws {
            StubURLProtocol.reset { request in
                request.method == "MKCOL" ? StubResponse(status: request.url.path().hasSuffix("2026/") ? 405 : 201) : StubResponse(status: 201)
            }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            let target = WebDAVUploader(uploader: UploaderStore.prepared(uploader()), now: { [date] in date })
            let outcome = try await target.upload(fileURL: file) { _ in }
            #expect(outcome.url.absoluteString == "https://files.example.com/2026/01/01/shot.png")
            #expect(outcome.s3Key == "2026/01/01/shot.png")
            let captured = StubURLProtocol.captured
            #expect(captured.map(\.method) == ["MKCOL", "MKCOL", "MKCOL", "PUT"])
            #expect(captured.allSatisfy { $0.headers["Authorization"] == "Basic bWU6c2VjcmV0" })
            #expect(captured.last?.body == TestUploaders.png)
        }

        @Test func failsWhenAFolderCannotBeCreated() async throws {
            StubURLProtocol.reset { request in StubResponse(status: request.method == "MKCOL" ? 403 : 201) }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            await #expect(throws: WebDAVError.self) {
                _ = try await WebDAVUploader(uploader: uploader(), now: { [date] in date }).upload(fileURL: file) { _ in }
            }
        }

        @Test func returnsTheDAVURLWithoutAPublicURLAndSkipsFoldersWhenAsked() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 204) }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            let outcome = try await WebDAVUploader(uploader: uploader(publicURL: nil, createDirectories: false), now: { [date] in date })
                .upload(fileURL: file) { _ in }
            #expect(outcome.url.absoluteString == "https://dav.example.com/remote.php/dav/files/me/2026/01/01/shot.png")
            #expect(StubURLProtocol.captured.map(\.method) == ["PUT"])
        }

        @Test func digestAuthenticationDoesNotSendBasicCredentials() throws {
            let plan = try WebDAVRequestBuilder.plan(
                configuration: try #require(uploader(authentication: .digest).webdav), fileName: "a.png", contentType: "image/png", date: date
            )
            #expect(plan.upload.headers["Authorization"] == nil)
        }

        @Test func deletesTheUploadedFile() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 204) }
            try await WebDAVUploader(uploader: uploader()).delete(HistoryItem(fileUrl: "https://files.example.com/a.png", s3Key: "2026/a.png"))
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.method == "DELETE")
            #expect(request.url.absoluteString == "https://dav.example.com/remote.php/dav/files/me/2026/a.png")
        }
    }
}
