import Foundation

public struct LinkRewrite: Codable, Hashable, Sendable {
    public var host: String?
    public var scheme: String?
    public var pathPrefix: String?
    public var stripQuery: Bool?
    public var template: String?
    public var rewritesDeletionURL: Bool?

    public static let placeholders = ["url", "scheme", "host", "port", "path", "filename", "query", "fragment"]
    static let sampleURL = URL(string: "https://uploads.example.com/files/a1b2c3.png?token=abc")!

    public init(
        host: String? = nil, scheme: String? = nil, pathPrefix: String? = nil, stripQuery: Bool? = nil, template: String? = nil,
        rewritesDeletionURL: Bool? = nil
    ) {
        self.host = host
        self.scheme = scheme
        self.pathPrefix = pathPrefix
        self.stripQuery = stripQuery
        self.template = template
        self.rewritesDeletionURL = rewritesDeletionURL
    }

    enum CodingKeys: String, CodingKey {
        case host
        case scheme
        case pathPrefix = "pathprefix"
        case stripQuery = "stripquery"
        case template
        case rewritesDeletionURL = "rewritedeletionurl"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        host = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "host"))
        scheme = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "scheme"))
        pathPrefix = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "pathprefix"))
        stripQuery = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "stripquery"))
        template = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "template"))
        rewritesDeletionURL = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "rewritedeletionurl"))
    }

    public var trimmedTemplate: String? { Self.nonEmpty(template) }
    public var trimmedHost: String? { Self.nonEmpty(host) }
    public var trimmedScheme: String? { Self.nonEmpty(scheme)?.lowercased() }

    public var normalizedPathPrefix: String? {
        guard let prefix = Self.nonEmpty(pathPrefix) else { return nil }
        let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : "/" + trimmed
    }

    public var isEmpty: Bool {
        trimmedTemplate == nil && trimmedHost == nil && trimmedScheme == nil && normalizedPathPrefix == nil && stripQuery != true
    }

    public func apply(to url: URL) -> URL? {
        if let template = trimmedTemplate {
            return render(template, for: url)
        }
        return rewriteComponents(of: url)
    }

    public func applyToDeletionURL(_ deletionURL: String?) -> String? {
        guard rewritesDeletionURL == true, let deletionURL, let url = URL(string: deletionURL), url.scheme != nil else { return deletionURL }
        return apply(to: url)?.absoluteString ?? deletionURL
    }

    func render(_ template: String, for url: URL) -> URL? {
        let values = Self.values(for: url)
        guard let rendered = try? ResponseTemplate.render(template, resolve: { values[$0.lowercased()] }) else { return nil }
        return Self.httpURL(rendered.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func rewriteComponents(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let scheme = trimmedScheme {
            components.scheme = scheme
        }
        if let host = trimmedHost {
            let parts = host.split(separator: ":", maxSplits: 1).map(String.init)
            components.host = parts[0]
            components.port = parts.count > 1 ? Int(parts[1]) : nil
        }
        if let prefix = normalizedPathPrefix {
            let path = components.percentEncodedPath
            components.percentEncodedPath = prefix + (path.hasPrefix("/") ? path : "/" + path)
        }
        if stripQuery == true {
            components.percentEncodedQuery = nil
        }
        return components.url
    }

    static func values(for url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path()
        return [
            "url": url.absoluteString,
            "scheme": url.scheme ?? "",
            "host": url.host() ?? "",
            "port": url.port.map(String.init) ?? "",
            "path": path.hasPrefix("/") ? String(path.dropFirst()) : path,
            "filename": url.lastPathComponent == "/" ? "" : url.lastPathComponent,
            "query": components?.percentEncodedQuery ?? "",
            "fragment": components?.percentEncodedFragment ?? "",
        ]
    }

    static func httpURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public static func isValidHost(_ host: String) -> Bool {
        let parts = host.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.first, !name.isEmpty, !name.contains("/"), !name.contains(" ") else { return false }
        if parts.count > 1 {
            guard let port = Int(parts[1]), (1 ... 65535).contains(port) else { return false }
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = name
        return components.url != nil
    }

    public var issues: [UploaderIssue] {
        guard !isEmpty else { return [.emptyLinkRewrite] }
        if let template = trimmedTemplate {
            guard UploaderValidator.isWellFormedTemplate(template) else { return [.malformedTemplate(field: "link template")] }
            let unknown = ResponseTemplate.placeholders(in: template).contains { !Self.placeholders.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
            return unknown || render(template, for: Self.sampleURL) == nil ? [.invalidLinkRewriteTemplate] : []
        }
        var issues: [UploaderIssue] = []
        if let scheme = trimmedScheme, scheme != "http", scheme != "https" {
            issues.append(.invalidLinkRewriteScheme)
        }
        if let host = trimmedHost, !Self.isValidHost(host) {
            issues.append(.invalidLinkRewriteHost)
        }
        return issues
    }
}
