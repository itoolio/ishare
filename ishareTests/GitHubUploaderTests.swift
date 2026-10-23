import Foundation
import ishareCore
import Synchronization
import Testing
@testable import ishare

struct GitHubDefinitionTests {
    @Test func parsesRepositoriesInSeveralForms() {
        #expect(GitHubConfiguration(repository: "me/shots").ownerAndName?.name == "shots")
        #expect(GitHubConfiguration(repository: "https://github.com/me/shots.git").ownerAndName?.owner == "me")
        #expect(GitHubConfiguration(repository: "https://github.com/me/shots.git").ownerAndName?.name == "shots")
        #expect(GitHubConfiguration(repository: "shots").ownerAndName == nil)
        #expect(GitHubConfiguration(repository: "a/b/c").ownerAndName == nil)
    }

    @Test func roundTripsHistoryReferences() {
        let contents = GitHubReference.contents(path: "2026/01/a:b.png", sha: "abc123")
        #expect(GitHubReference(rawValue: contents.rawValue) == contents)
        #expect(GitHubReference(rawValue: GitHubReference.gist(id: "g1").rawValue) == .gist(id: "g1"))
        #expect(GitHubReference(rawValue: "other") == nil)
    }

    @Test func detectsTextSnippets() throws {
        let directory = FileManager.default.temporaryDirectory
        #expect(GitHubAPI.isText(directory.appending(path: "a.txt")))
        #expect(GitHubAPI.isText(directory.appending(path: "a.swift")))
        #expect(GitHubAPI.isText(directory.appending(path: "a.json")))
        #expect(!GitHubAPI.isText(directory.appending(path: "a.png")))
        #expect(!GitHubAPI.isText(directory.appending(path: "a.mp4")))
        #expect(!GitHubAPI.isText(directory.appending(path: "a.pdf")))
    }

    @Test @MainActor func parsesDeviceFlowResponses() throws {
        let code = try GitHubDeviceFlow.deviceCode(from: [
            "device_code": "dc", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "interval": 5, "expires_in": 900,
        ])
        #expect(code.userCode == "ABCD-1234")
        #expect(try GitHubDeviceFlow.pollResult(from: ["error": "authorization_pending"]) == .pending)
        #expect(try GitHubDeviceFlow.pollResult(from: ["error": "slow_down"]) == .slowDown)
        #expect(try GitHubDeviceFlow.pollResult(from: ["access_token": "gho_x", "token_type": "bearer"]) == .token("gho_x"))
        #expect(throws: OAuthError.cancelled) { try GitHubDeviceFlow.pollResult(from: ["error": "access_denied"]) }
        #expect(throws: GitHubError.self) { try GitHubDeviceFlow.pollResult(from: ["error": "expired_token"]) }
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct GitHubUploaderTests {
        let date = Date(timeIntervalSince1970: 1_767_225_600)

        init() {
            UploadService.session = StubURLProtocol.makeSession()
        }

        func uploader(style: GitHubLinkStyle? = nil, branch: String? = "main", publicGists: Bool? = nil) -> CustomUploader {
            UploaderStore.prepared(
                .github(
                    name: "gh",
                    configuration: GitHubConfiguration(
                        repository: "me/shots", branch: branch, pathTemplate: "{{date}}/{{filename}}", linkStyle: style, token: "github_pat_1",
                        publicGists: publicGists
                    )))
        }

        func body(_ request: CapturedRequest) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
        }

        nonisolated static let contentsResponse = Data(
            #"""
            {"content": {"path": "2026/01/01/shot.png", "sha": "s1", "html_url": "https://github.com/me/shots/blob/main/2026/01/01/shot.png",
              "download_url": "https://raw.githubusercontent.com/me/shots/main/2026/01/01/shot.png"}, "commit": {"sha": "c1"}}
            """#.utf8)

        @Test func commitsImagesThroughTheContentsAPIAndReturnsTheRawURL() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 201, body: Self.contentsResponse) }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            let outcome = try await GitHubUploader(uploader: uploader(), now: { [date] in date }).upload(fileURL: file) { _ in }
            #expect(outcome.url.absoluteString == "https://raw.githubusercontent.com/me/shots/main/2026/01/01/shot.png")
            #expect(outcome.s3Key == "contents:s1:2026/01/01/shot.png")
            #expect(outcome.clipboardText == nil)
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.method == "PUT")
            #expect(request.url.absoluteString == "https://api.github.com/repos/me/shots/contents/2026/01/01/shot.png")
            #expect(request.headers["Authorization"] == "Bearer github_pat_1")
            #expect(request.headers["X-GitHub-Api-Version"] == "2022-11-28")
            let json = body(request)
            #expect(json["content"] as? String == TestUploaders.png.base64EncodedString())
            #expect(json["branch"] as? String == "main")
            #expect(json["message"] as? String == "Upload shot.png with ishare")
        }

        @Test func returnsTheBlobURLOrMarkdownWhenChosen() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 201, body: Self.contentsResponse) }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            let blob = try await GitHubUploader(uploader: uploader(style: .blob), now: { [date] in date }).upload(fileURL: file) { _ in }
            #expect(blob.url.absoluteString == "https://github.com/me/shots/blob/main/2026/01/01/shot.png")
            let markdown = try await GitHubUploader(uploader: uploader(style: .markdown), now: { [date] in date }).upload(fileURL: file) { _ in }
            #expect(markdown.clipboardText == "![shot.png](https://raw.githubusercontent.com/me/shots/main/2026/01/01/shot.png)")
        }

        @Test func usesHEADForRawLinksWithoutABranch() {
            let configuration = GitHubConfiguration(repository: "me/shots")
            #expect(GitHubAPI.rawURL(configuration: configuration, path: "a b.png") == "https://raw.githubusercontent.com/me/shots/HEAD/a%20b.png")
        }

        @Test func sendsTextSnippetsToASecretGist() async throws {
            StubURLProtocol.reset { _ in
                StubResponse(
                    status: 201,
                    body: Data(
                        #"{"id": "g1", "html_url": "https://gist.github.com/me/g1", "files": {"note.md": {"raw_url": "https://gist.githubusercontent.com/me/g1/raw/note.md"}}}"#
                            .utf8))
            }
            let file = try Fixtures.temporaryFile(named: "note.md", contents: Data("# Hello".utf8))
            let outcome = try await GitHubUploader(uploader: uploader(style: .blob)).upload(fileURL: file) { _ in }
            #expect(outcome.url.absoluteString == "https://gist.github.com/me/g1")
            #expect(outcome.s3Key == "gist:g1")
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.url.absoluteString == "https://api.github.com/gists")
            let json = body(request)
            #expect(json["public"] as? Bool == false)
            #expect(((json["files"] as? [String: Any])?["note.md"] as? [String: Any])?["content"] as? String == "# Hello")
            let raw = try await GitHubUploader(uploader: uploader(publicGists: true)).upload(fileURL: file) { _ in }
            #expect(raw.url.absoluteString == "https://gist.githubusercontent.com/me/g1/raw/note.md")
            #expect(body(try #require(StubURLProtocol.lastRequest))["public"] as? Bool == true)
        }

        @Test func deliversMarkdownToTheClipboardAfterUploading() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 201, body: Self.contentsResponse) }
            let spy = UploadEnvironmentSpy()
            UploadCoordinator.environment = spy
            defer { UploadCoordinator.environment = LiveUploadEnvironment() }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, primary: .custom(uploader(style: .markdown)), additional: [], shortener: .none, localFileURL: nil)
            #expect(spy.delivered.first?.host() == "raw.githubusercontent.com")
            #expect(spy.copiedText.first?.hasPrefix("![shot.png](https://raw.githubusercontent.com/me/shots/main/") == true)
        }

        @Test func deletesCommittedFilesAndGists() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 200, body: Data("{}".utf8)) }
            let target = GitHubUploader(uploader: uploader())
            try await target.delete(HistoryItem(fileUrl: "https://x", s3Key: "contents:s1:2026/a.png"))
            let deleteFile = try #require(StubURLProtocol.lastRequest)
            #expect(deleteFile.method == "DELETE")
            #expect(deleteFile.url.path() == "/repos/me/shots/contents/2026/a.png")
            #expect(body(deleteFile)["sha"] as? String == "s1")
            try await target.delete(HistoryItem(fileUrl: "https://x", s3Key: "gist:g1"))
            #expect(StubURLProtocol.lastRequest?.url.absoluteString == "https://api.github.com/gists/g1")
        }

        @Test func requiresAToken() {
            let uploader = CustomUploader.github(name: "gh", configuration: GitHubConfiguration(repository: "me/shots"))
            #expect(UploaderValidator.issues(for: uploader) == [.missingRemoteField("access token")])
        }

        @Test func pollsTheDeviceFlowUntilGitHubIssuesAToken() async throws {
            let original = GitHubDeviceFlow.sleep
            GitHubDeviceFlow.sleep = { _ in }
            defer { GitHubDeviceFlow.sleep = original }
            let responses = PollSequence([#"{"error": "authorization_pending"}"#, #"{"error": "slow_down"}"#, #"{"access_token": "gho_abc"}"#])
            StubURLProtocol.reset { _ in StubResponse(body: Data(responses.next().utf8)) }
            let code = GitHubDeviceCode(deviceCode: "dc", userCode: "U", verificationURL: URL(string: "https://github.com/login/device")!, interval: 1, expiresIn: 60)
            #expect(try await GitHubDeviceFlow.waitForToken(clientID: "cid", code: code) == "gho_abc")
            #expect(StubURLProtocol.captured.count == 3)
            #expect(String(decoding: StubURLProtocol.captured[0].body, as: UTF8.self).contains("device_code=dc"))
        }
    }
}

final class PollSequence: Sendable {
    private let values: [String]
    private let index = Mutex(0)

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        index.withLock { index in
            defer { index += 1 }
            return values[min(index, values.count - 1)]
        }
    }
}
