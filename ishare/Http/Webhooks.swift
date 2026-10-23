import Alamofire
import CryptoKit
import Defaults
import Foundation

enum WebhookPayloadStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case json
    case slack
    case discord

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .json: "ishare JSON"
        case .slack: "Slack"
        case .discord: "Discord"
        }
    }
}

struct UploadWebhook: Codable, Hashable, Identifiable, Sendable, Defaults.Serializable {
    var id: UUID
    var name: String
    var url: String
    var enabled: Bool
    var style: WebhookPayloadStyle
    var secret: String?

    init(id: UUID = UUID(), name: String = "", url: String = "", enabled: Bool = true, style: WebhookPayloadStyle = .json, secret: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.style = style
        self.secret = secret
    }

    var endpoint: URL? {
        guard UploaderValidator.isHTTPURL(url) else { return nil }
        return URL(string: url.trimmingCharacters(in: .whitespaces))
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (endpoint?.host() ?? url) : trimmed
    }
}

struct WebhookEvent: Codable, Equatable, Sendable {
    var event: String
    var link: String
    var shortLink: String?
    var deletionLink: String?
    var fileName: String
    var size: Int?
    var type: String
    var uploader: String
    var timestamp: String
    var altText: String?
    var savedBytes: Int?

    static let uploadCompleted = "upload.completed"
    static let test = "webhook.test"

    static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func upload(outcome: UploadOutcome, fileURL: URL, uploaderName: String, altText: String?, date: Date, savedBytes: Int? = nil) -> WebhookEvent? {
        guard let link = outcome.historyURL else { return nil }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return WebhookEvent(
            event: uploadCompleted, link: link, shortLink: outcome.shortURL?.absoluteString, deletionLink: outcome.deletionURL,
            fileName: UploadFileName.lowercasingExtension(of: fileURL), size: size, type: MimeType.forFile(fileURL).components(separatedBy: ";")[0],
            uploader: uploaderName, timestamp: timestampString(date), altText: altText, savedBytes: savedBytes
        )
    }

    static func sample(date: Date = .init()) -> WebhookEvent {
        WebhookEvent(
            event: test, link: "https://example.com/ishare-test.png", shortLink: nil, deletionLink: "https://example.com/delete/ishare-test",
            fileName: "ishare-test.png", size: 1024, type: "image/png", uploader: "ishare", timestamp: timestampString(date),
            altText: "A test image sent by ishare", savedBytes: nil
        )
    }

    var isImage: Bool { type.hasPrefix("image/") }
}

enum WebhookPayload {
    static func body(for event: WebhookEvent, style: WebhookPayloadStyle) -> Data {
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

    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    static func signature(for body: Data, secret: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: Data(secret.utf8)))
        return "sha256=" + code.map { String(format: "%02x", $0) }.joined()
    }

    static func request(for webhook: UploadWebhook, event: WebhookEvent, secret: String?) -> URLRequest? {
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

enum WebhookSecrets {
    static func account(_ id: UUID) -> String {
        "webhook.\(id.uuidString)"
    }

    static func secret(for webhook: UploadWebhook) -> String? {
        guard let secret = webhook.secret, !secret.isEmpty else { return nil }
        return UploaderSecrets.isPlaceholder(secret) ? UploaderSecrets.backend.read(account: account(webhook.id)) : secret
    }

    static func storing(_ webhook: UploadWebhook) -> UploadWebhook {
        var copy = webhook
        guard let secret = webhook.secret, !secret.isEmpty else {
            UploaderSecrets.backend.delete(account: account(webhook.id))
            copy.secret = nil
            return copy
        }
        guard !UploaderSecrets.isPlaceholder(secret) else { return copy }
        if (try? UploaderSecrets.backend.write(secret, account: account(webhook.id))) != nil {
            copy.secret = UploaderSecrets.placeholder
        }
        return copy
    }

    static func remove(_ webhook: UploadWebhook) {
        UploaderSecrets.backend.delete(account: account(webhook.id))
    }
}

enum WebhookDelivery: Equatable, Sendable {
    case delivered(status: Int)
    case failed(String, retryable: Bool)
}

@MainActor
enum WebhookDispatcher {
    static var session: Session = AF
    static var retryDelays: [Duration] = [.seconds(2), .seconds(10), .seconds(30)]
    static var altTextWait: Duration = .seconds(20)
    static var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    static var isEnabled = !RuntimeEnvironment.isRunningTests

    static func uploadCompleted(_ outcome: UploadOutcome, fileURL: URL, uploaderName: String, savedBytes: Int?, waitsForAltText: Bool) {
        let webhooks = Defaults[.uploadWebhooks].filter(\.enabled)
        guard isEnabled, !webhooks.isEmpty, outcome.historyURL != nil else { return }
        let date = Date()
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        Task { @MainActor in
            let altText = waitsForAltText ? await waitForAltText(link: outcome.historyURL) : nil
            guard var event = WebhookEvent.upload(outcome: outcome, fileURL: fileURL, uploaderName: uploaderName, altText: altText, date: date, savedBytes: savedBytes) else { return }
            event.size = event.size ?? size
            for webhook in webhooks {
                Task { @MainActor in
                    _ = await deliver(event, to: webhook)
                }
            }
        }
    }

    static func waitForAltText(link: String?) async -> String? {
        guard let link else { return nil }
        let deadline = ContinuousClock.now + altTextWait
        while ContinuousClock.now < deadline {
            if let altText = Defaults[.uploadHistory].first(where: { $0.fileUrl == link })?.altText, !altText.isEmpty {
                return altText
            }
            try? await sleep(.seconds(1))
        }
        return nil
    }

    static func sendTest(to webhook: UploadWebhook) async -> WebhookDelivery {
        await deliver(.sample(), to: webhook, retries: [])
    }

    static func deliver(_ event: WebhookEvent, to webhook: UploadWebhook, retries: [Duration]? = nil) async -> WebhookDelivery {
        guard let request = WebhookPayload.request(for: webhook, event: event, secret: WebhookSecrets.secret(for: webhook)) else {
            return .failed("The webhook URL must be a valid http or https URL".localized(), retryable: false)
        }
        var delays = retries ?? retryDelays
        while true {
            let result = await attempt(request)
            switch result {
            case let .delivered(status):
                Log.upload.info("Webhook \(webhook.displayName, privacy: .public) answered \(status)")
                return result
            case let .failed(detail, retryable):
                guard !delays.isEmpty, retryable else {
                    Log.upload.error("Webhook \(webhook.displayName, privacy: .public) failed: \(detail, privacy: .public)")
                    return result
                }
                try? await sleep(delays.removeFirst())
            }
        }
    }

    static func attempt(_ request: URLRequest) async -> WebhookDelivery {
        let response = await session.request(request).serializingData(emptyResponseCodes: Set(100 ..< 600)).response
        guard let status = response.response?.statusCode else {
            return .failed(response.error?.localizedDescription ?? "no response", retryable: true)
        }
        if (200 ..< 300).contains(status) { return .delivered(status: status) }
        let body = String(data: response.data ?? Data(), encoding: .utf8).map { String($0.prefix(200)) } ?? ""
        let detail = "HTTP \(status) \(body)"
        return .failed(detail, retryable: status >= 500 || status == 429 || status == 408)
    }
}
