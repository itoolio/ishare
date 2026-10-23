import Foundation

public struct SFTPConfiguration: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int?
    public var username: String
    public var password: String?
    public var privateKey: String?
    public var passphrase: String?
    public var directory: String?
    public var pathTemplate: String?
    public var createDirectories: Bool?
    public var publicURL: String?
    public var hostKeyFingerprint: String?

    public static let defaultPort = 22

    public init(
        host: String, port: Int? = nil, username: String, password: String? = nil, privateKey: String? = nil,
        passphrase: String? = nil, directory: String? = nil, pathTemplate: String? = nil, createDirectories: Bool? = nil,
        publicURL: String? = nil, hostKeyFingerprint: String? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.privateKey = privateKey
        self.passphrase = passphrase
        self.directory = directory
        self.pathTemplate = pathTemplate
        self.createDirectories = createDirectories
        self.publicURL = publicURL
        self.hostKeyFingerprint = hostKeyFingerprint
    }

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case username
        case password
        case privateKey = "privatekey"
        case passphrase
        case directory
        case pathTemplate = "pathtemplate"
        case createDirectories = "createdirectories"
        case publicURL = "publicurl"
        case hostKeyFingerprint = "hostkeyfingerprint"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let rawHost = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "host"))
            ?? container.decodeDynamic(String.self, forKey: .key(named: "url"))
        let parsed = Self.parse(rawHost)
        host = parsed.host
        port = try container.decodeDynamicIfPresent(Int.self, forKey: .key(named: "port")) ?? parsed.port
        username = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "username")) ?? parsed.username ?? ""
        password = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "password"))
        privateKey = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "privatekey"))
        passphrase = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "passphrase"))
        directory = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "directory")) ?? parsed.directory
        pathTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "pathtemplate"))
        createDirectories = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "createdirectories"))
        publicURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "publicurl"))
        hostKeyFingerprint = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "hostkeyfingerprint"))
    }

    public static func parse(_ value: String) -> (host: String, port: Int?, username: String?, directory: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("sftp://"), let components = URLComponents(string: trimmed) else {
            return (trimmed, nil, nil, nil)
        }
        let path = components.path.isEmpty || components.path == "/" ? nil : components.path
        return (components.host ?? "", components.port, components.user, path)
    }

    public var resolvedPort: Int { port ?? Self.defaultPort }
    public var createsDirectories: Bool { createDirectories ?? true }
    public var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }

    public var usesPrivateKey: Bool {
        !(privateKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func remotePath(for relativePath: String) -> String {
        guard let directory = directory?.trimmingCharacters(in: .whitespaces), !directory.isEmpty else { return relativePath }
        return RemotePath.joined(directory, relativePath)
    }
}

public struct SFTPPlan: Equatable, Sendable {
    public let relativePath: String
    public let remotePath: String
    public let directories: [String]
    public let resultURL: URL?

    public init(relativePath: String, remotePath: String, directories: [String], resultURL: URL?) {
        self.relativePath = relativePath
        self.remotePath = remotePath
        self.directories = directories
        self.resultURL = resultURL
    }
}

public enum SFTPPlanner {
    public static func plan(configuration: SFTPConfiguration, fileName: String, date: Date = .init(), uuid: UUID = .init()) throws -> SFTPPlan {
        let relativePath = try RemotePath.render(configuration.pathTemplate, fileName: fileName, date: date, uuid: uuid)
        let remotePath = configuration.remotePath(for: relativePath)
        let directories = configuration.createsDirectories ? RemotePath.directories(of: relativePath).map(configuration.remotePath(for:)) : []
        let resultURL = try RemotePath.publicURL(configuration.publicURL, path: relativePath, fallback: nil)
        return SFTPPlan(relativePath: relativePath, remotePath: remotePath, directories: directories, resultURL: resultURL)
    }

    public static func fileURL(configuration: SFTPConfiguration, remotePath: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sftp"
        components.host = configuration.trimmedHost
        components.user = configuration.username.isEmpty ? nil : configuration.username
        components.port = configuration.port
        components.path = remotePath.hasPrefix("/") ? remotePath : "/" + remotePath
        return components.url
    }
}
