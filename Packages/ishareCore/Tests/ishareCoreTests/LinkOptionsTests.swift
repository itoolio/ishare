import Foundation
import Testing
@testable import ishareCore

struct LinkOptionsDecodingTests {
    @Test func decodesTheLinkOptionsBlockCaseInsensitively() throws {
        let json = Data(
            """
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
        let json = Data(
            #"{"name": "a", "requestURL": "https://a.example.com", "responseURL": "{{url}}", "linkOptions": {"password": {"field": "p", "location": "\#(alias)"}}}"#.utf8)
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
