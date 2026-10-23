import Alamofire
import CryptoKit
import Defaults
import Foundation
import ishareCore

extension WebhookEvent {
    static func upload(outcome: UploadOutcome, fileURL: URL, uploaderName: String, altText: String?, date: Date, savedBytes: Int? = nil) -> WebhookEvent? {
        guard let link = outcome.historyURL else { return nil }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return WebhookEvent(
            event: uploadCompleted, link: link, shortLink: outcome.shortURL?.absoluteString, deletionLink: outcome.deletionURL,
            fileName: UploadFileName.lowercasingExtension(of: fileURL), size: size, type: MimeType.forFile(fileURL).components(separatedBy: ";")[0],
            uploader: uploaderName, timestamp: timestampString(date), altText: altText, savedBytes: savedBytes
        )
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

extension UploadWebhook: @retroactive Defaults.Serializable {}
