import Foundation
import Testing
@testable import ishareCore

struct CustomUploaderTests {
    static let exampleFiles = ["chibisafe", "copyparty", "discord", "lumen", "zipline", "zipline-protected", "zipline-cdn", "s3", "folder", "photos"]

    @Test(arguments: exampleFiles)
    func decodesBundledExamples(name: String) throws {
        let uploader = try CustomUploader.fromJSON(Fixtures.data("examples/\(name).iscu"))
        #expect(uploader.name == name)
    }

    @Test func decodesKeysCaseInsensitively() throws {
        let json = Data(
            """
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
        let json = Data(
            """
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
            configuration: S3Configuration(
                endpoint: "https://s3.eu-west-1.amazonaws.com", region: "eu-west-1", bucket: "b", accessKeyId: "a", secretAccessKey: "s", pathStyle: false, acl: "public-read")
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

struct ShareXImportTests {
    static let imgurStyle = """
        {
          "Version": "15.0.0",
          "Name": "Zipline",
          "DestinationType": "ImageUploader, TextUploader, FileUploader",
          "RequestMethod": "POST",
          "RequestURL": "https://zipline.example.com/api/upload",
          "Headers": {
            "Authorization": "secret-token",
            "Format": "random"
          },
          "Body": "MultipartFormData",
          "Arguments": {
            "album": "shots"
          },
          "FileFormName": "file",
          "URL": "{json:files[0]}",
          "DeletionURL": "https://zipline.example.com/api/delete/{json:id}",
          "ErrorMessage": "{json:error}"
        }
        """

    static let legacyBinary = """
        {
          "Name": "Legacy",
          "DestinationType": "ImageUploader",
          "RequestType": "PUT",
          "RequestMethod": "put",
          "RequestURL": "https://legacy.example.com/upload",
          "Parameters": { "key": "abc" },
          "Body": "Binary",
          "URL": "$json:data.link$",
          "DeletionURL": "$json:data.delete$",
        }
        """

    @Test func importsMultipartUploadersWithModernSyntax() throws {
        let uploader = try ShareXImport.uploader(from: Data(Self.imgurStyle.utf8))
        #expect(uploader.name == "Zipline")
        #expect(uploader.requestURL == "https://zipline.example.com/api/upload")
        #expect(uploader.headers == ["Authorization": "secret-token", "Format": "random"])
        #expect(uploader.formData == ["album": "shots"])
        #expect(uploader.fileFormName == "file")
        #expect(uploader.requestBodyType == .multipartFormData)
        #expect(uploader.responseURL == "{{files[0]}}")
        #expect(uploader.deletionURL == "https://zipline.example.com/api/delete/{{id}}")
        #expect(uploader.requestMethod == nil)
        #expect(uploader.isValid())
    }

    @Test func importsBinaryUploadersWithLegacySyntaxAndQueryParameters() throws {
        let uploader = try ShareXImport.uploader(from: Data(Self.legacyBinary.utf8))
        #expect(uploader.requestURL == "https://legacy.example.com/upload?key=abc")
        #expect(uploader.requestBodyType == .binary)
        #expect(uploader.requestMethod == .put)
        #expect(uploader.formData == nil)
        #expect(uploader.fileFormName == nil)
        #expect(uploader.responseURL == "{{data.link}}")
        #expect(uploader.deletionURL == "{{data.delete}}")
    }

    @Test func usesTheResponseBodyWhenNoURLIsGivenAndFallsBackToTheFileName() throws {
        let json = #"{"RequestURL": "https://paste.example.com/", "FileFormName": "f"}"#
        let uploader = try UploaderFile.decode(Data(json.utf8), fileExtension: "SXCU", fallbackName: "my paste")
        #expect(uploader.name == "my paste")
        #expect(uploader.responseURL == "{{response}}")
        #expect(uploader.fileFormName == "f")
    }

    @Test func convertsJSONPathPrefixes() throws {
        #expect(try ShareXImport.convertTemplate("{json:$.data.url}", field: "URL") == "{{data.url}}")
        #expect(try ShareXImport.convertTemplate("https://x/{json:files[0].name}?r={response}", field: "URL") == "https://x/{{files[0].name}}?r={{response}}")
    }

    @Test func rejectsUnsupportedFeatures() {
        #expect(throws: ShareXImportError.unsupportedBody("JSON")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "Body": "JSON"}"#.utf8))
        }
        #expect(throws: ShareXImportError.unsupportedSyntax(field: "URL", token: "{regex:1}")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "URL": "{regex:1}"}"#.utf8))
        }
        #expect(throws: ShareXImportError.unsupportedDestination("URLShortener")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "DestinationType": "URLShortener"}"#.utf8))
        }
        #expect(throws: ShareXImportError.unsupportedMethod("GET")) {
            try ShareXImport.uploader(from: Data(#"{"RequestURL": "https://a.b", "RequestMethod": "GET"}"#.utf8))
        }
        #expect(throws: ShareXImportError.missingRequestURL) {
            try ShareXImport.uploader(from: Data(#"{"Name": "x"}"#.utf8))
        }
    }

    @Test func keepsIscuFilesOnTheIshareDecoder() throws {
        let uploader = try UploaderFile.decode(Fixtures.data("examples/zipline.iscu"), fileExtension: "iscu")
        #expect(uploader.name == "zipline")
    }

    @Test func roundTripsRequestMethodAndModificationDate() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TestUploaders.http(name: "m", host: "a.example.com")
        var modified = original
        modified.requestMethod = .patch
        modified.modifiedAt = date
        let decoded = try CustomUploader.fromJSON(modified.toJSON())
        #expect(decoded.requestMethod == .patch)
        #expect(decoded.modifiedAt == date)
        #expect(try CustomUploader.fromJSON(Data(#"{"name":"x","requestURL":"https://a.b","responseURL":"{{u}}","requestMethod":"put"}"#.utf8)).requestMethod == .put)
    }
}

struct PKCETests {
    @Test func derivesTheRFC7636Challenge() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatesURLSafeVerifiersOfAValidLength() {
        let pkce = PKCE.generate()
        #expect((43 ... 128).contains(pkce.verifier.count))
        #expect(pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE.generate().verifier != pkce.verifier)
    }
}
