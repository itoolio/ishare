import Alamofire
import Foundation
import Testing
@testable import ishare

@MainActor
@Suite(.serialized)
struct UploadServiceTests {
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03])

    init() {
        UploadService.session = StubURLProtocol.makeSession()
    }

    func uploader(bodyType: RequestBodyType? = nil, responseURL: String = "{{files[0].url}}", deletionURL: String? = "{{files[0].delete}}") -> CustomUploader {
        CustomUploader(
            name: "stub", requestURL: "https://upload.example.com/api", headers: ["Authorization": "token"],
            formData: ["album": "shots"], fileFormName: "file", requestBodyType: bodyType,
            responseURL: responseURL, deletionURL: deletionURL
        )
    }

    @Test func uploadsMultipartFormDataAndParsesTheResponse() async throws {
        StubURLProtocol.reset { _ in
            StubResponse(body: Data(#"{"files": [{"url": "https://cdn.example.com/abc.png", "delete": "https://cdn.example.com/del/abc"}]}"#.utf8))
        }
        let file = try Fixtures.temporaryFile(named: "Shot.PNG", contents: pngData)
        let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader()))
        #expect(outcome.url.absoluteString == "https://cdn.example.com/abc.png")
        #expect(outcome.deletionURL == "https://cdn.example.com/del/abc")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://upload.example.com/api")
        #expect(request.headers["Authorization"] == "token")
        #expect(request.headers["x-file-name"] == "Shot.png")
        #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    @Test func uploadsBinaryBodiesWithTheFileMimeType() async throws {
        StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"files": [{"url": "https://cdn.example.com/b.png"}]}"#.utf8)) }
        let file = try Fixtures.temporaryFile(named: "b.png", contents: pngData)
        let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader(bodyType: .binary, deletionURL: nil)))
        #expect(outcome.url.absoluteString == "https://cdn.example.com/b.png")
        #expect(outcome.deletionURL == nil)
        #expect(StubURLProtocol.lastRequest?.headers["Content-Type"] == "image/png")
    }

    @Test func reportsHTTPErrors() async throws {
        StubURLProtocol.reset { _ in StubResponse(status: 413, body: Data("too large".utf8)) }
        let file = try Fixtures.temporaryFile(named: "c.png", contents: pngData)
        await #expect(throws: UploadFailure.http(status: 413, body: "too large")) {
            try await UploadService.upload(fileURL: file, to: .custom(uploader()))
        }
    }

    @Test func reportsMissingResponseFields() async throws {
        StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"ok": true}"#.utf8)) }
        let file = try Fixtures.temporaryFile(named: "d.png", contents: pngData)
        await #expect(throws: UploadFailure.responseParsing("files[0].url")) {
            try await UploadService.upload(fileURL: file, to: .custom(uploader()))
        }
    }

    @Test func rejectsInvalidUploadersBeforeSendingAnything() async throws {
        StubURLProtocol.reset { _ in StubResponse() }
        let file = try Fixtures.temporaryFile(named: "e.png", contents: pngData)
        let invalid = CustomUploader(name: "x", requestURL: "nope", headers: nil, formData: nil, fileFormName: nil, responseURL: "{{url}}")
        await #expect(throws: UploadFailure.invalidSpecification([.invalidRequestURL])) {
            try await UploadService.upload(fileURL: file, to: .custom(invalid))
        }
        #expect(StubURLProtocol.lastRequest == nil)
    }

    @Test func uploadsToImgur() async throws {
        StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"data": {"link": "https://i.imgur.com/q.png", "deletehash": "dh"}}"#.utf8)) }
        let file = try Fixtures.temporaryFile(named: "q.png", contents: pngData)
        let outcome = try await UploadService.upload(fileURL: file, to: .imgur(clientID: "cid"))
        #expect(outcome.url.absoluteString == "https://i.imgur.com/q.png")
        #expect(outcome.deletionURL == "https://api.imgur.com/3/image/dh")
        #expect(StubURLProtocol.lastRequest?.headers["Authorization"] == "Client-ID cid")
    }

    @Test func uploadsToS3WithSignedPut() async throws {
        StubURLProtocol.reset { _ in StubResponse(status: 200, headers: [:], body: Data()) }
        let file = try Fixtures.temporaryFile(named: "s3.png", contents: pngData)
        let configuration = S3Configuration(
            endpoint: "http://127.0.0.1:9000", region: "us-east-1", bucket: "ishare", accessKeyId: "AK", secretAccessKey: "SK",
            keyTemplate: "shots/{{filename}}", publicURL: "https://img.example.com/{{key}}"
        )
        let outcome = try await UploadService.upload(fileURL: file, to: .custom(.s3(name: "minio", configuration: configuration)))
        #expect(outcome.url.absoluteString == "https://img.example.com/shots/s3.png")
        #expect(outcome.s3Key == "shots/s3.png")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.method == "PUT")
        #expect(request.url.absoluteString == "http://127.0.0.1:9000/ishare/shots/s3.png")
        #expect(request.headers["x-amz-content-sha256"] == SigV4Signer.sha256Hex(pngData))
        #expect(request.headers["Authorization"]?.hasPrefix("AWS4-HMAC-SHA256 Credential=AK/") == true)
    }

    @Test func buildsDeletionRequestsWithUploaderHeaders() {
        let request = UploadService.deletionRequest(for: "https://x.example.com/del/1", uploader: uploader().withDeleteMethod(.delete))
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "token")
    }
}

private extension CustomUploader {
    func withDeleteMethod(_ method: DeleteRequestType) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: requestURL, headers: headers, formData: formData, fileFormName: fileFormName,
            requestBodyType: requestBodyType, responseURL: responseURL, deletionURL: deletionURL, deleteRequestType: method
        )
    }
}

struct MimeTypeTests {
    @Test(arguments: [("PNG", "image/png"), ("jpeg", "image/jpeg"), ("mov", "video/quicktime"), ("gif", "image/gif"), ("heic", "image/heic"), ("zzz", "application/octet-stream")])
    func mapsExtensions(pair: (String, String)) {
        #expect(MimeType.forExtension(pair.0) == pair.1)
    }

    @Test func lowercasesOnlyTheExtension() {
        #expect(UploadFileName.lowercasingExtension(of: URL(fileURLWithPath: "/a/My.Shot.PNG")) == "My.Shot.png")
    }
}
