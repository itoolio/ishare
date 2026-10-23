import Foundation

public struct CloudStorageConfiguration: Codable, Hashable, Sendable {
    public var folder: String?
    public var pathTemplate: String?
    public var clientID: String?
    public var account: String?
    public var directLink: Bool?

    public static let defaultFolder = "ishare"
    public static let defaultPathTemplate = "{{filename}}"

    public init(folder: String? = nil, pathTemplate: String? = nil, clientID: String? = nil, account: String? = nil, directLink: Bool? = nil) {
        self.folder = folder
        self.pathTemplate = pathTemplate
        self.clientID = clientID
        self.account = account
        self.directLink = directLink
    }

    enum CodingKeys: String, CodingKey {
        case folder
        case pathTemplate = "pathtemplate"
        case clientID = "clientid"
        case account
        case directLink = "directlink"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        folder = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "folder"))
        pathTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "pathtemplate"))
        clientID = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "clientid"))
        account = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "account"))
        directLink = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "directlink"))
    }

    public var folderPath: String {
        FolderPaths.sanitized(folder ?? Self.defaultFolder)
    }

    public func remotePath(fileName: String, date: Date = .init(), uuid: UUID = .init()) throws -> String {
        let relative = try RemotePath.render(pathTemplate ?? Self.defaultPathTemplate, fileName: fileName, date: date, uuid: uuid)
        return folderPath.isEmpty ? relative : "\(folderPath)/\(relative)"
    }
}
