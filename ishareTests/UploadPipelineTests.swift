import Foundation
import Testing
@testable import ishare

extension NetworkSuite {
    @MainActor
    @Suite
    struct UploadFanOutTests {
        let spy = UploadEnvironmentSpy()

        init() {
            UploadService.session = StubURLProtocol.makeSession()
            UploadCoordinator.environment = spy
            StubURLProtocol.reset { request in
                switch request.url.host() {
                case "primary.example.com":
                    StubResponse(body: Data(#"{"url": "https://cdn.primary.example.com/a.png"}"#.utf8))
                case "mirror.example.com":
                    StubResponse(body: Data(#"{"url": "https://cdn.mirror.example.com/a.png"}"#.utf8))
                case "down.example.com":
                    StubResponse(status: 503, body: Data("busy".utf8))
                default:
                    StubResponse(status: 400, body: Data("bad".utf8))
                }
            }
        }

        func finish() {
            UploadCoordinator.environment = LiveUploadEnvironment()
        }

        @Test func uploadsToEveryTargetAndRecordsEachResult() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "a.png", contents: TestUploaders.png)
            let targets: [UploadTarget] = [
                .custom(TestUploaders.http(name: "primary", host: "primary.example.com")),
                .custom(TestUploaders.http(name: "mirror", host: "mirror.example.com")),
            ]
            let results = await UploadCoordinator.upload(fileURL: file, to: targets, localFileURL: file)
            #expect(results.count == 2)
            #expect(spy.history.map(\.fileUrl) == ["https://cdn.primary.example.com/a.png", "https://cdn.mirror.example.com/a.png"])
            #expect(spy.history.allSatisfy { $0.localPath == file.path })
            #expect(UploadPlan.urlToDeliver(results)?.absoluteString == "https://cdn.primary.example.com/a.png")
            #expect(StubURLProtocol.captured.count == 2)
        }

        @Test func fallsBackToTheFirstSuccessfulURLAndQueuesRetryableFailures() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "b.png", contents: TestUploaders.png)
            let down = TestUploaders.http(name: "down", host: "down.example.com")
            let targets: [UploadTarget] = [.custom(down), .custom(TestUploaders.http(name: "mirror", host: "mirror.example.com"))]
            let results = await UploadCoordinator.upload(fileURL: file, to: targets, localFileURL: nil)
            #expect((try? results[0].get()) == nil)
            #expect(UploadPlan.urlToDeliver(results)?.absoluteString == "https://cdn.mirror.example.com/a.png")
            #expect(spy.enqueued.map(\.1) == [.custom(down.id)])
            #expect(spy.notifications == ["Upload failed, ishare will retry it later".localized()])
        }

        @Test func reportsAPlainFailureWhenTheQueueRejectsARetryableUpload() async throws {
            defer { finish() }
            UploadCoordinator.environment = FailingQueueUploadEnvironment(wrapped: spy)
            let file = try Fixtures.temporaryFile(named: "e.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(TestUploaders.http(name: "down", host: "down.example.com"))], localFileURL: nil)
            #expect(spy.enqueued.isEmpty)
            #expect(spy.notifications == ["Upload failed".localized()])
        }

        @Test func doesNotQueueClientErrors() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "c.png", contents: TestUploaders.png)
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(TestUploaders.http(name: "x", host: "other.example.com"))], localFileURL: nil)
            #expect(spy.enqueued.isEmpty)
            #expect(spy.notifications == ["Upload failed".localized()])
        }

        @Test func explicitTargetsSkipAdditionalDestinationsAndDeliverOnce() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "d.png", contents: TestUploaders.png)
            let result = await UploadCoordinator.upload(fileURL: file, target: .custom(TestUploaders.http(name: "p", host: "primary.example.com")))
            #expect((try? result.get())?.url.absoluteString == "https://cdn.primary.example.com/a.png")
            #expect(spy.delivered.map(\.absoluteString) == ["https://cdn.primary.example.com/a.png"])
            #expect(StubURLProtocol.captured.count == 1)
        }

        @Test func imgurRejectsTextWithAClearMessage() async throws {
            defer { finish() }
            let file = try Fixtures.temporaryFile(named: "note.txt", contents: Data("hello".utf8))
            let results = await UploadCoordinator.upload(fileURL: file, to: [.imgur(clientID: "cid")], localFileURL: nil)
            #expect(StubURLProtocol.captured.isEmpty)
            #expect(spy.enqueued.isEmpty)
            #expect(throws: UploadFailure.unsupportedFile(destination: "Imgur", fileExtension: "txt")) { try results[0].get() }
            #expect(spy.notifications.first?.contains("Imgur") == true)
        }

        @Test func sendsTextSnippetsWithTheirMimeType() async throws {
            defer { finish() }
            let directory = try Fixtures.temporaryFile(named: "x", contents: Data()).deletingLastPathComponent()
            let file = try TextSnippet.write("# Title\n\nSome *markdown*", in: directory, prefix: "ishare")
            var uploader = TestUploaders.http(name: "paste", host: "primary.example.com")
            uploader = CustomUploader(
                id: uploader.id, name: uploader.name, requestURL: uploader.requestURL, headers: nil, formData: nil, fileFormName: nil,
                requestBodyType: .binary, responseURL: "{{url}}", requestMethod: .put
            )
            _ = await UploadCoordinator.upload(fileURL: file, to: [.custom(uploader)], localFileURL: nil)
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.method == "PUT")
            #expect(request.headers["Content-Type"] == "text/markdown; charset=utf-8")
            #expect(file.pathExtension == "md")
        }
    }

    @MainActor
    @Suite
    struct UploadTesterTests {
        init() {
            UploadService.session = StubURLProtocol.makeSession()
        }

        @Test func reportsStatusHeadersPrettyBodyAndParsedURLs() async throws {
            StubURLProtocol.reset { _ in
                StubResponse(status: 201, headers: ["Content-Type": "application/json", "X-Request-Id": "42"], body: Data(#"{"url":"https://cdn.example.com/t.png","del":"https://cdn.example.com/d/1"}"#.utf8))
            }
            let uploader = TestUploaders.http(name: "t", host: "up.example.com").withTemplates(response: "{{url}}", deletion: "{{del}}")
            let report = await UploadTester.run(uploader)
            #expect(report.statusCode == 201)
            #expect(report.headers.contains { $0.name == "X-Request-Id" && $0.value == "42" })
            #expect(report.body == "{\n  \"del\" : \"https://cdn.example.com/d/1\",\n  \"url\" : \"https://cdn.example.com/t.png\"\n}")
            #expect(report.url == "https://cdn.example.com/t.png")
            #expect(report.deletionURL == "https://cdn.example.com/d/1")
            #expect(report.error == nil)
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.body.range(of: Data([0x89, 0x50, 0x4E, 0x47])) != nil)
        }

        @Test func reportsParsingErrorsAlongsideTheRawResponse() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok".utf8)) }
            let report = await UploadTester.run(TestUploaders.http(name: "t", host: "up.example.com", responseURL: "{{data.link}}"))
            #expect(report.statusCode == 200)
            #expect(report.body == "ok")
            #expect(report.url == nil)
            #expect(report.error == UploadFailure.responseParsing("data.link").localizedDescription)
        }

        @Test func reportsHTTPErrors() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 401, body: Data(#"{"error":"denied"}"#.utf8)) }
            let report = await UploadTester.run(TestUploaders.http(name: "t", host: "up.example.com"))
            #expect(report.statusCode == 401)
            #expect(report.body.contains("\"error\" : \"denied\""))
            #expect(report.succeeded == false)
        }
    }

    @MainActor
    @Suite
    struct S3SecretUploadTests {
        init() {
            UploadService.session = StubURLProtocol.makeSession()
            TestSecrets.install()
        }

        @Test func signsWithTheKeychainSecretAndReturnsPresignedLinks() async throws {
            StubURLProtocol.reset { _ in StubResponse(status: 200, headers: [:], body: Data()) }
            let configuration = S3Configuration(
                endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "b", accessKeyId: "AK", secretAccessKey: "SECRET",
                keyTemplate: "{{filename}}", presignedExpiry: 3600
            )
            let stored = S3SecretStore.movingSecretToKeychain(.s3(name: "aws", configuration: configuration))
            #expect(stored.s3?.secretAccessKey == S3SecretStore.placeholder)
            let file = try Fixtures.temporaryFile(named: "k.png", contents: TestUploaders.png)
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(stored))
            let components = try #require(URLComponents(url: outcome.url, resolvingAgainstBaseURL: false))
            #expect(components.path == "/b/k.png")
            #expect(components.queryItems?.first { $0.name == "X-Amz-Expires" }?.value == "3600")
            #expect(components.queryItems?.contains { $0.name == "X-Amz-Signature" } == true)
            #expect(StubURLProtocol.lastRequest?.headers["Authorization"]?.hasPrefix("AWS4-HMAC-SHA256 Credential=AK/") == true)
        }

        @Test func failsClearlyWhenTheKeychainSecretIsMissing() async throws {
            StubURLProtocol.reset { _ in StubResponse() }
            let configuration = S3Configuration(endpoint: "https://s3.example.com", region: "us-east-1", bucket: "b", accessKeyId: "AK", secretAccessKey: S3SecretStore.placeholder)
            let file = try Fixtures.temporaryFile(named: "m.png", contents: TestUploaders.png)
            await #expect(throws: S3SecretError.missingSecret("other")) {
                try await UploadService.upload(fileURL: file, to: .custom(.s3(name: "other", configuration: configuration)))
            }
            #expect(StubURLProtocol.lastRequest == nil)
        }
    }
}

extension CustomUploader {
    func withTemplates(response: String, deletion: String?) -> CustomUploader {
        CustomUploader(
            id: id, name: name, requestURL: requestURL, headers: headers, formData: formData, fileFormName: fileFormName,
            requestBodyType: requestBodyType, responseURL: response, deletionURL: deletion
        )
    }
}

struct UploadPlanTests {
    @Test func removesThePrimaryAndDuplicatesFromAdditionalDestinations() {
        let id = UUID()
        let other = UUID()
        let additional = UploadPlan.additional([.custom(id), .builtIn(.IMGUR), .custom(other), .custom(other)], excluding: .custom(id))
        #expect(additional == [.builtIn(.IMGUR), .custom(other)])
    }

    @Test func copiesOnlyWhenNoImageIsCopiedInstead() {
        let copyOnly = UploadPlan.deliveryActions(copyURL: true, copyImage: false, openURL: false)
        #expect(copyOnly.copy && !copyOnly.open)
        let imageCopied = UploadPlan.deliveryActions(copyURL: true, copyImage: true, openURL: true)
        #expect(!imageCopied.copy && imageCopied.open)
        let nothing = UploadPlan.deliveryActions(copyURL: false, copyImage: false, openURL: false)
        #expect(!nothing.copy && !nothing.open)
    }

    @Test func classifiesRetryableFailures() {
        #expect(UploadFailure.transport("offline").isRetryable)
        #expect(UploadFailure.http(status: 502, body: nil).isRetryable)
        #expect(UploadFailure.http(status: 429, body: nil).isRetryable)
        #expect(!UploadFailure.http(status: 404, body: nil).isRetryable)
        #expect(!UploadFailure.responseParsing("x").isRetryable)
    }

    @MainActor @Test func detectsTheDestinationChooserModifier() {
        #expect(DestinationChooser.isRequested(flags: [.option, .command], modifier: .option))
        #expect(!DestinationChooser.isRequested(flags: [.command], modifier: .option))
        #expect(!DestinationChooser.isRequested(flags: [.option], modifier: nil))
    }
}

struct TextSnippetTests {
    @Test(arguments: [
        ("{\"a\": [1, 2]}", "json"),
        ("# Release notes\n\n- one\n- two", "md"),
        ("Check [the docs](https://example.com) first", "md"),
        ("import SwiftUI\n\nstruct A: View {}", "swift"),
        ("func greet(name: String) -> String {\n    return name\n}", "swift"),
        ("def main():\n    print('hi')", "py"),
        ("#!/bin/zsh\necho hi", "sh"),
        ("const add = (a, b) => a + b", "js"),
        ("<!DOCTYPE html>\n<html></html>", "html"),
        ("SELECT id FROM users WHERE id = 1;", "sql"),
        ("package main\n\nfunc main() {\n}", "go"),
        ("just a note to self", "txt"),
        ("{ not json", "txt"),
    ])
    func detectsLanguages(pair: (String, String)) {
        #expect(TextSnippet.fileExtension(for: pair.0) == pair.1)
    }

    @Test func writesUTF8FilesWithTheDetectedExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = try TextSnippet.write("héllo wörld", in: directory, prefix: "ishare", date: Date(timeIntervalSince1970: 100))
        #expect(url.lastPathComponent == "ishare-100-paste.txt")
        #expect(try String(contentsOf: url, encoding: .utf8) == "héllo wörld")
    }

    @Test(arguments: [("txt", "text/plain; charset=utf-8"), ("md", "text/markdown; charset=utf-8"), ("json", "application/json; charset=utf-8"), ("swift", "text/plain; charset=utf-8")])
    func mapsTextMimeTypes(pair: (String, String)) {
        #expect(MimeType.forExtension(pair.0) == pair.1)
    }
}
