import Foundation

public enum WebDAVAuthentication: String, Codable, CaseIterable, Sendable {
    case basic
    case digest

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let value = WebDAVAuthentication(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid WebDAV authentication: \(rawValue)")
        }
        self = value
    }
}

public struct WebDAVConfiguration: Codable, Hashable, Sendable {
    public var url: String
    public var username: String?
    public var password: String?
    public var authentication: WebDAVAuthentication?
    public var pathTemplate: String?
    public var createDirectories: Bool?
    public var publicURL: String?

    public init(
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        url = try container.decodeDynamic(String.self, forKey: .key(named: "url"))
        username = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "username"))
        password = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "password"))
        authentication = try container.decodeDynamicIfPresent(WebDAVAuthentication.self, forKey: .key(named: "authentication"))
        pathTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "pathtemplate"))
        createDirectories = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "createdirectories"))
        publicURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "publicurl"))
    }

    public var baseURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard UploaderValidator.isHTTPURL(trimmed) else { return nil }
        return URL(string: trimmed)
    }

    public var createsDirectories: Bool { createDirectories ?? true }
    public var authenticationMethod: WebDAVAuthentication { authentication ?? .basic }

    public func resourceURL(for path: String) -> URL? {
        guard let baseURL, var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.percentEncodedPath = RemotePath.joined(components.percentEncodedPath, S3Path.encode(path))
        return components.url
    }
}

public struct WebDAVRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]

    public init(method: String, url: URL, headers: [String: String]) {
        self.method = method
        self.url = url
        self.headers = headers
    }
}

public struct WebDAVPlan: Equatable, Sendable {
    public let path: String
    public let directories: [WebDAVRequest]
    public let upload: WebDAVRequest
    public let resultURL: URL

    public init(path: String, directories: [WebDAVRequest], upload: WebDAVRequest, resultURL: URL) {
        self.path = path
        self.directories = directories
        self.upload = upload
        self.resultURL = resultURL
    }
}

public enum WebDAVError: Error, Equatable {
    case invalidURL
    case directoryFailed(path: String, status: Int)
}

public enum WebDAVRequestBuilder {
    public static let directoryAcceptedStatuses: Set<Int> = [200, 201, 204, 301, 405]

    public static func authorizationHeader(username: String?, password: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        let token = Data("\(username):\(password ?? "")".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    public static func headers(for configuration: WebDAVConfiguration) -> [String: String] {
        guard configuration.authenticationMethod == .basic,
              let authorization = authorizationHeader(username: configuration.username, password: configuration.password)
        else { return [:] }
        return ["Authorization": authorization]
    }

    public static func plan(configuration: WebDAVConfiguration, fileName: String, contentType: String, date: Date = .init(), uuid: UUID = .init()) throws -> WebDAVPlan {
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

    public static func delete(configuration: WebDAVConfiguration, path: String) throws -> WebDAVRequest {
        guard let url = configuration.resourceURL(for: path) else { throw WebDAVError.invalidURL }
        return WebDAVRequest(method: "DELETE", url: url, headers: headers(for: configuration))
    }
}
