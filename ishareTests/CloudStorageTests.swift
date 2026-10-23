import Foundation
import ishareCore
import Testing
@testable import ishare

struct OAuthRequestTests {
    func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func buildsAuthorizationURLsWithPKCEAndOfflineAccess() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let dropbox = query(OAuthRequests.authorizationURL(provider: .dropbox, clientID: "app-key", pkce: pkce, state: "s1"))
        #expect(dropbox["code_challenge"] == pkce.challenge)
        #expect(dropbox["code_challenge_method"] == "S256")
        #expect(dropbox["token_access_type"] == "offline")
        #expect(dropbox["redirect_uri"] == "ishare-oauth://dropbox")
        #expect(dropbox["state"] == "s1")
        let google = query(OAuthRequests.authorizationURL(provider: .googleDrive, clientID: "123-abc.apps.googleusercontent.com", pkce: pkce, state: "s"))
        #expect(google["redirect_uri"] == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        #expect(google["scope"] == "https://www.googleapis.com/auth/drive.file")
        #expect(google["access_type"] == "offline")
        #expect(CloudProvider.googleDrive.callbackScheme(clientID: "123-abc.apps.googleusercontent.com") == "com.googleusercontent.apps.123-abc")
        let onedrive = query(OAuthRequests.authorizationURL(provider: .oneDrive, clientID: "guid", pkce: pkce, state: "s"))
        #expect(onedrive["scope"]?.contains("offline_access") == true)
        #expect(onedrive["redirect_uri"] == "ishare-oauth://onedrive")
    }

    @Test func encodesTheTokenAndRefreshRequestsAsForms() throws {
        let exchange = OAuthRequests.tokenRequest(provider: .dropbox, clientID: "key", code: "a/b+c", verifier: "v")
        let body = String(decoding: try #require(exchange.httpBody), as: UTF8.self)
        #expect(body == "grant_type=authorization_code&code=a%2Fb%2Bc&client_id=key&redirect_uri=ishare-oauth%3A%2F%2Fdropbox&code_verifier=v")
        #expect(exchange.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let refresh = OAuthRequests.refreshRequest(provider: .oneDrive, clientID: "id", refreshToken: "r")
        let refreshBody = String(decoding: try #require(refresh.httpBody), as: UTF8.self)
        #expect(refreshBody.hasPrefix("grant_type=refresh_token&refresh_token=r&client_id=id&scope="))
        #expect(refresh.url == CloudProvider.oneDrive.tokenEndpoint)
    }

    @Test func parsesTokensAndKeepsTheRefreshTokenWhenTheProviderOmitsIt() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let token = try OAuthRequests.token(from: Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8), now: now)
        #expect(token == OAuthToken(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 4600)))
        let refreshed = try OAuthRequests.token(from: Data(#"{"access_token":"b","expires_in":"60"}"#.utf8), now: now, previous: token)
        #expect(refreshed.refreshToken == "r")
        #expect(refreshed.expiresAt == Date(timeIntervalSince1970: 1060))
        #expect(throws: OAuthError.tokenResponse("bad code")) {
            try OAuthRequests.token(from: Data(#"{"error":"invalid_grant","error_description":"bad code"}"#.utf8))
        }
        #expect(token.needsRefresh(at: Date(timeIntervalSince1970: 4500)))
        #expect(!token.needsRefresh(at: Date(timeIntervalSince1970: 1000)))
    }

    @Test func readsTheAuthorizationCodeAndChecksTheState() throws {
        #expect(try OAuthRequests.authorizationCode(from: URL(string: "ishare-oauth://dropbox?code=abc&state=s")!, expectedState: "s") == "abc")
        #expect(throws: OAuthError.stateMismatch) {
            try OAuthRequests.authorizationCode(from: URL(string: "ishare-oauth://dropbox?code=abc&state=x")!, expectedState: "s")
        }
        #expect(throws: OAuthError.cancelled) {
            try OAuthRequests.authorizationCode(from: URL(string: "ishare-oauth://onedrive?error=access_denied&state=s")!, expectedState: "s")
        }
    }

    @Test func ignoresUnexpandedBuildSettingsAsClientIDs() {
        #expect(CloudProvider.clientID(fromInfoValue: "$(DROPBOX_CLIENT_ID)") == nil)
        #expect(CloudProvider.clientID(fromInfoValue: " ") == nil)
        #expect(CloudProvider.clientID(fromInfoValue: "abc") == "abc")
    }
}

struct CloudRequestTests {
    @Test func escapesNonASCIIInTheDropboxArgumentHeader() {
        let headers = DropboxAPI.uploadHeaders(path: "ishare/Grüße 😀.png", token: "t")
        let argument = headers["Dropbox-API-Arg"] ?? ""
        let isASCII = argument.unicodeScalars.allSatisfy(\.isASCII)
        #expect(isASCII)
        let expected = #""path":"/ishare/Gr\u00fc\u00dfe \ud83d\ude00.png""#
        #expect(argument.contains(expected))
        #expect(argument.contains(#""autorename":true"#))
        #expect(headers["Authorization"] == "Bearer t")
    }

    @Test func turnsDropboxLinksIntoDirectLinks() {
        #expect(DropboxAPI.directURL("https://www.dropbox.com/scl/fi/x/a.png?rlkey=k&dl=0") == "https://www.dropbox.com/scl/fi/x/a.png?rlkey=k&raw=1")
        #expect(
            DropboxAPI.existingLink(fromConflict: #"{"error": {".tag": "shared_link_already_exists", "shared_link_already_exists": {"metadata": {"url": "https://db.tt/x"}}}}"#)
                == "https://db.tt/x")
    }

    @Test func splitsLargeOneDriveUploadsIntoAlignedChunks() {
        let ranges = OneDriveAPI.chunkRanges(size: 25 * 1024 * 1024)
        #expect(ranges.count == 3)
        #expect(ranges.dropLast().allSatisfy { $0.count % (320 * 1024) == 0 })
        #expect(OneDriveAPI.contentRange(ranges[0], total: 25 * 1024 * 1024) == "bytes 0-10485759/26214400")
        #expect(
            OneDriveAPI.simpleUploadURL(path: "ishare/a b.png").absoluteString
                == "https://graph.microsoft.com/v1.0/me/drive/root:/ishare/a%20b.png:/content?@microsoft.graph.conflictBehavior=rename")
    }

    @Test func escapesDriveFolderQueries() throws {
        let request = GoogleDriveAPI.folderSearchRequest(name: "Bob's", parent: "root", token: "t")
        let query = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value)
        #expect(query == "name = 'Bob\\'s' and mimeType = 'application/vnd.google-apps.folder' and 'root' in parents and trashed = false")
    }

    @Test func buildsRemotePathsInsideTheChosenFolder() throws {
        let configuration = CloudStorageConfiguration(folder: "/ishare/shots/", pathTemplate: "{{date}}/{{filename}}")
        #expect(try configuration.remotePath(fileName: "A.PNG", date: Date(timeIntervalSince1970: 1_767_225_600)) == "ishare/shots/2026/01/01/A.png")
        #expect(try CloudStorageConfiguration().remotePath(fileName: "a.png") == "ishare/a.png")
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct CloudStorageUploaderTests {
        init() {
            UploadService.session = StubURLProtocol.makeSession()
            OAuthSession.now = { Date(timeIntervalSince1970: 10000) }
        }

        func signedIn(_ provider: CloudProvider, expiresAt: Date = Date(timeIntervalSince1970: 20000), folder: String = "ishare") throws -> CustomUploader {
            let uploader = CustomUploader.cloud(name: provider.rawValue, provider: provider, configuration: CloudStorageConfiguration(folder: folder, clientID: "client"))
            try OAuthTokenStore.save(OAuthToken(accessToken: "access", refreshToken: "refresh", expiresAt: expiresAt), for: uploader.id)
            return uploader
        }

        func body(_ request: CapturedRequest) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
        }

        @Test func uploadsToDropboxAndCreatesASharedLink() async throws {
            StubURLProtocol.reset { request in
                switch request.url.path() {
                case "/2/files/upload":
                    StubResponse(body: Data(#"{"id": "id:abc", "path_lower": "/ishare/shot.png"}"#.utf8))
                case "/2/sharing/create_shared_link_with_settings":
                    StubResponse(body: Data(#"{"url": "https://www.dropbox.com/scl/fi/abc/shot.png?rlkey=k&dl=0"}"#.utf8))
                default:
                    StubResponse(status: 404)
                }
            }
            let uploader = try signedIn(.dropbox)
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            #expect(outcome.url.absoluteString == "https://www.dropbox.com/scl/fi/abc/shot.png?rlkey=k&dl=0")
            #expect(outcome.s3Key == "id:abc")
            let captured = StubURLProtocol.captured
            #expect(captured[0].headers["Authorization"] == "Bearer access")
            #expect(captured[0].body == TestUploaders.png)
            #expect(body(captured[1])["path"] as? String == "/ishare/shot.png")
        }

        @Test func reusesAnExistingDropboxLinkOnConflict() async throws {
            StubURLProtocol.reset { request in
                switch request.url.path() {
                case "/2/files/upload":
                    StubResponse(body: Data(#"{"id": "id:abc", "path_display": "/ishare/shot.png"}"#.utf8))
                default:
                    StubResponse(
                        status: 409,
                        body: Data(#"{"error": {".tag": "shared_link_already_exists", "shared_link_already_exists": {"metadata": {"url": "https://www.dropbox.com/s/old"}}}}"#.utf8)
                    )
                }
            }
            let file = try Fixtures.temporaryFile(named: "shot.png", contents: TestUploaders.png)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(signedIn(.dropbox)))
            #expect(outcome.url.absoluteString == "https://www.dropbox.com/s/old")
        }

        @Test func refreshesAnExpiredTokenBeforeUploading() async throws {
            StubURLProtocol.reset { request in
                switch request.url.host() {
                case "api.dropboxapi.com" where request.url.path() == "/oauth2/token":
                    StubResponse(body: Data(#"{"access_token": "fresh", "expires_in": 14400}"#.utf8))
                case "content.dropboxapi.com":
                    StubResponse(body: Data(#"{"id": "id:1", "path_lower": "/ishare/a.png"}"#.utf8))
                default:
                    StubResponse(body: Data(#"{"url": "https://db.tt/a"}"#.utf8))
                }
            }
            let uploader = try signedIn(.dropbox, expiresAt: Date(timeIntervalSince1970: 10030))
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            _ = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            let captured = StubURLProtocol.captured
            #expect(captured[0].url.path() == "/oauth2/token")
            #expect(String(decoding: captured[0].body, as: UTF8.self).contains("refresh_token=refresh"))
            #expect(captured[1].headers["Authorization"] == "Bearer fresh")
            let stored = try #require(OAuthTokenStore.token(for: uploader.id))
            #expect(stored.accessToken == "fresh")
            #expect(stored.refreshToken == "refresh")
            #expect(stored.expiresAt == Date(timeIntervalSince1970: 24400))
        }

        @Test func refreshesAndRetriesOnceWhenTheAccessTokenIsRejected() async throws {
            StubURLProtocol.reset { request in
                if request.url.path() == "/oauth2/token" {
                    return StubResponse(body: Data(#"{"access_token": "second", "expires_in": 3600}"#.utf8))
                }
                guard request.headers["Authorization"] == "Bearer second" else { return StubResponse(status: 401) }
                return request.url.host() == "content.dropboxapi.com"
                    ? StubResponse(body: Data(#"{"id": "id:1"}"#.utf8))
                    : StubResponse(body: Data(#"{"url": "https://db.tt/a"}"#.utf8))
            }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(signedIn(.dropbox)))
            #expect(outcome.url.absoluteString == "https://db.tt/a")
            #expect(StubURLProtocol.captured.map { $0.url.path() } == ["/2/files/upload", "/oauth2/token", "/2/files/upload", "/2/sharing/create_shared_link_with_settings"])
        }

        @Test func reportsWhenNotSignedIn() async throws {
            let uploader = CustomUploader.cloud(name: "nobody", provider: .oneDrive, configuration: CloudStorageConfiguration(clientID: "c"))
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            await #expect(throws: OAuthError.notSignedIn("nobody")) {
                _ = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            }
        }

        @Test func uploadsToGoogleDriveWithAResumableSessionAndSharesTheFile() async throws {
            StubURLProtocol.reset { request in
                switch (request.method, request.url.host() ?? "", request.url.path()) {
                case ("GET", _, "/drive/v3/files"):
                    let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
                    return StubResponse(body: Data((query.contains("'ishare'") ? #"{"files": [{"id": "folder1"}]}"# : #"{"files": []}"#).utf8))
                case ("POST", _, "/drive/v3/files"):
                    return StubResponse(body: Data(#"{"id": "folder2"}"#.utf8))
                case ("POST", "www.googleapis.com", "/upload/drive/v3/files"):
                    return StubResponse(headers: ["Location": "https://www.googleapis.com/upload/drive/v3/files?upload_id=xyz"])
                case ("PUT", _, "/upload/drive/v3/files"):
                    return StubResponse(body: Data(#"{"id": "file9", "webViewLink": "https://drive.google.com/file/d/file9/view"}"#.utf8))
                case ("POST", _, "/drive/v3/files/file9/permissions"):
                    return StubResponse(body: Data(#"{"id": "anyoneWithLink"}"#.utf8))
                default:
                    return StubResponse(status: 404)
                }
            }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(signedIn(.googleDrive, folder: "ishare/shots")))
            #expect(outcome.url.absoluteString == "https://drive.google.com/file/d/file9/view")
            #expect(outcome.s3Key == "file9")
            let captured = StubURLProtocol.captured
            let start = try #require(captured.first { $0.url.path() == "/upload/drive/v3/files" && $0.method == "POST" })
            #expect(body(start)["name"] as? String == "a.png")
            #expect(body(start)["parents"] as? [String] == ["folder2"])
            #expect(start.headers["X-Upload-Content-Type"] == "image/png")
            let put = try #require(captured.first { $0.method == "PUT" })
            #expect(put.url.query()?.contains("upload_id=xyz") == true)
            #expect(put.body == TestUploaders.png)
            let permission = try #require(captured.last)
            #expect(body(permission)["type"] as? String == "anyone")
            #expect(body(permission)["role"] as? String == "reader")
        }

        @Test func uploadsToOneDriveAndFallsBackToAnOrganizationLink() async throws {
            StubURLProtocol.reset { request in
                if request.method == "PUT" {
                    return StubResponse(status: 201, body: Data(#"{"id": "item1", "name": "a.png"}"#.utf8))
                }
                let isAnonymous = String(decoding: request.body, as: UTF8.self).contains("anonymous")
                return isAnonymous
                    ? StubResponse(status: 403, body: Data(#"{"error": {"code": "accessDenied"}}"#.utf8))
                    : StubResponse(status: 201, body: Data(#"{"link": {"webUrl": "https://1drv.ms/i/s!abc"}}"#.utf8))
            }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(signedIn(.oneDrive)))
            #expect(outcome.url.absoluteString == "https://1drv.ms/i/s!abc")
            let captured = StubURLProtocol.captured
            #expect(captured[0].url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/ishare/a.png:/content?@microsoft.graph.conflictBehavior=rename")
            #expect(captured[1].url.path() == "/v1.0/me/drive/items/item1/createLink")
            #expect(body(captured[1])["type"] as? String == "view")
            #expect(captured.count == 3)
        }

        @Test func deletesFromEachProvider() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 200, body: Data("{}".utf8)) }
            for provider in CloudProvider.allCases {
                try await CloudStorageUploader(uploader: signedIn(provider), provider: provider).delete(HistoryItem(fileUrl: "https://x", s3Key: "file-id"))
            }
            let captured = StubURLProtocol.captured
            #expect(captured[0].url.absoluteString == "https://api.dropboxapi.com/2/files/delete_v2")
            #expect(body(captured[0])["path"] as? String == "file-id")
            #expect(captured[1].method == "DELETE")
            #expect(captured[1].url.absoluteString == "https://www.googleapis.com/drive/v3/files/file-id")
            #expect(captured[2].url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/items/file-id")
        }

        @Test func needsAClientIDWhenTheBuildHasNone() throws {
            let uploader = CustomUploader.cloud(name: "d", provider: .dropbox, configuration: CloudStorageConfiguration())
            if CloudProvider.dropbox.hasBuiltInClientID {
                #expect(UploaderValidator.issues(for: uploader).isEmpty)
            } else {
                #expect(UploaderValidator.issues(for: uploader) == [.missingCloudClientID])
                #expect(throws: OAuthError.self) { try OAuthSession.clientID(provider: .dropbox, configuration: nil) }
            }
            #expect(try OAuthSession.clientID(provider: .dropbox, configuration: CloudStorageConfiguration(clientID: " mine ")) == "mine")
        }
    }
}
