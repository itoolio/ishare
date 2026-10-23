import Alamofire
import AppKit
import Foundation
import UniformTypeIdentifiers

enum GitHubLinkStyle: String, Codable, CaseIterable, Sendable {
    case raw
    case blob
    case markdown

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let value = GitHubLinkStyle(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GitHub link style: \(rawValue)")
        }
        self = value
    }

    var titleKey: String {
        switch self {
        case .raw: "Raw file URL"
        case .blob: "GitHub page URL"
        case .markdown: "Markdown"
        }
    }
}

struct GitHubConfiguration: Codable, Hashable, Sendable {
    var repository: String
    var branch: String?
    var pathTemplate: String?
    var linkStyle: GitHubLinkStyle?
    var token: String?
    var textAsGist: Bool?
    var publicGists: Bool?
    var commitMessage: String?

    static let defaultPathTemplate = "{{date}}/{{uuid}}.{{ext}}"
    static let defaultCommitMessage = "Upload {{filename}} with ishare"
    static let tokenPermissions = "Contents: Read and write (only the upload repository), Gists: Read and write"
    static let deviceFlowScopes = "repo gist"

    init(
        repository: String, branch: String? = nil, pathTemplate: String? = nil, linkStyle: GitHubLinkStyle? = nil,
        token: String? = nil, textAsGist: Bool? = nil, publicGists: Bool? = nil, commitMessage: String? = nil
    ) {
        self.repository = repository
        self.branch = branch
        self.pathTemplate = pathTemplate
        self.linkStyle = linkStyle
        self.token = token
        self.textAsGist = textAsGist
        self.publicGists = publicGists
        self.commitMessage = commitMessage
    }

    enum CodingKeys: String, CodingKey {
        case repository
        case branch
        case pathTemplate = "pathtemplate"
        case linkStyle = "linkstyle"
        case token
        case textAsGist = "textasgist"
        case publicGists = "publicgists"
        case commitMessage = "commitmessage"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        repository = try container.decodeDynamic(String.self, forKey: .key(named: "repository"))
        branch = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "branch"))
        pathTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "pathtemplate"))
        linkStyle = try container.decodeDynamicIfPresent(GitHubLinkStyle.self, forKey: .key(named: "linkstyle"))
        token = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "token"))
        textAsGist = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "textasgist"))
        publicGists = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "publicgists"))
        commitMessage = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "commitmessage"))
    }

    var ownerAndName: (owner: String, name: String)? {
        let trimmed = repository.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
        return (parts[0], parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1])
    }

    var trimmedBranch: String? {
        branch?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    var sendsTextToGist: Bool { textAsGist ?? true }
    var style: GitHubLinkStyle { linkStyle ?? .raw }
}

enum GitHubError: LocalizedError, Equatable {
    case invalidRepository
    case missingToken
    case deviceFlow(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            "Enter the repository as owner/name".localized()
        case .missingToken:
            "Enter a GitHub personal access token or sign in with GitHub".localized()
        case let .deviceFlow(detail):
            String(format: "Signing in with GitHub failed: %@".localized(), detail)
        }
    }
}

enum GitHubReference: Equatable, Sendable {
    case contents(path: String, sha: String)
    case gist(id: String)

    var rawValue: String {
        switch self {
        case let .contents(path, sha): "contents:\(sha):\(path)"
        case let .gist(id): "gist:\(id)"
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix("gist:") {
            self = .gist(id: String(rawValue.dropFirst(5)))
            return
        }
        guard rawValue.hasPrefix("contents:") else { return nil }
        let rest = rawValue.dropFirst(9)
        guard let separator = rest.firstIndex(of: ":") else { return nil }
        self = .contents(path: String(rest[rest.index(after: separator)...]), sha: String(rest[..<separator]))
    }
}

enum GitHubAPI {
    static let baseURL = URL(string: "https://api.github.com")!
    static let rawHost = "https://raw.githubusercontent.com"
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    static var builtInClientID: String? {
        CloudProvider.clientID(fromInfoValue: Bundle.main.object(forInfoDictionaryKey: "ISHAREGitHubClientID") as? String)
    }

    static func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
    }

    static func isText(_ fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext) else { return MimeType.forExtension(ext).hasPrefix("text/") }
        if type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf) { return false }
        return type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml)
            || MimeType.forExtension(ext).hasPrefix("text/")
    }

    static func contentsURL(owner: String, name: String, path: String) -> URL {
        URL(string: "\(baseURL.absoluteString)/repos/\(S3Path.encodeSegment(owner))/\(S3Path.encodeSegment(name))/contents/\(S3Path.encode(path))")!
    }

    static func commitMessage(_ template: String?, fileName: String) -> String {
        let source = template?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? GitHubConfiguration.defaultCommitMessage
        return (try? ResponseTemplate.render(source) { $0.lowercased() == "filename" ? fileName : nil }) ?? source
    }

    static func createFileRequest(configuration: GitHubConfiguration, path: String, content: Data, token: String) throws -> APIRequest {
        guard let repository = configuration.ownerAndName else { throw GitHubError.invalidRepository }
        var body: [String: Any] = [
            "message": commitMessage(configuration.commitMessage, fileName: (path as NSString).lastPathComponent),
            "content": content.base64EncodedString(),
        ]
        if let branch = configuration.trimmedBranch {
            body["branch"] = branch
        }
        return .json("PUT", contentsURL(owner: repository.owner, name: repository.name, path: path), token: nil, body: body, headers: headers(token: token))
    }

    static func deleteFileRequest(configuration: GitHubConfiguration, path: String, sha: String, token: String) throws -> APIRequest {
        guard let repository = configuration.ownerAndName else { throw GitHubError.invalidRepository }
        var body: [String: Any] = ["message": "Delete \((path as NSString).lastPathComponent) with ishare", "sha": sha]
        if let branch = configuration.trimmedBranch {
            body["branch"] = branch
        }
        return .json("DELETE", contentsURL(owner: repository.owner, name: repository.name, path: path), token: nil, body: body, headers: headers(token: token))
    }

    static func createGistRequest(fileName: String, text: String, isPublic: Bool, token: String) -> APIRequest {
        .json("POST", baseURL.appending(path: "gists"), token: nil, body: [
            "description": "Shared with ishare",
            "public": isPublic,
            "files": [fileName: ["content": text]],
        ], headers: headers(token: token))
    }

    static func deleteGistRequest(id: String, token: String) -> APIRequest {
        .json("DELETE", baseURL.appending(path: "gists").appending(path: id), token: nil, headers: headers(token: token))
    }

    static func rawURL(configuration: GitHubConfiguration, path: String) -> String? {
        guard let repository = configuration.ownerAndName else { return nil }
        let ref = configuration.trimmedBranch ?? "HEAD"
        return "\(rawHost)/\(S3Path.encodeSegment(repository.owner))/\(S3Path.encodeSegment(repository.name))/\(S3Path.encode(ref))/\(S3Path.encode(path))"
    }

    static func markdown(fileName: String, url: String, isImage: Bool) -> String {
        let label = fileName.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return isImage ? "![\(label)](\(url))" : "[\(label)](\(url))"
    }

    static func contentsOutcome(_ data: Data, configuration: GitHubConfiguration, path: String, fileURL: URL) throws -> (link: String, clipboard: String?, reference: GitHubReference) {
        let object = try JSONValue.object(data)
        let sha = try JSONValue.require(object, "content", "sha")
        let storedPath = JSONValue.string(object, "content", "path") ?? path
        let blob = JSONValue.string(object, "content", "html_url")
        let raw = rawURL(configuration: configuration, path: storedPath)
        let link: String
        var clipboard: String?
        switch configuration.style {
        case .blob:
            link = blob ?? raw ?? ""
        case .raw:
            link = raw ?? blob ?? ""
        case .markdown:
            link = raw ?? blob ?? ""
            clipboard = markdown(fileName: fileURL.lastPathComponent, url: link, isImage: MimeType.isImageOrVideo(fileURL) && !["mp4", "mov"].contains(fileURL.pathExtension.lowercased()))
        }
        return (link, clipboard, .contents(path: storedPath, sha: sha))
    }

    static func gistOutcome(_ data: Data, configuration: GitHubConfiguration, fileName: String) throws -> (link: String, clipboard: String?, reference: GitHubReference) {
        let object = try JSONValue.object(data)
        let id = try JSONValue.require(object, "id")
        let page = try JSONValue.require(object, "html_url")
        let raw = ((object["files"] as? [String: Any])?[fileName] as? [String: Any])?["raw_url"] as? String
        switch configuration.style {
        case .raw: return (raw ?? page, nil, .gist(id: id))
        case .blob: return (page, nil, .gist(id: id))
        case .markdown: return (page, markdown(fileName: fileName, url: page, isImage: false), .gist(id: id))
        }
    }
}

struct GitHubDeviceCode: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let interval: Int
    let expiresIn: Int
}

enum GitHubDevicePoll: Equatable, Sendable {
    case pending
    case slowDown
    case token(String)
}

@MainActor
enum GitHubDeviceFlow {
    static var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    static func start(clientID: String) async throws -> GitHubDeviceCode {
        let request = OAuthRequests.formRequest(GitHubAPI.deviceCodeURL, fields: [("client_id", clientID), ("scope", GitHubConfiguration.deviceFlowScopes)])
        let object = try JSONValue.object(try await UploadService.response(of: UploadService.session.request(request)))
        return try deviceCode(from: object)
    }

    static func deviceCode(from object: [String: Any]) throws -> GitHubDeviceCode {
        guard let deviceCode = object["device_code"] as? String, let userCode = object["user_code"] as? String,
              let uri = (object["verification_uri"] as? String).flatMap(URL.init(string:))
        else {
            throw GitHubError.deviceFlow((object["error_description"] as? String) ?? (object["error"] as? String) ?? "device_code")
        }
        return GitHubDeviceCode(
            deviceCode: deviceCode, userCode: userCode, verificationURL: uri,
            interval: (object["interval"] as? NSNumber)?.intValue ?? 5, expiresIn: (object["expires_in"] as? NSNumber)?.intValue ?? 900
        )
    }

    static func pollResult(from object: [String: Any]) throws -> GitHubDevicePoll {
        if let token = object["access_token"] as? String, !token.isEmpty { return .token(token) }
        switch object["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied": throw OAuthError.cancelled
        case let error: throw GitHubError.deviceFlow((object["error_description"] as? String) ?? error ?? "access_token")
        }
    }

    static func waitForToken(clientID: String, code: GitHubDeviceCode) async throws -> String {
        var interval = max(1, code.interval)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        while Date() < deadline {
            try await sleep(.seconds(interval))
            let request = OAuthRequests.formRequest(GitHubAPI.accessTokenURL, fields: [
                ("client_id", clientID), ("device_code", code.deviceCode), ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ])
            let object = try JSONValue.object(try await UploadService.response(of: UploadService.session.request(request)))
            switch try pollResult(from: object) {
            case .pending: continue
            case .slowDown: interval += 5
            case let .token(token): return token
            }
        }
        throw GitHubError.deviceFlow("expired_token")
    }
}

struct GitHubUploader: Uploader {
    let uploader: CustomUploader
    var now: @Sendable () -> Date = { Date() }

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let (configuration, token) = try resolved()
        let result: (link: String, clipboard: String?, reference: GitHubReference)
        if configuration.sendsTextToGist, GitHubAPI.isText(fileURL) {
            let fileName = UploadFileName.lowercasingExtension(of: fileURL)
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let request = GitHubAPI.createGistRequest(fileName: fileName, text: text, isPublic: configuration.publicGists ?? false, token: token)
            result = try GitHubAPI.gistOutcome(try await CloudHTTP.send(request), configuration: configuration, fileName: fileName)
        } else {
            let path = try RemotePath.render(configuration.pathTemplate ?? GitHubConfiguration.defaultPathTemplate, fileName: fileURL.lastPathComponent, date: now())
            let content = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: fileURL) }.value
            let request = try GitHubAPI.createFileRequest(configuration: configuration, path: path, content: content, token: token)
            result = try GitHubAPI.contentsOutcome(try await CloudHTTP.send(request), configuration: configuration, path: path, fileURL: fileURL)
        }
        progress(1)
        guard let url = URL(string: result.link), url.scheme != nil else { throw UploadFailure.responseParsing(result.link) }
        var outcome = UploadOutcome(url: url, deletionURL: nil, uploaderID: uploader.id, s3Key: result.reference.rawValue)
        outcome.clipboardText = result.clipboard
        return outcome
    }

    func delete(_ item: HistoryItem) async throws {
        guard let reference = item.s3Key.flatMap(GitHubReference.init(rawValue:)) else { return }
        let (configuration, token) = try resolved()
        switch reference {
        case let .gist(id):
            _ = try await CloudHTTP.send(GitHubAPI.deleteGistRequest(id: id, token: token))
        case let .contents(path, sha):
            _ = try await CloudHTTP.send(try GitHubAPI.deleteFileRequest(configuration: configuration, path: path, sha: sha, token: token))
        }
    }

    private func resolved() throws -> (GitHubConfiguration, String) {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let configuration = try UploaderSecrets.resolvingSecrets(uploader).github else {
            throw UploadFailure.invalidSpecification([.missingRemoteConfiguration])
        }
        guard let token = configuration.token, !token.isEmpty else { throw GitHubError.missingToken }
        return (configuration, token)
    }
}
