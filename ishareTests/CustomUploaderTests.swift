import Foundation
import Testing
@testable import ishare

struct CustomUploaderTests {
    static let exampleFiles = ["chibisafe", "copyparty", "discord", "lumen", "zipline", "zipline-protected", "s3", "folder", "photos"]

    @Test(arguments: exampleFiles)
    func decodesBundledExamples(name: String) throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/\(name).iscu"))
        #expect(uploader.name == name)
    }

    @Test func decodesKeysCaseInsensitively() throws {
        let json = Data("""
        {"NAME": "mixed", "RequestUrl": "https://up.example.com", "RESPONSEURL": "{{url}}",
         "FileFormName": "upload", "RequestBodyType": "binary", "DeleteRequestType": "delete"}
        """.utf8)
        let uploader = try CustomUploader.fromJSON(json)
        #expect(uploader.requestURL == "https://up.example.com")
        #expect(uploader.fileFormName == "upload")
        #expect(uploader.requestBodyType == .binary)
        #expect(uploader.deleteRequestType == .delete)
        #expect(uploader.kind == .custom)
    }

    @Test func requiresRequestAndResponseURLForCustomUploaders() {
        let json = Data(#"{"name": "broken", "responseURL": "{{url}}"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try CustomUploader.fromJSON(json)
        }
    }

    @Test func decodesS3UploadersWithoutRequestURL() throws {
        let json = Data("""
        {"name": "r2", "uploaderType": "S3", "s3": {"endpoint": "https://acc.r2.cloudflarestorage.com",
         "region": "auto", "bucket": "shots", "accessKeyId": "AK", "secretAccessKey": "SK",
         "keyTemplate": "{{date}}/{{uuid}}.{{ext}}", "publicURL": "https://img.example.com/{{key}}"}}
        """.utf8)
        let uploader = try CustomUploader.fromJSON(json)
        #expect(uploader.kind == .s3)
        #expect(uploader.s3?.bucket == "shots")
        #expect(uploader.s3?.usesPathStyle == true)
        #expect(uploader.isValid())
    }

    @Test func infersS3KindFromConfiguration() throws {
        let json = Data(#"{"name": "minio", "s3": {"endpoint": "localhost:9000", "bucket": "b", "accessKeyId": "a", "secretAccessKey": "s"}}"#.utf8)
        let uploader = try CustomUploader.fromJSON(json)
        #expect(uploader.kind == .s3)
        #expect(uploader.s3?.region == "us-east-1")
        #expect(uploader.s3?.endpointURL?.absoluteString == "https://localhost:9000")
    }

    @Test func roundTripsThroughJSON() throws {
        let original = CustomUploader.s3(
            name: "aws",
            configuration: S3Configuration(endpoint: "https://s3.eu-west-1.amazonaws.com", region: "eu-west-1", bucket: "b", accessKeyId: "a", secretAccessKey: "s", pathStyle: false, acl: "public-read")
        )
        let decoded = try CustomUploader.fromJSON(original.toJSON())
        #expect(decoded.id == original.id)
        #expect(decoded.s3 == original.s3)
        #expect(decoded.kind == .s3)
    }

    @Test func acceptsTrailingCommas() throws {
        let json = Data(#"{"name": "x", "requestURL": "https://a.b/", "responseURL": "{{url}}",}"#.utf8)
        #expect(try CustomUploader.fromJSON(json).name == "x")
    }
}

struct UploaderValidatorTests {
    func custom(requestURL: String = "https://up.example.com", responseURL: String = "{{url}}", deletionURL: String? = nil, fileFormName: String? = nil) -> CustomUploader {
        CustomUploader(name: "t", requestURL: requestURL, headers: nil, formData: nil, fileFormName: fileFormName, responseURL: responseURL, deletionURL: deletionURL)
    }

    @Test func acceptsValidUploader() {
        #expect(UploaderValidator.issues(for: custom()).isEmpty)
    }

    @Test func rejectsNonHTTPRequestURLs() {
        #expect(UploaderValidator.issues(for: custom(requestURL: "ftp://x")) == [.invalidRequestURL])
        #expect(UploaderValidator.issues(for: custom(requestURL: "WEBHOOK_URL")) == [.invalidRequestURL])
    }

    @Test func rejectsMalformedTemplates() {
        #expect(UploaderValidator.issues(for: custom(responseURL: "{{url}")) == [.malformedTemplate(field: "response URL")])
        #expect(UploaderValidator.issues(for: custom(deletionURL: "{{a{{b}}}}")) == [.malformedTemplate(field: "deletion URL")])
    }

    @Test func rejectsEmptyFileFormName() {
        #expect(UploaderValidator.issues(for: custom(fileFormName: " ")) == [.emptyFileFormName])
    }

    @Test func reportsMissingS3Fields() {
        let uploader = CustomUploader.s3(name: "s", configuration: S3Configuration(endpoint: "", region: "", bucket: "", accessKeyId: "a", secretAccessKey: ""))
        let issues = UploaderValidator.issues(for: uploader)
        #expect(issues.contains(.invalidS3Endpoint))
        #expect(issues.contains(.missingS3Field("bucket")))
        #expect(issues.contains(.missingS3Field("region")))
        #expect(issues.contains(.missingS3Field("secret access key")))
        #expect(!issues.contains(.missingS3Field("access key ID")))
    }

    @Test(arguments: ["{{a}}", "x{{a}}y{{b.c[0]}}", "plain", ""])
    func wellFormedTemplates(template: String) {
        #expect(UploaderValidator.isWellFormedTemplate(template))
    }

    @Test(arguments: ["{{a}", "}}", "{{{{a}}}}", "{{a"])
    func malformedTemplates(template: String) {
        #expect(!UploaderValidator.isWellFormedTemplate(template))
    }
}
