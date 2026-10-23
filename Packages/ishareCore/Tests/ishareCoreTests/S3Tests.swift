import Foundation
import Testing
@testable import ishareCore

struct SigV4SignerTests {
    let signer = SigV4Signer(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
    )
    let date = Date(timeIntervalSince1970: 1_369_353_600)

    @Test func formatsTimestamps() {
        let stamps = SigV4Signer.timestamps(for: date)
        #expect(stamps.amzDate == "20130524T000000Z")
        #expect(stamps.shortDate == "20130524")
    }

    @Test func hashesEmptyPayload() {
        #expect(SigV4Signer.emptyPayloadHash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func matchesAWSGetObjectExample() {
        let result = signer.signature(
            method: "GET",
            url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!,
            headers: ["Range": "bytes=0-9"],
            payloadHash: SigV4Signer.emptyPayloadHash,
            date: date
        )
        #expect(result.signedHeaders == "host;range;x-amz-content-sha256;x-amz-date")
        #expect(result.signature == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
        #expect(result.authorization == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    @Test func matchesAWSPutObjectExample() {
        let payload = Data("Welcome to Amazon S3.".utf8)
        let result = signer.signature(
            method: "PUT",
            url: URL(string: "https://examplebucket.s3.amazonaws.com/test%24file.text")!,
            headers: ["Date": "Fri, 24 May 2013 00:00:00 GMT", "x-amz-storage-class": "REDUCED_REDUNDANCY"],
            payloadHash: SigV4Signer.sha256Hex(payload),
            date: date
        )
        #expect(SigV4Signer.sha256Hex(payload) == "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")
        #expect(result.signedHeaders == "date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class")
        #expect(result.signature == "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
    }

    @Test func matchesAWSListObjectsExampleWithQuery() {
        let result = signer.signature(
            method: "GET",
            url: URL(string: "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J")!,
            headers: [:],
            payloadHash: SigV4Signer.emptyPayloadHash,
            date: date
        )
        #expect(result.canonicalRequest.split(separator: "\n", omittingEmptySubsequences: false)[2] == "max-keys=2&prefix=J")
        #expect(result.signature == "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")
    }

    @Test func includesNonDefaultPortInHost() {
        let result = signer.signature(method: "PUT", url: URL(string: "http://localhost:9000/b/k.png")!, headers: [:], payloadHash: "x", date: date)
        #expect(result.canonicalRequest.contains("host:localhost:9000\n"))
    }

    @Test func hashesFilesInChunks() throws {
        let payload = Data((0 ..< 3_000_000).map { UInt8($0 % 251) })
        let url = try Fixtures.temporaryFile(named: "big.bin", contents: payload)
        #expect(try SigV4Signer.sha256Hex(fileAt: url) == SigV4Signer.sha256Hex(payload))
    }
}

struct S3ConfigurationTests {
    func configuration(pathStyle: Bool? = nil, publicURL: String? = nil, endpoint: String = "https://s3.eu-central-1.amazonaws.com") -> S3Configuration {
        S3Configuration(endpoint: endpoint, region: "eu-central-1", bucket: "shots", accessKeyId: "a", secretAccessKey: "s", pathStyle: pathStyle, publicURL: publicURL)
    }

    @Test func buildsPathStyleObjectURLs() {
        let url = configuration().objectURL(for: "2026/10/20/my shot.png")
        #expect(url?.absoluteString == "https://s3.eu-central-1.amazonaws.com/shots/2026/10/20/my%20shot.png")
    }

    @Test func buildsVirtualHostedObjectURLs() {
        let url = configuration(pathStyle: false).objectURL(for: "a+b.png")
        #expect(url?.absoluteString == "https://shots.s3.eu-central-1.amazonaws.com/a%2Bb.png")
    }

    @Test func keepsEndpointPortsAndPaths() {
        let url = configuration(endpoint: "http://127.0.0.1:9000/storage").objectURL(for: "k.png")
        #expect(url?.absoluteString == "http://127.0.0.1:9000/storage/shots/k.png")
    }

    @Test func rendersPublicURLTemplates() throws {
        let url = try configuration(publicURL: "https://cdn.example.com/{{bucket}}/{{key}}").publicURL(for: "a b.png")
        #expect(url?.absoluteString == "https://cdn.example.com/shots/a%20b.png")
    }

    @Test func fallsBackToObjectURLWithoutPublicTemplate() throws {
        #expect(try configuration().publicURL(for: "k.png") == configuration().objectURL(for: "k.png"))
    }
}

struct S3KeyTemplateTests {
    let context = S3KeyContext(
        fileName: "ishare-1700000000-safari.PNG",
        date: Date(timeIntervalSince1970: 1_760_918_400),
        uuid: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!,
        randomToken: "abcd1234"
    )

    @Test func defaultsToTheFileNameWithLowercaseExtension() throws {
        #expect(try S3KeyTemplate.render(nil, context: context) == "ishare-1700000000-safari.png")
    }

    @Test func rendersAllPlaceholders() throws {
        let key = try S3KeyTemplate.render("/{{date}}/{{uuid}}-{{random}}-{{timestamp}}/{{name}}.{{ext}}", context: context)
        #expect(key == "2025/10/20/6f9619ff-8b86-d011-b42d-00cf4fc964ff-abcd1234-1760918400/ishare-1700000000-safari.png")
    }

    @Test func rejectsUnknownPlaceholders() {
        #expect(throws: ResponseTemplateError.missingValue("nope")) {
            try S3KeyTemplate.render("{{nope}}", context: context)
        }
    }
}

struct S3RequestBuilderTests {
    @Test func signsUploadRequestsWithACLAndContentType() throws {
        let configuration = S3Configuration(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "b", accessKeyId: "AK", secretAccessKey: "SK", acl: "public-read")
        let request = try S3RequestBuilder.upload(
            configuration: configuration, fileURL: URL(fileURLWithPath: "/tmp/x.png"), contentType: "image/png",
            payloadHash: "abc", context: S3KeyContext(fileName: "x.png"), date: Date(timeIntervalSince1970: 0)
        )
        #expect(request.url.absoluteString == "https://s3.us-east-1.amazonaws.com/b/x.png")
        #expect(request.headers["x-amz-acl"] == "public-read")
        #expect(request.headers["Content-Type"] == "image/png")
        #expect(request.headers["x-amz-date"] == "19700101T000000Z")
        #expect(request.headers["Authorization"]?.contains("SignedHeaders=content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date") == true)
    }
}
