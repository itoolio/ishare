import Defaults
import Foundation
import ishareCore
import Synchronization
import Testing
@testable import ishare

struct WebhookPayloadTests {
    let date = Date(timeIntervalSince1970: 1_767_225_600)

    func event() throws -> WebhookEvent {
        let file = try Fixtures.temporaryFile(named: "Shot.PNG", contents: TestUploaders.png)
        var outcome = UploadOutcome(url: URL(string: "https://cdn.example.com/a.png")!, deletionURL: "https://cdn.example.com/delete/a", uploaderID: nil, s3Key: nil)
        outcome.shortURL = URL(string: "https://is.gd/x")
        return try #require(WebhookEvent.upload(outcome: outcome, fileURL: file, uploaderName: "Zipline", altText: "A chart", date: date))
    }

    @Test func describesTheUploadInTheJSONPayload() throws {
        let body = WebhookPayload.body(for: try event(), style: .json)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["event"] as? String == "upload.completed")
        #expect(json["link"] as? String == "https://cdn.example.com/a.png")
        #expect(json["shortLink"] as? String == "https://is.gd/x")
        #expect(json["deletionLink"] as? String == "https://cdn.example.com/delete/a")
        #expect(json["fileName"] as? String == "Shot.png")
        #expect(json["size"] as? Int == TestUploaders.png.count)
        #expect(json["type"] as? String == "image/png")
        #expect(json["uploader"] as? String == "Zipline")
        #expect(json["timestamp"] as? String == "2026-01-01T00:00:00Z")
        #expect(json["altText"] as? String == "A chart")
        #expect(String(decoding: body, as: UTF8.self).contains("https://cdn.example.com/a.png"))
    }

    @Test func skipsUploadsWithoutAShareableLink() throws {
        let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
        let local = UploadOutcome(url: file, deletionURL: nil, uploaderID: nil, s3Key: nil, isShareable: false)
        #expect(WebhookEvent.upload(outcome: local, fileURL: file, uploaderName: "Folder", altText: nil, date: date) == nil)
    }

    @Test func buildsSlackAndDiscordPayloads() throws {
        let slack = try #require(try JSONSerialization.jsonObject(with: WebhookPayload.body(for: try event(), style: .slack)) as? [String: Any])
        #expect(slack["text"] as? String == "<https://is.gd/x|Shot.png> uploaded with ishare to Zipline\n_A chart_")
        let discord = try #require(try JSONSerialization.jsonObject(with: WebhookPayload.body(for: try event(), style: .discord)) as? [String: Any])
        #expect(discord["content"] as? String == "https://is.gd/x")
        let embed = try #require((discord["embeds"] as? [[String: Any]])?.first)
        #expect((embed["image"] as? [String: Any])?["url"] as? String == "https://cdn.example.com/a.png")
        #expect(embed["description"] as? String == "A chart")
        #expect((discord["allowed_mentions"] as? [String: Any])?["parse"] as? [String] == [])
    }

    @Test func signsTheBodyWithHMACSHA256() {
        #expect(WebhookPayload.signature(for: Data("what do ya want for nothing?".utf8), secret: "Jefe")
            == "sha256=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    @Test func addsTheSignatureHeaderOnlyWithASecret() throws {
        let webhook = UploadWebhook(url: "https://hooks.example.com/ishare")
        let signed = try #require(WebhookPayload.request(for: webhook, event: try event(), secret: "s3cret"))
        let body = try #require(signed.httpBody)
        #expect(signed.httpMethod == "POST")
        #expect(signed.value(forHTTPHeaderField: "X-ishare-Signature") == WebhookPayload.signature(for: body, secret: "s3cret"))
        #expect(signed.value(forHTTPHeaderField: "X-ishare-Event") == "upload.completed")
        #expect(signed.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let unsigned = try #require(WebhookPayload.request(for: webhook, event: try event(), secret: nil))
        #expect(unsigned.value(forHTTPHeaderField: "X-ishare-Signature") == nil)
        #expect(WebhookPayload.request(for: UploadWebhook(url: "not a url"), event: try event(), secret: nil) == nil)
    }

    @Test @MainActor func keepsSecretsInTheKeychain() {
        let webhook = WebhookSecrets.storing(UploadWebhook(url: "https://hooks.example.com", secret: "abc"))
        #expect(webhook.secret == UploaderSecrets.placeholder)
        #expect(WebhookSecrets.secret(for: webhook) == "abc")
        let cleared = WebhookSecrets.storing(UploadWebhook(id: webhook.id, url: "https://hooks.example.com", secret: nil))
        #expect(cleared.secret == nil)
        #expect(WebhookSecrets.secret(for: webhook) == nil)
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct WebhookDeliveryTests {
        let delays = DelayLog()

        init() {
            WebhookDispatcher.session = StubURLProtocol.makeSession()
        }

        func recordingSleep() -> @Sendable (Duration) async throws -> Void {
            let delays = self.delays
            return { duration in delays.append(duration) }
        }

        @Test func retriesServerErrorsWithBackoff() async throws {
            let original = WebhookDispatcher.sleep
            WebhookDispatcher.sleep = recordingSleep()
            defer { WebhookDispatcher.sleep = original }
            let attempts = DelayLog()
            StubURLProtocol.reset { _ in
                attempts.append(.zero)
                return StubResponse(status: attempts.values.count < 3 ? 503 : 204)
            }
            let result = await WebhookDispatcher.deliver(.sample(), to: UploadWebhook(url: "https://hooks.example.com/a"), retries: [.seconds(1), .seconds(4), .seconds(16)])
            #expect(result == .delivered(status: 204))
            #expect(attempts.values.count == 3)
            #expect(delays.values == [.seconds(1), .seconds(4)])
        }

        @Test func doesNotRetryClientErrors() async throws {
            let original = WebhookDispatcher.sleep
            WebhookDispatcher.sleep = recordingSleep()
            defer { WebhookDispatcher.sleep = original }
            StubURLProtocol.reset { _ in StubResponse(status: 404, body: Data("missing".utf8)) }
            let result = await WebhookDispatcher.deliver(.sample(), to: UploadWebhook(url: "https://hooks.example.com/a"), retries: [.seconds(1)])
            #expect(result == .failed("HTTP 404 missing", retryable: false))
            #expect(StubURLProtocol.captured.count == 1)
            #expect(delays.values.isEmpty)
        }

        @Test func sendsATestEventWithTheSignature() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 200) }
            let webhook = WebhookSecrets.storing(UploadWebhook(url: "https://hooks.example.com/test", style: .json, secret: "k"))
            #expect(await WebhookDispatcher.sendTest(to: webhook) == .delivered(status: 200))
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.headers["X-ishare-Event"] == "webhook.test")
            #expect(request.headers["X-ishare-Signature"] == WebhookPayload.signature(for: request.body, secret: "k"))
            let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            #expect(json["event"] as? String == "webhook.test")
        }

        @Test func firesAfterAnUploadWithoutBlockingIt() async throws {
            UploadService.session = StubURLProtocol.makeSession()
            let spy = UploadEnvironmentSpy()
            UploadCoordinator.environment = spy
            let previous = Defaults[.uploadWebhooks]
            Defaults[.uploadWebhooks] = [UploadWebhook(url: "https://hooks.example.com/upload")]
            WebhookDispatcher.isEnabled = true
            WebhookDispatcher.altTextWait = .zero
            defer {
                WebhookDispatcher.isEnabled = false
                Defaults[.uploadWebhooks] = previous
                UploadCoordinator.environment = LiveUploadEnvironment()
            }
            StubURLProtocol.reset { request in
                request.url.host() == "hooks.example.com"
                    ? StubResponse(status: 204)
                    : StubResponse(body: Data(#"{"url": "https://cdn.example.com/hooked.png"}"#.utf8))
            }
            let file = try Fixtures.temporaryFile(named: "hooked.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(TestUploaders.http(name: "srv", host: "srv.example.com"))], localFileURL: nil)
            #expect(spy.history.count == 1)
            var hook: CapturedRequest?
            for _ in 0 ..< 100 where hook == nil {
                try await Task.sleep(for: .milliseconds(20))
                hook = StubURLProtocol.captured.first { $0.url.host() == "hooks.example.com" }
            }
            let request = try #require(hook)
            let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            #expect(json["link"] as? String == "https://cdn.example.com/hooked.png")
            #expect(json["uploader"] as? String == "srv")
        }
    }
}

final class DelayLog: Sendable {
    private let storage = Mutex<[Duration]>([])

    var values: [Duration] {
        storage.withLock { $0 }
    }

    func append(_ duration: Duration) {
        storage.withLock { $0.append(duration) }
    }
}
