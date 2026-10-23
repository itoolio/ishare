import Foundation

public enum LinkOptionLocation: String, Codable, CaseIterable, Sendable {
    case form
    case header
    case query

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "form", "formdata", "multipart", "body": self = .form
        case "header", "headers": self = .header
        case "query", "querystring", "url": self = .query
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid link option location: \(rawValue)")
        }
    }
}

public enum LinkExpiryFormat: String, Codable, CaseIterable, Sendable {
    case seconds
    case minutes
    case iso8601
    case timestamp

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "seconds", "s": self = .seconds
        case "minutes", "m": self = .minutes
        case "iso8601", "iso", "date": self = .iso8601
        case "timestamp", "unix", "epoch": self = .timestamp
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid link expiry format: \(rawValue)")
        }
    }
}

public struct LinkPasswordField: Codable, Hashable, Sendable {
    public var field: String
    public var location: LinkOptionLocation
    public var template: String?

    public init(field: String, location: LinkOptionLocation = .form, template: String? = nil) {
        self.field = field
        self.location = location
        self.template = template
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        field = try container.decodeDynamic(String.self, forKey: .key(named: "field"))
        location = try container.decodeDynamicIfPresent(LinkOptionLocation.self, forKey: .key(named: "location")) ?? .form
        template = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "template"))
    }
}

public struct LinkExpiryField: Codable, Hashable, Sendable {
    public var field: String
    public var location: LinkOptionLocation
    public var format: LinkExpiryFormat
    public var template: String?

    public init(field: String, location: LinkOptionLocation = .form, format: LinkExpiryFormat = .seconds, template: String? = nil) {
        self.field = field
        self.location = location
        self.format = format
        self.template = template
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        field = try container.decodeDynamic(String.self, forKey: .key(named: "field"))
        location = try container.decodeDynamicIfPresent(LinkOptionLocation.self, forKey: .key(named: "location")) ?? .form
        format = try container.decodeDynamicIfPresent(LinkExpiryFormat.self, forKey: .key(named: "format")) ?? .seconds
        template = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "template"))
    }
}

public struct LinkOptionsSpec: Codable, Hashable, Sendable {
    public var password: LinkPasswordField?
    public var expiry: LinkExpiryField?

    public init(password: LinkPasswordField? = nil, expiry: LinkExpiryField? = nil) {
        self.password = password
        self.expiry = expiry
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        password = try container.decodeDynamicIfPresent(LinkPasswordField.self, forKey: .key(named: "password"))
        expiry = try container.decodeDynamicIfPresent(LinkExpiryField.self, forKey: .key(named: "expiry"))
    }

    public var isEmpty: Bool {
        password == nil && expiry == nil
    }
}

public struct LinkChoice: Hashable, Sendable {
    public var password: String?
    public var expiry: Int?

    public static let none = LinkChoice()

    public var isEmpty: Bool {
        (password ?? "").isEmpty && expiry == nil
    }

    public init(password: String? = nil, expiry: Int? = nil) {
        self.password = password
        self.expiry = expiry
    }
}

public enum LinkChoiceResolution: Equatable, Sendable {
    case use(LinkChoice)
    case cancel
}

public enum LinkExpiryChoice: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = 0
    case tenMinutes = 600
    case oneHour = 3600
    case oneDay = 86400
    case oneWeek = 604_800
    case thirtyDays = 2_592_000

    public var id: Self { self }

    public var seconds: Int? {
        self == .never ? nil : rawValue
    }

    public var titleKey: String {
        switch self {
        case .never: "Never"
        case .tenMinutes: "After 10 minutes"
        case .oneHour: "After 1 hour"
        case .oneDay: "After 1 day"
        case .oneWeek: "After 7 days"
        case .thirtyDays: "After 30 days"
        }
    }
}

public struct LinkOptionPreferences: Codable, Hashable, Sendable {
    public var usesPassword = false
    public var expiry: LinkExpiryChoice = .never
    public var asksEveryTime = false

    public init(usesPassword: Bool = false, expiry: LinkExpiryChoice = .never, asksEveryTime: Bool = false) {
        self.usesPassword = usesPassword
        self.expiry = expiry
        self.asksEveryTime = asksEveryTime
    }

    public static let standard = LinkOptionPreferences()

    public func choice(password: String?, spec: LinkOptionsSpec) -> LinkChoice {
        LinkChoice(
            password: spec.password != nil && usesPassword ? password.flatMap { $0.isEmpty ? nil : $0 } : nil,
            expiry: spec.expiry == nil ? nil : expiry.seconds
        )
    }
}

public struct HTTPRequestParts: Equatable, Sendable {
    public var url: URL
    public var headers: [String: String]
    public var formFields: [String: String]

    public init(url: URL, headers: [String: String], formFields: [String: String]) {
        self.url = url
        self.headers = headers
        self.formFields = formFields
    }
}

public enum LinkOptionsEncoder {
    static let valuePlaceholder = "value"

    public static func apply(_ choice: LinkChoice, spec: LinkOptionsSpec?, to parts: inout HTTPRequestParts, now: Date = .init()) {
        guard let spec else { return }
        if let field = spec.password, let password = choice.password, !password.isEmpty {
            place(rendered(password, template: field.template), named: field.field, at: field.location, in: &parts)
        }
        if let field = spec.expiry, let seconds = choice.expiry {
            let value = expiryValue(seconds: seconds, format: field.format, now: now)
            place(rendered(value, template: field.template), named: field.field, at: field.location, in: &parts)
        }
    }

    static func expiryValue(seconds: Int, format: LinkExpiryFormat, now: Date) -> String {
        switch format {
        case .seconds:
            return String(seconds)
        case .minutes:
            return String(Int((Double(seconds) / 60).rounded(.up)))
        case .iso8601:
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: now.addingTimeInterval(TimeInterval(seconds)))
        case .timestamp:
            return String(Int(now.addingTimeInterval(TimeInterval(seconds)).timeIntervalSince1970))
        }
    }

    public static func rendered(_ value: String, template: String?) -> String {
        guard let template, !template.trimmingCharacters(in: .whitespaces).isEmpty else { return value }
        return (try? ResponseTemplate.render(template) { name in
            name.lowercased() == valuePlaceholder ? value : nil
        }) ?? value
    }

    private static func place(_ value: String, named name: String, at location: LinkOptionLocation, in parts: inout HTTPRequestParts) {
        let field = name.trimmingCharacters(in: .whitespaces)
        switch location {
        case .form:
            parts.formFields[field] = value
        case .header:
            parts.headers[field] = value
        case .query:
            guard var components = URLComponents(url: parts.url, resolvingAgainstBaseURL: false) else { return }
            var items = components.queryItems ?? []
            items.removeAll { $0.name == field }
            items.append(URLQueryItem(name: field, value: value))
            components.queryItems = items
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            if let url = components.url {
                parts.url = url
            }
        }
    }
}
