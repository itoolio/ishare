import Defaults
import Foundation
import ishareCore
import Testing
@testable import ishare

struct LinkOptionsRequestPartsTests {
    @Test func buildsRequestPartsForUploaders() throws {
        let uploader = CustomUploader(
            name: "parts", requestURL: " https://up.example.com/api ", headers: ["Authorization": "key"], formData: ["album": "shots"],
            fileFormName: nil, requestBodyType: .binary, responseURL: "{{url}}",
            linkOptions: LinkOptionsSpec(password: LinkPasswordField(field: "pw", location: .query))
        )
        let parts = try #require(HTTPUploader.requestParts(for: uploader, fileURL: URL(fileURLWithPath: "/tmp/Shot.PNG"), linkChoice: LinkChoice(password: "s")))
        #expect(parts.url.absoluteString == "https://up.example.com/api?pw=s")
        #expect(parts.headers == ["Authorization": "key", "x-file-name": "Shot.png"])
        #expect(parts.formFields.isEmpty)
    }
}

@MainActor
@Suite(.serialized)
struct LinkOptionsResolverTests {
    let spec = LinkOptionsSpec(password: LinkPasswordField(field: "pw"), expiry: LinkExpiryField(field: "exp"))

    func uploader() -> CustomUploader {
        CustomUploader(name: "r", requestURL: "https://r.example.com", headers: nil, formData: nil, fileFormName: nil, responseURL: "{{url}}", linkOptions: spec)
    }

    @Test func preferencesBuildChoicesForTheSpec() {
        let preferences = LinkOptionPreferences(usesPassword: true, expiry: .oneDay)
        #expect(preferences.choice(password: "pw", spec: spec) == LinkChoice(password: "pw", expiry: 86400))
        #expect(preferences.choice(password: "", spec: spec) == LinkChoice(password: nil, expiry: 86400))
        #expect(preferences.choice(password: "pw", spec: LinkOptionsSpec(expiry: spec.expiry)) == LinkChoice(password: nil, expiry: 86400))
        #expect(LinkOptionPreferences(usesPassword: false).choice(password: "pw", spec: spec) == .none)
    }

    @Test func usesTheStoredDefaultsWithoutPrompting() async {
        let uploader = uploader()
        defer { LinkOptionsResolver.forget(uploader.id) }
        LinkOptionsResolver.setPreferences(LinkOptionPreferences(usesPassword: true, expiry: .oneHour), for: uploader.id)
        LinkPasswordStore.setPassword("secret", for: uploader.id)
        let resolution = await LinkOptionsResolver.resolve(for: .custom(uploader)) { _, _ in
            Issue.record("The prompt must not appear")
            return nil
        }
        #expect(resolution == .use(LinkChoice(password: "secret", expiry: 3600)))
        #expect(LinkOptionsResolver.storedChoice(for: uploader) == LinkChoice(password: "secret", expiry: 3600))
    }

    @Test func asksEveryTimeWhenEnabled() async {
        let uploader = uploader()
        defer { LinkOptionsResolver.forget(uploader.id) }
        LinkOptionsResolver.setPreferences(LinkOptionPreferences(expiry: .oneWeek, asksEveryTime: true), for: uploader.id)
        var suggested: LinkChoice?
        let resolution = await LinkOptionsResolver.resolve(for: .custom(uploader)) { _, choice in
            suggested = choice
            return LinkChoice(password: "typed", expiry: 600)
        }
        #expect(suggested == LinkChoice(expiry: 604_800))
        #expect(resolution == .use(LinkChoice(password: "typed", expiry: 600)))
        let cancelled = await LinkOptionsResolver.resolve(for: .custom(uploader)) { _, _ in nil }
        #expect(cancelled == .cancel)
    }

    @Test func skipsUploadersWithoutLinkOptions() async {
        let plain = TestUploaders.http(name: "plain", host: "plain.example.com")
        #expect(await LinkOptionsResolver.resolve(for: .custom(plain)) { _, _ in nil } == .use(.none))
        #expect(await LinkOptionsResolver.resolve(for: .imgur(clientID: "x")) { _, _ in nil } == .use(.none))
    }

    @Test func forgettingRemovesPreferencesAndPassword() {
        let id = UUID()
        LinkOptionsResolver.setPreferences(LinkOptionPreferences(usesPassword: true), for: id)
        LinkPasswordStore.setPassword("pw", for: id)
        LinkOptionsResolver.forget(id)
        #expect(Defaults[.linkOptionPreferences][id.uuidString] == nil)
        #expect(LinkPasswordStore.password(for: id) == nil)
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct LinkOptionsUploadTests {
        let spy = UploadEnvironmentSpy()

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"url": "https://cdn.example.com/a.png"}"#.utf8)) }
        }

        func uploader(_ spec: LinkOptionsSpec, bodyType: RequestBodyType? = nil) -> CustomUploader {
            CustomUploader(
                name: "linked", requestURL: "https://up.example.com/upload", headers: nil, formData: nil, fileFormName: "file",
                requestBodyType: bodyType, responseURL: "{{url}}", linkOptions: spec
            )
        }

        @Test func sendsPasswordAndExpiryAsMultipartFields() async throws {
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let spec = LinkOptionsSpec(password: LinkPasswordField(field: "password"), expiry: LinkExpiryField(field: "expires", format: .minutes))
            _ = try await UploadService.upload(fileURL: file, to: .custom(uploader(spec)), linkChoice: LinkChoice(password: "pw1", expiry: 3600))
            let body = String(decoding: try #require(StubURLProtocol.lastRequest).body, as: UTF8.self)
            #expect(body.contains("name=\"password\"\r\n\r\npw1\r\n"))
            #expect(body.contains("name=\"expires\"\r\n\r\n60\r\n"))
        }

        @Test func sendsHeadersAndQueryItemsWithBinaryBodies() async throws {
            let file = try Fixtures.temporaryFile(named: "b.png", contents: TestUploaders.png)
            let spec = LinkOptionsSpec(
                password: LinkPasswordField(field: "x-password", location: .header),
                expiry: LinkExpiryField(field: "ttl", location: .query, format: .seconds)
            )
            _ = try await UploadService.upload(fileURL: file, to: .custom(uploader(spec, bodyType: .binary)), linkChoice: LinkChoice(password: "pw2", expiry: 120))
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.headers["x-password"] == "pw2")
            #expect(request.url.absoluteString == "https://up.example.com/upload?ttl=120")
            #expect(request.body == TestUploaders.png)
        }

        @Test func cancellingThePromptSkipsTheUpload() async throws {
            UploadCoordinator.environment = spy
            spy.linkChoice = .cancel
            defer { UploadCoordinator.environment = LiveUploadEnvironment() }
            let file = try Fixtures.temporaryFile(named: "c.png", contents: TestUploaders.png)
            let target = UploadTarget.custom(uploader(LinkOptionsSpec(password: LinkPasswordField(field: "pw"))))
            let results = await UploadCoordinator.upload(fileURL: file, to: [target], localFileURL: nil)
            #expect(throws: UploadFailure.cancelled) { try results[0].get() }
            #expect(StubURLProtocol.captured.isEmpty)
            #expect(spy.notifications == ["Upload cancelled".localized()])
            #expect(spy.enqueued.isEmpty)
        }

        @Test func passesTheResolvedChoiceToTheRequest() async throws {
            UploadCoordinator.environment = spy
            spy.linkChoice = .use(LinkChoice(password: "chosen"))
            defer { UploadCoordinator.environment = LiveUploadEnvironment() }
            let file = try Fixtures.temporaryFile(named: "d.png", contents: TestUploaders.png)
            let target = UploadTarget.custom(uploader(LinkOptionsSpec(password: LinkPasswordField(field: "x-pw", location: .header))))
            _ = await UploadCoordinator.upload(fileURL: file, to: [target], localFileURL: nil)
            #expect(StubURLProtocol.lastRequest?.headers["x-pw"] == "chosen")
            #expect(spy.history.map(\.fileUrl) == ["https://cdn.example.com/a.png"])
        }
    }
}
