import Defaults
import Foundation
import Testing
@testable import ishare

struct LinkOptionsDecodingTests {
    @Test func decodesTheLinkOptionsBlockCaseInsensitively() throws {
        let json = Data("""
        {"name": "zip", "requestURL": "https://zip.example.com/api/upload", "responseURL": "{{files[0].url}}",
         "LinkOptions": {"Password": {"Field": "x-password", "Location": "Header"},
                         "expiry": {"field": "expires", "location": "query", "format": "ISO8601", "template": "date={{value}}"}}}
        """.utf8)
        let uploader = try CustomUploader.fromJSON(json)
        let options = try #require(uploader.linkOptions)
        #expect(options.password == LinkPasswordField(field: "x-password", location: .header))
        #expect(options.expiry == LinkExpiryField(field: "expires", location: .query, format: .iso8601, template: "date={{value}}"))
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }

    @Test func defaultsToFormFieldsAndSeconds() throws {
        let json = Data(#"{"name": "a", "requestURL": "https://a.example.com", "responseURL": "{{url}}", "linkOptions": {"expiry": {"field": "ttl"}}}"#.utf8)
        let expiry = try #require(CustomUploader.fromJSON(json).linkOptions?.expiry)
        #expect(expiry.location == .form)
        #expect(expiry.format == .seconds)
    }

    @Test(arguments: [("formdata", LinkOptionLocation.form), ("headers", .header), ("querystring", .query)])
    func acceptsLocationAliases(alias: String, location: LinkOptionLocation) throws {
        let json = Data(#"{"name": "a", "requestURL": "https://a.example.com", "responseURL": "{{url}}", "linkOptions": {"password": {"field": "p", "location": "\#(alias)"}}}"#.utf8)
        #expect(try CustomUploader.fromJSON(json).linkOptions?.password?.location == location)
    }

    @Test func rejectsUnknownFormats() {
        let json = Data(#"{"name": "a", "requestURL": "https://a.example.com", "responseURL": "{{url}}", "linkOptions": {"expiry": {"field": "e", "format": "fortnights"}}}"#.utf8)
        #expect(throws: DecodingError.self) { try CustomUploader.fromJSON(json) }
    }

    @Test func roundTripsThroughJSON() throws {
        let uploader = CustomUploader(
            name: "round", requestURL: "https://r.example.com", headers: nil, formData: nil, fileFormName: nil, responseURL: "{{url}}",
            linkOptions: LinkOptionsSpec(password: LinkPasswordField(field: "pw", location: .query), expiry: LinkExpiryField(field: "exp", format: .timestamp))
        )
        let decoded = try CustomUploader.fromJSON(uploader.toJSON())
        #expect(decoded.linkOptions == uploader.linkOptions)
        #expect(decoded.renamed("other").linkOptions == uploader.linkOptions)
    }

    @Test func decodesTheZiplineExample() throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/zipline-protected.iscu"))
        let options = try #require(uploader.linkOptions)
        #expect(options.password?.location == .header)
        #expect(options.expiry?.location == .header)
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }
}

struct LinkOptionsEncoderTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let base = HTTPRequestParts(url: URL(string: "https://up.example.com/api?token=abc")!, headers: ["Authorization": "key"], formFields: ["album": "shots"])

    func applying(_ choice: LinkChoice, _ spec: LinkOptionsSpec) -> HTTPRequestParts {
        var parts = base
        LinkOptionsEncoder.apply(choice, spec: spec, to: &parts, now: now)
        return parts
    }

    @Test func placesThePasswordInAFormField() {
        let parts = applying(LinkChoice(password: "hunter2"), LinkOptionsSpec(password: LinkPasswordField(field: "password", location: .form)))
        #expect(parts.formFields == ["album": "shots", "password": "hunter2"])
        #expect(parts.headers == base.headers)
        #expect(parts.url == base.url)
    }

    @Test func placesThePasswordInAHeader() {
        let parts = applying(LinkChoice(password: "hunter2"), LinkOptionsSpec(password: LinkPasswordField(field: "x-zipline-password", location: .header)))
        #expect(parts.headers["x-zipline-password"] == "hunter2")
        #expect(parts.formFields == base.formFields)
    }

    @Test func placesThePasswordInTheQueryAndKeepsExistingItems() {
        let parts = applying(LinkChoice(password: "a+b c&d"), LinkOptionsSpec(password: LinkPasswordField(field: "pw", location: .query)))
        #expect(parts.url.absoluteString == "https://up.example.com/api?token=abc&pw=a%2Bb%20c%26d")
        let items = URLComponents(url: parts.url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "pw" }?.value == "a+b c&d")
    }

    @Test(arguments: [
        (LinkExpiryFormat.seconds, "3600"),
        (.minutes, "60"),
        (.iso8601, "2023-11-14T23:13:20Z"),
        (.timestamp, "1700003600"),
    ])
    func formatsTheExpiry(format: LinkExpiryFormat, expected: String) {
        let parts = applying(LinkChoice(expiry: 3600), LinkOptionsSpec(expiry: LinkExpiryField(field: "expires", location: .header, format: format)))
        #expect(parts.headers["expires"] == expected)
    }

    @Test func roundsMinutesUp() {
        #expect(LinkExpiryFormat.minutes == .minutes)
        #expect(LinkOptionsEncoder.expiryValue(seconds: 90, format: .minutes, now: now) == "2")
    }

    @Test(arguments: LinkOptionLocation.allCases)
    func placesTheExpiryAtEveryLocation(location: LinkOptionLocation) {
        let parts = applying(LinkChoice(expiry: 600), LinkOptionsSpec(expiry: LinkExpiryField(field: "ttl", location: location, format: .seconds)))
        switch location {
        case .form: #expect(parts.formFields["ttl"] == "600")
        case .header: #expect(parts.headers["ttl"] == "600")
        case .query: #expect(parts.url.absoluteString == "https://up.example.com/api?token=abc&ttl=600")
        }
    }

    @Test func rendersValueTemplates() {
        let spec = LinkOptionsSpec(
            password: LinkPasswordField(field: "Authorization-Password", location: .header, template: "Basic {{value}}"),
            expiry: LinkExpiryField(field: "x-zipline-deletes-at", location: .header, format: .iso8601, template: "date={{value}}")
        )
        let parts = applying(LinkChoice(password: "pw", expiry: 60), spec)
        #expect(parts.headers["Authorization-Password"] == "Basic pw")
        #expect(parts.headers["x-zipline-deletes-at"] == "date=2023-11-14T22:14:20Z")
    }

    @Test func leavesTheRequestAloneWithoutAChoice() {
        let spec = LinkOptionsSpec(password: LinkPasswordField(field: "pw"), expiry: LinkExpiryField(field: "exp"))
        #expect(applying(.none, spec) == base)
        #expect(applying(LinkChoice(password: ""), spec) == base)
    }

    @Test func ignoresChoicesWithoutASpec() {
        var parts = base
        LinkOptionsEncoder.apply(LinkChoice(password: "pw", expiry: 60), spec: nil, to: &parts, now: now)
        #expect(parts == base)
    }

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

struct LinkOptionsValidationTests {
    func uploader(_ spec: LinkOptionsSpec, bodyType: RequestBodyType? = nil) -> CustomUploader {
        CustomUploader(
            name: "v", requestURL: "https://v.example.com", headers: nil, formData: nil, fileFormName: nil, requestBodyType: bodyType,
            responseURL: "{{url}}", linkOptions: spec
        )
    }

    @Test func requiresAtLeastOneOption() {
        #expect(UploaderValidator.issues(for: uploader(LinkOptionsSpec())) == [.emptyLinkOptions])
    }

    @Test func requiresFieldNames() {
        let issues = UploaderValidator.issues(for: uploader(LinkOptionsSpec(password: LinkPasswordField(field: " "), expiry: LinkExpiryField(field: ""))))
        #expect(issues == [.missingLinkOptionField("password"), .missingLinkOptionField("expiry")])
    }

    @Test func rejectsFormFieldsOnBinaryBodies() {
        let issues = UploaderValidator.issues(for: uploader(LinkOptionsSpec(password: LinkPasswordField(field: "pw", location: .form)), bodyType: .binary))
        #expect(issues == [.linkOptionFormWithBinaryBody("password")])
        #expect(UploaderValidator.issues(for: uploader(LinkOptionsSpec(password: LinkPasswordField(field: "pw", location: .header)), bodyType: .binary)).isEmpty)
    }

    @Test func checksTemplates() {
        let missingValue = uploader(LinkOptionsSpec(expiry: LinkExpiryField(field: "e", template: "date={{expires}}")))
        #expect(UploaderValidator.issues(for: missingValue) == [.linkOptionTemplateWithoutValue("expiry")])
        let malformed = uploader(LinkOptionsSpec(password: LinkPasswordField(field: "p", template: "{{value")))
        #expect(UploaderValidator.issues(for: malformed) == [.malformedTemplate(field: "password link option")])
    }

    @Test func formatsMessages() {
        #expect(UploaderIssue.missingLinkOptionField("password").message == "The password link option needs a field name")
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
            UploadCoordinator.environment = spy.environment
            UploadCoordinator.environment.resolveLinkChoice = { _ in .cancel }
            defer { UploadCoordinator.environment = .live }
            let file = try Fixtures.temporaryFile(named: "c.png", contents: TestUploaders.png)
            let target = UploadTarget.custom(uploader(LinkOptionsSpec(password: LinkPasswordField(field: "pw"))))
            let results = await UploadCoordinator.upload(fileURL: file, to: [target], localFileURL: nil)
            #expect(throws: UploadFailure.cancelled) { try results[0].get() }
            #expect(StubURLProtocol.captured.isEmpty)
            #expect(spy.notifications == ["Upload cancelled".localized()])
            #expect(spy.enqueued.isEmpty)
        }

        @Test func passesTheResolvedChoiceToTheRequest() async throws {
            UploadCoordinator.environment = spy.environment
            UploadCoordinator.environment.resolveLinkChoice = { _ in .use(LinkChoice(password: "chosen")) }
            defer { UploadCoordinator.environment = .live }
            let file = try Fixtures.temporaryFile(named: "d.png", contents: TestUploaders.png)
            let target = UploadTarget.custom(uploader(LinkOptionsSpec(password: LinkPasswordField(field: "x-pw", location: .header))))
            _ = await UploadCoordinator.upload(fileURL: file, to: [target], localFileURL: nil)
            #expect(StubURLProtocol.lastRequest?.headers["x-pw"] == "chosen")
            #expect(spy.history.map(\.fileUrl) == ["https://cdn.example.com/a.png"])
        }
    }
}
