import Alamofire
import Foundation

enum WebDAVAuthentication: String, Codable, CaseIterable, Sendable {
    case basic
    case digest

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let value = WebDAVAuthentication(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid WebDAV authentication: \(rawValue)")
        }
        self = value
    }
}

struct WebDAVConfiguration: Codable, Hashable, Sendable {
    var url: String
    var username: String?
    var password: String?
    var authentication: WebDAVAuthentication?
    var pathTemplate: String?
    var createDirectories: Bool?
    var publicURL: String?

    init(
        url: String, username: String? = nil, password: String? = nil, authentication: WebDAVAuthentication? = nil,
        pathTemplate: String? = nil, createDirectories: Bool? = nil, publicURL: String? = nil
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.authentication = authentication
        self.pathTemplate = pathTemplate
        self.createDirectories = createDirectories
        self.publicURL = publicURL
    }

    enum CodingKeys: String, CodingKey {
        case url
        case username
        case password
        case authentication
        case pathTemplate = "pathtemplate"
        case createDirectories = "createdirectories"
        case publicURL = "publicurl"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        url = try container.decodeDynamic(String.self, forKey: .key(named: "url"))
        username = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "username"))
        password = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "password"))
        authentication = try container.decodeDynamicIfPresent(WebDAVAuthentication.self, forKey: .key(named: "authentication"))
        pathTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "pathtemplate"))
        createDirectories = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "createdirectories"))
        publicURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "publicurl"))
    }

    var baseURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard UploaderValidator.isHTTPURL(trimmed) else { return nil }
        return URL(string: trimmed)
    }

    var createsDirectories: Bool { createDirectories ?? true }
    var authenticationMethod: WebDAVAuthentication { authentication ?? .basic }

    func resourceURL(for path: String) -> URL? {
        guard let baseURL, var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.percentEncodedPath = RemotePath.joined(components.percentEncodedPath, S3Path.encode(path))
        return components.url
    }
}

struct WebDAVRequest: Equatable, Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
}

struct WebDAVPlan: Equatable, Sendable {
    let path: String
    let directories: [WebDAVRequest]
    let upload: WebDAVRequest
    let resultURL: URL
}

enum WebDAVError: LocalizedError, Equatable {
    case invalidURL
    case directoryFailed(path: String, status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The WebDAV URL must be a valid http or https URL".localized()
        case let .directoryFailed(path, status):
            String(format: "Creating the folder %@ on the WebDAV server failed with status %d".localized(), path, status)
        }
    }
}

enum WebDAVRequestBuilder {
    static let directoryAcceptedStatuses: Set<Int> = [200, 201, 204, 301, 405]

    static func authorizationHeader(username: String?, password: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        let token = Data("\(username):\(password ?? "")".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    static func headers(for configuration: WebDAVConfiguration) -> [String: String] {
        guard configuration.authenticationMethod == .basic,
              let authorization = authorizationHeader(username: configuration.username, password: configuration.password)
        else { return [:] }
        return ["Authorization": authorization]
    }

    static func plan(configuration: WebDAVConfiguration, fileName: String, contentType: String, date: Date = .init(), uuid: UUID = .init()) throws -> WebDAVPlan {
        let path = try RemotePath.render(configuration.pathTemplate, fileName: fileName, date: date, uuid: uuid)
        guard let uploadURL = configuration.resourceURL(for: path) else { throw WebDAVError.invalidURL }
        let base = headers(for: configuration)
        var directories: [WebDAVRequest] = []
        if configuration.createsDirectories {
            for directory in RemotePath.directories(of: path) {
                guard let url = configuration.resourceURL(for: directory + "/") else { throw WebDAVError.invalidURL }
                directories.append(WebDAVRequest(method: "MKCOL", url: url, headers: base))
            }
        }
        var uploadHeaders = base
        uploadHeaders["Content-Type"] = contentType
        let upload = WebDAVRequest(method: "PUT", url: uploadURL, headers: uploadHeaders)
        let resultURL = try RemotePath.publicURL(configuration.publicURL, path: path, fallback: uploadURL) ?? uploadURL
        return WebDAVPlan(path: path, directories: directories, upload: upload, resultURL: resultURL)
    }

    static func delete(configuration: WebDAVConfiguration, path: String) throws -> WebDAVRequest {
        guard let url = configuration.resourceURL(for: path) else { throw WebDAVError.invalidURL }
        return WebDAVRequest(method: "DELETE", url: url, headers: headers(for: configuration))
    }
}

struct WebDAVUploader: Uploader {
    let uploader: CustomUploader
    var now: @Sendable () -> Date = { Date() }

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let configuration = try resolvedConfiguration()
        let plan = try WebDAVRequestBuilder.plan(
            configuration: configuration, fileName: fileURL.lastPathComponent, contentType: MimeType.forFile(fileURL), date: now()
        )
        let credential = credential(for: configuration)
        for directory in plan.directories {
            try await createDirectory(directory, credential: credential)
        }
        var request = UploadService.session.upload(
            fileURL, to: plan.upload.url, method: .put, headers: HTTPHeaders(plan.upload.headers)
        )
        if let credential {
            request = request.authenticate(with: credential)
        }
        _ = try await UploadService.perform(request, progress: progress)
        return UploadOutcome(url: plan.resultURL, deletionURL: nil, uploaderID: uploader.id, s3Key: plan.path)
    }

    func delete(_ item: HistoryItem) async throws {
        guard let path = item.s3Key else { return }
        let configuration = try resolvedConfiguration()
        let built = try WebDAVRequestBuilder.delete(configuration: configuration, path: path)
        var request = UploadService.session.request(built.url, method: .delete, headers: HTTPHeaders(built.headers))
        if let credential = credential(for: configuration) {
            request = request.authenticate(with: credential)
        }
        _ = try await UploadService.response(of: request)
    }

    private func resolvedConfiguration() throws -> WebDAVConfiguration {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let configuration = try UploaderSecrets.resolvingSecrets(uploader).webdav else {
            throw UploadFailure.invalidSpecification([.missingRemoteConfiguration])
        }
        return configuration
    }

    private func credential(for configuration: WebDAVConfiguration) -> URLCredential? {
        guard configuration.authenticationMethod == .digest, let username = configuration.username, !username.isEmpty else { return nil }
        return URLCredential(user: username, password: configuration.password ?? "", persistence: .forSession)
    }

    private func createDirectory(_ directory: WebDAVRequest, credential: URLCredential?) async throws {
        var request = UploadService.session.request(directory.url, method: HTTPMethod(rawValue: directory.method), headers: HTTPHeaders(directory.headers))
        if let credential {
            request = request.authenticate(with: credential)
        }
        let response = await request.serializingData(emptyResponseCodes: Set(100 ..< 600)).response
        UploadDiagnostics.recorder?.record(response.response, body: response.data ?? Data())
        guard let status = response.response?.statusCode else {
            throw UploadFailure.transport(response.error?.localizedDescription ?? "The WebDAV server didn't respond")
        }
        guard WebDAVRequestBuilder.directoryAcceptedStatuses.contains(status) else {
            throw WebDAVError.directoryFailed(path: directory.url.path(percentEncoded: false), status: status)
        }
    }
}
