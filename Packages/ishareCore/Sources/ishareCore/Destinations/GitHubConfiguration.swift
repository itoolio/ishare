import Foundation

public enum GitHubLinkStyle: String, Codable, CaseIterable, Sendable {
    case raw
    case blob
    case markdown

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        guard let value = GitHubLinkStyle(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GitHub link style: \(rawValue)")
        }
        self = value
    }

    public var titleKey: String {
        switch self {
        case .raw: "Raw file URL"
        case .blob: "GitHub page URL"
        case .markdown: "Markdown"
        }
    }
}

public struct GitHubConfiguration: Codable, Hashable, Sendable {
    public var repository: String
    public var branch: String?
    public var pathTemplate: String?
    public var linkStyle: GitHubLinkStyle?
    public var token: String?
    public var textAsGist: Bool?
    public var publicGists: Bool?
    public var commitMessage: String?

    public static let defaultPathTemplate = "{{date}}/{{uuid}}.{{ext}}"
    public static let defaultCommitMessage = "Upload {{filename}} with ishare"
    public static let tokenPermissions = "Contents: Read and write (only the upload repository), Gists: Read and write"
    public static let deviceFlowScopes = "repo gist"

    public init(
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

    public init(from decoder: any Decoder) throws {
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

    public var ownerAndName: (owner: String, name: String)? {
        let trimmed = repository.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
        return (parts[0], parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1])
    }

    public var trimmedBranch: String? {
        branch?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    public var sendsTextToGist: Bool { textAsGist ?? true }
    public var style: GitHubLinkStyle { linkStyle ?? .raw }
}
