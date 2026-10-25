import Alamofire
import Foundation
import ishareCore
import Testing
@testable import ishare

enum S3IntegrationEnvironment {
    static let values = ProcessInfo.processInfo.environment

    static var endpoint: String? { nonEmpty("ISHARE_S3_ENDPOINT") }
    static var virtualHostEndpoint: String? { nonEmpty("ISHARE_S3_VIRTUAL_HOST_ENDPOINT") }
    static var accessKey: String { nonEmpty("ISHARE_S3_ACCESS_KEY") ?? "minioadmin" }
    static var secretKey: String { nonEmpty("ISHARE_S3_SECRET_KEY") ?? "minioadmin" }
    static var region: String { nonEmpty("ISHARE_S3_REGION") ?? "us-east-1" }
    static var publicBucket: String { nonEmpty("ISHARE_S3_BUCKET") ?? "ishare-integration" }
    static var privateBucket: String { nonEmpty("ISHARE_S3_PRIVATE_BUCKET") ?? "ishare-integration-private" }

    static var isConfigured: Bool { endpoint != nil }
    static var supportsVirtualHosts: Bool { isConfigured && virtualHostEndpoint != nil }

    private static func nonEmpty(_ name: String) -> String? {
        guard let value = values[name]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

extension NetworkSuite {
    @MainActor
    @Suite(.enabled(if: S3IntegrationEnvironment.isConfigured, "Set ISHARE_S3_ENDPOINT to run the S3 integration tests against a live server"))
    struct S3IntegrationTests {
        let http: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }()

        init() {
            UploadService.session = Session(configuration: .ephemeral)
        }

        func configuration(
            bucket: String = S3IntegrationEnvironment.publicBucket, endpoint: String = S3IntegrationEnvironment.endpoint ?? "",
            pathStyle: Bool = true, presignedExpiry: Int? = nil
        ) -> S3Configuration {
            S3Configuration(
                endpoint: endpoint, region: S3IntegrationEnvironment.region, bucket: bucket,
                accessKeyId: S3IntegrationEnvironment.accessKey, secretAccessKey: S3IntegrationEnvironment.secretKey,
                pathStyle: pathStyle, keyTemplate: "integration/{{uuid}}.{{ext}}", presignedExpiry: presignedExpiry
            )
        }

        func signedRequest(_ method: String, _ url: URL, body: Data = Data(), configuration: S3Configuration) -> URLRequest {
            let signer = SigV4Signer(
                accessKeyId: configuration.accessKeyId, secretAccessKey: configuration.secretAccessKey, region: configuration.region
            )
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body.isEmpty ? nil : body
            for (name, value) in signer.signedHeaders(method: method, url: url, headers: [:], payloadHash: SigV4Signer.sha256Hex(body)) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            return request
        }

        func fetch(_ request: URLRequest) async throws -> (Int, Data) {
            let (data, response) = try await http.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }

        func bucketURL(_ configuration: S3Configuration, query: String? = nil) throws -> URL {
            let base = try #require(configuration.endpointURL)
            var components = try #require(URLComponents(url: base, resolvingAgainstBaseURL: false))
            let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
            components.percentEncodedPath = "\(path)/\(configuration.bucket)"
            components.percentEncodedQuery = query
            return try #require(components.url)
        }

        func ensureBucket(_ configuration: S3Configuration, publicRead: Bool) async throws {
            let (created, body) = try await fetch(signedRequest("PUT", bucketURL(configuration), configuration: configuration))
            #expect(created == 200 || created == 409, "Creating the bucket failed: \(String(decoding: body, as: UTF8.self))")
            guard publicRead else { return }
            let policy = Data(
                """
                {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":["*"]},"Action":["s3:GetObject"],"Resource":["arn:aws:s3:::\(configuration.bucket)/*"]}]}
                """.utf8)
            let (applied, policyBody) = try await fetch(signedRequest("PUT", bucketURL(configuration, query: "policy"), body: policy, configuration: configuration))
            #expect(applied == 204 || applied == 200, "Setting the bucket policy failed: \(String(decoding: policyBody, as: UTF8.self))")
        }

        func payload() -> Data {
            Data((0 ..< 200_000).map { UInt8(($0 * 31) % 251) })
        }

        func upload(_ payload: Data, named name: String, configuration: S3Configuration) async throws -> UploadOutcome {
            let file = try Fixtures.temporaryFile(named: name, contents: payload)
            return try await UploadService.upload(fileURL: file, to: .custom(.s3(name: "integration", configuration: configuration)))
        }

        @Test func uploadsAndServesThePublicURL() async throws {
            let configuration = configuration()
            try await ensureBucket(configuration, publicRead: true)
            let bytes = payload()
            let outcome = try await upload(bytes, named: "public.png", configuration: configuration)
            let key = try #require(outcome.s3Key)
            #expect(key.hasPrefix("integration/") && key.hasSuffix(".png"))
            #expect(outcome.url == configuration.objectURL(for: key))
            let (status, body) = try await fetch(URLRequest(url: outcome.url))
            #expect(status == 200)
            #expect(body == bytes)
        }

        @Test func servesPresignedLinksToPrivateObjects() async throws {
            let configuration = configuration(bucket: S3IntegrationEnvironment.privateBucket, presignedExpiry: 300)
            try await ensureBucket(configuration, publicRead: false)
            let bytes = payload()
            let outcome = try await upload(bytes, named: "private.jpg", configuration: configuration)
            #expect(outcome.url.query()?.contains("X-Amz-Signature=") == true)
            let (status, body) = try await fetch(URLRequest(url: outcome.url))
            #expect(status == 200)
            #expect(body == bytes)
            let key = try #require(outcome.s3Key)
            let (anonymous, _) = try await fetch(URLRequest(url: try #require(configuration.objectURL(for: key))))
            #expect(anonymous == 403)
            var tampered = try #require(URLComponents(url: outcome.url, resolvingAgainstBaseURL: false))
            tampered.percentEncodedQuery = tampered.percentEncodedQuery?.replacingOccurrences(of: "X-Amz-Expires=300", with: "X-Amz-Expires=301")
            let (rejected, _) = try await fetch(URLRequest(url: try #require(tampered.url)))
            #expect(rejected == 403)
        }

        @Test func deletesUploadedObjects() async throws {
            let configuration = configuration()
            try await ensureBucket(configuration, publicRead: true)
            let outcome = try await upload(payload(), named: "delete-me.png", configuration: configuration)
            let key = try #require(outcome.s3Key)
            let uploader = S3Uploader(uploader: .s3(name: "integration", configuration: configuration))
            try await uploader.delete(HistoryItem(fileUrl: outcome.url.absoluteString, s3Key: key))
            let objectURL = try #require(configuration.objectURL(for: key))
            let (status, _) = try await fetch(signedRequest("GET", objectURL, configuration: configuration))
            #expect(status == 404)
        }

        @Test func deletesExpiredUploadsThroughTheExpiryRunner() async throws {
            let configuration = configuration()
            try await ensureBucket(configuration, publicRead: true)
            var uploader = CustomUploader.s3(name: "integration-expiry", configuration: configuration)
            uploader.autoDeleteAfterDays = 1
            let file = try Fixtures.temporaryFile(named: "expire.png", contents: payload())
            let outcome = try await UploadService.upload(fileURL: file, to: .custom(uploader))
            let key = try #require(outcome.s3Key)
            let objectURL = try #require(configuration.objectURL(for: key))
            let (uploaded, _) = try await fetch(signedRequest("GET", objectURL, configuration: configuration))
            #expect(uploaded == 200)
            _ = try await ExpiryIntegration.expireAndDelete(outcome, uploader: uploader)
            let (deleted, _) = try await fetch(signedRequest("GET", objectURL, configuration: configuration))
            #expect(deleted == 404)
        }

        @Test func uploadsWithPathStyleURLs() async throws {
            let configuration = configuration(pathStyle: true)
            try await ensureBucket(configuration, publicRead: true)
            let outcome = try await upload(payload(), named: "path.png", configuration: configuration)
            let endpointHost = try #require(configuration.endpointURL?.host())
            #expect(outcome.url.host() == endpointHost)
            #expect(outcome.url.path().hasPrefix("/\(configuration.bucket)/integration/"))
            let (status, _) = try await fetch(URLRequest(url: outcome.url))
            #expect(status == 200)
        }

        @Test(.enabled(if: S3IntegrationEnvironment.supportsVirtualHosts, "Set ISHARE_S3_VIRTUAL_HOST_ENDPOINT to test virtual-hosted style"))
        func uploadsWithVirtualHostedURLs() async throws {
            try await ensureBucket(configuration(), publicRead: true)
            let virtual = configuration(endpoint: try #require(S3IntegrationEnvironment.virtualHostEndpoint), pathStyle: false)
            let bytes = payload()
            let outcome = try await upload(bytes, named: "virtual.png", configuration: virtual)
            let endpointHost = try #require(virtual.endpointURL?.host())
            #expect(outcome.url.host() == "\(virtual.bucket).\(endpointHost)")
            #expect(outcome.url.path().hasPrefix("/integration/"))
            let (status, body) = try await fetch(URLRequest(url: outcome.url))
            #expect(status == 200)
            #expect(body == bytes)
            let presigned = configuration(
                bucket: S3IntegrationEnvironment.privateBucket, endpoint: try #require(S3IntegrationEnvironment.virtualHostEndpoint),
                pathStyle: false, presignedExpiry: 120
            )
            try await ensureBucket(configuration(bucket: S3IntegrationEnvironment.privateBucket), publicRead: false)
            let signed = try await upload(bytes, named: "virtual-private.png", configuration: presigned)
            let (signedStatus, signedBody) = try await fetch(URLRequest(url: signed.url))
            #expect(signedStatus == 200)
            #expect(signedBody == bytes)
        }
    }
}
