import Defaults
import Foundation

enum LinkOptionLocation: String, Codable, CaseIterable, Sendable {
    case form
    case header
    case query

    init(from decoder: any Decoder) throws {
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

enum LinkExpiryFormat: String, Codable, CaseIterable, Sendable {
    case seconds
    case minutes
    case iso8601
    case timestamp

    init(from decoder: any Decoder) throws {
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

struct LinkPasswordField: Codable, Hashable, Sendable {
    var field: String
    var location: LinkOptionLocation
    var template: String?

    init(field: String, location: LinkOptionLocation = .form, template: String? = nil) {
        self.field = field
        self.location = location
        self.template = template
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        field = try container.decodeDynamic(String.self, forKey: .key(named: "field"))
        location = try container.decodeDynamicIfPresent(LinkOptionLocation.self, forKey: .key(named: "location")) ?? .form
        template = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "template"))
    }
}

struct LinkExpiryField: Codable, Hashable, Sendable {
    var field: String
    var location: LinkOptionLocation
    var format: LinkExpiryFormat
    var template: String?

    init(field: String, location: LinkOptionLocation = .form, format: LinkExpiryFormat = .seconds, template: String? = nil) {
        self.field = field
        self.location = location
        self.format = format
        self.template = template
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        field = try container.decodeDynamic(String.self, forKey: .key(named: "field"))
        location = try container.decodeDynamicIfPresent(LinkOptionLocation.self, forKey: .key(named: "location")) ?? .form
        format = try container.decodeDynamicIfPresent(LinkExpiryFormat.self, forKey: .key(named: "format")) ?? .seconds
        template = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "template"))
    }
}

struct LinkOptionsSpec: Codable, Hashable, Sendable {
    var password: LinkPasswordField?
    var expiry: LinkExpiryField?

    init(password: LinkPasswordField? = nil, expiry: LinkExpiryField? = nil) {
        self.password = password
        self.expiry = expiry
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        password = try container.decodeDynamicIfPresent(LinkPasswordField.self, forKey: .key(named: "password"))
        expiry = try container.decodeDynamicIfPresent(LinkExpiryField.self, forKey: .key(named: "expiry"))
    }

    var isEmpty: Bool {
        password == nil && expiry == nil
    }
}

struct LinkChoice: Hashable, Sendable {
    var password: String?
    var expiry: Int?

    static let none = LinkChoice()

    var isEmpty: Bool {
        (password ?? "").isEmpty && expiry == nil
    }
}

enum LinkChoiceResolution: Equatable, Sendable {
    case use(LinkChoice)
    case cancel
}

enum LinkExpiryChoice: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = 0
    case tenMinutes = 600
    case oneHour = 3600
    case oneDay = 86400
    case oneWeek = 604_800
    case thirtyDays = 2_592_000

    var id: Self { self }

    var seconds: Int? {
        self == .never ? nil : rawValue
    }

    var titleKey: String {
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

struct LinkOptionPreferences: Codable, Hashable, Sendable, Defaults.Serializable {
    var usesPassword = false
    var expiry: LinkExpiryChoice = .never
    var asksEveryTime = false

    static let standard = LinkOptionPreferences()

    func choice(password: String?, spec: LinkOptionsSpec) -> LinkChoice {
        LinkChoice(
            password: spec.password != nil && usesPassword ? password.flatMap { $0.isEmpty ? nil : $0 } : nil,
            expiry: spec.expiry == nil ? nil : expiry.seconds
        )
    }
}

struct HTTPRequestParts: Equatable, Sendable {
    var url: URL
    var headers: [String: String]
    var formFields: [String: String]
}

enum LinkOptionsEncoder {
    static let valuePlaceholder = "value"

    static func apply(_ choice: LinkChoice, spec: LinkOptionsSpec?, to parts: inout HTTPRequestParts, now: Date = .init()) {
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

    static func rendered(_ value: String, template: String?) -> String {
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

enum LinkPasswordStore {
    static let service = "dev.adrian.ishare.link-password"
    private static let backendSlot = SecretBackendSlot(
        RuntimeEnvironment.isRunningTests
            ? InMemorySecretBackend()
            : KeychainSecretBackend(service: service, label: "ishare default link password")
    )

    static var backend: any SecretBackend {
        get { backendSlot.current }
        set { backendSlot.current = newValue }
    }

    static func password(for id: UUID) -> String? {
        backend.read(account: id.uuidString)
    }

    static func setPassword(_ password: String?, for id: UUID) {
        guard let password, !password.isEmpty else {
            backend.delete(account: id.uuidString)
            return
        }
        do {
            try backend.write(password, account: id.uuidString)
        } catch {
            Log.upload.error("Storing the default link password failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
enum LinkOptionsResolver {
    static func preferences(for id: UUID) -> LinkOptionPreferences {
        Defaults[.linkOptionPreferences][id.uuidString] ?? .standard
    }

    static func setPreferences(_ preferences: LinkOptionPreferences?, for id: UUID) {
        Defaults[.linkOptionPreferences][id.uuidString] = preferences == .standard ? nil : preferences
    }

    static func storedChoice(for uploader: CustomUploader) -> LinkChoice {
        guard let spec = uploader.linkOptions, !spec.isEmpty else { return .none }
        return preferences(for: uploader.id).choice(password: LinkPasswordStore.password(for: uploader.id), spec: spec)
    }

    static func resolve(for target: UploadTarget, prompt: (CustomUploader, LinkChoice) async -> LinkChoice? = LinkOptionsPrompt.ask) async -> LinkChoiceResolution {
        guard case let .custom(uploader) = target, let spec = uploader.linkOptions, !spec.isEmpty else { return .use(.none) }
        let stored = storedChoice(for: uploader)
        guard preferences(for: uploader.id).asksEveryTime else { return .use(stored) }
        guard let chosen = await prompt(uploader, stored) else { return .cancel }
        return .use(chosen)
    }

    static func forget(_ id: UUID) {
        setPreferences(nil, for: id)
        LinkPasswordStore.setPassword(nil, for: id)
    }
}
