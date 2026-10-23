import CryptoKit
import Foundation

public enum WebhookPayloadStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case json
    case slack
    case discord

    public var id: Self { self }

    public var titleKey: String {
        switch self {
        case .json: "ishare JSON"
        case .slack: "Slack"
        case .discord: "Discord"
        }
    }
}

public struct UploadWebhook: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public var enabled: Bool
    public var style: WebhookPayloadStyle
    public var secret: String?

    public init(id: UUID = UUID(), name: String = "", url: String = "", enabled: Bool = true, style: WebhookPayloadStyle = .json, secret: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.style = style
        self.secret = secret
    }

    public var endpoint: URL? {
        guard UploaderValidator.isHTTPURL(url) else { return nil }
        return URL(string: url.trimmingCharacters(in: .whitespaces))
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (endpoint?.host() ?? url) : trimmed
    }
}

public struct WebhookEvent: Codable, Equatable, Sendable {
    public var event: String
    public var link: String
    public var shortLink: String?
    public var deletionLink: String?
    public var fileName: String
    public var size: Int?
    public var type: String
    public var uploader: String
    public var timestamp: String
    public var altText: String?
    public var savedBytes: Int?

    public static let uploadCompleted = "upload.completed"
    public static let test = "webhook.test"

    public static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func sample(date: Date = .init()) -> WebhookEvent {
        WebhookEvent(
            event: test, link: "https://example.com/ishare-test.png", shortLink: nil, deletionLink: "https://example.com/delete/ishare-test",
            fileName: "ishare-test.png", size: 1024, type: "image/png", uploader: "ishare", timestamp: timestampString(date),
            altText: "A test image sent by ishare", savedBytes: nil
        )
    }

    public var isImage: Bool { type.hasPrefix("image/") }

    public init(event: String, link: String, shortLink: String? = nil, deletionLink: String? = nil, fileName: String, size: Int? = nil, type: String, uploader: String, timestamp: String, altText: String? = nil, savedBytes: Int? = nil) {
        self.event = event
        self.link = link
        self.shortLink = shortLink
        self.deletionLink = deletionLink
        self.fileName = fileName
        self.size = size
        self.type = type
        self.uploader = uploader
        self.timestamp = timestamp
        self.altText = altText
        self.savedBytes = savedBytes
    }
}

public enum WebhookPayload {
    public static func body(for event: WebhookEvent, style: WebhookPayloadStyle) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        switch style {
        case .json:
            return (try? encoder.encode(event)) ?? Data()
        case .slack:
            var text = "<\(event.shortLink ?? event.link)|\(escapedSlack(event.fileName))> uploaded with ishare to \(escapedSlack(event.uploader))"
            if let altText = event.altText, !altText.isEmpty {
                text += "\n_\(escapedSlack(altText))_"
            }
            return json(["text": text, "unfurl_links": true, "unfurl_media": true])
        case .discord:
            var embed: [String: Any] = ["title": event.fileName, "url": event.shortLink ?? event.link, "timestamp": event.timestamp]
            if let altText = event.altText, !altText.isEmpty {
                embed["description"] = altText
            }
            if event.isImage {
                embed["image"] = ["url": event.link]
            }
            return json([
                "content": "\(event.shortLink ?? event.link)",
                "username": "ishare",
                "embeds": [embed],
                "allowed_mentions": ["parse": [String]()],
            ])
        }
    }

    static func escapedSlack(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    public static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    public static func signature(for body: Data, secret: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: Data(secret.utf8)))
        return "sha256=" + code.map { String(format: "%02x", $0) }.joined()
    }

    public static func request(for webhook: UploadWebhook, event: WebhookEvent, secret: String?) -> URLRequest? {
        guard let endpoint = webhook.endpoint else { return nil }
        let body = body(for: event, style: webhook.style)
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ishare-webhook/1", forHTTPHeaderField: "User-Agent")
        request.setValue(event.event, forHTTPHeaderField: "X-ishare-Event")
        if let secret, !secret.isEmpty {
            request.setValue(signature(for: body, secret: secret), forHTTPHeaderField: "X-ishare-Signature")
        }
        return request
    }
}
