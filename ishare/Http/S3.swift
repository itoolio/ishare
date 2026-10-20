import CryptoKit
import Foundation

struct S3Configuration: Codable, Hashable, Sendable {
    var endpoint: String
    var region: String
    var bucket: String
    var accessKeyId: String
    var secretAccessKey: String
    var pathStyle: Bool?
    var keyTemplate: String?
    var acl: String?
    var publicURL: String?

    static let defaultKeyTemplate = "{{filename}}"

    init(
        endpoint: String, region: String, bucket: String, accessKeyId: String, secretAccessKey: String,
        pathStyle: Bool? = nil, keyTemplate: String? = nil, acl: String? = nil, publicURL: String? = nil
    ) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.pathStyle = pathStyle
        self.keyTemplate = keyTemplate
        self.acl = acl
        self.publicURL = publicURL
    }

    enum CodingKeys: String, CodingKey {
        case endpoint
        case region
        case bucket
        case accessKeyId = "accesskeyid"
        case secretAccessKey = "secretaccesskey"
        case pathStyle = "pathstyle"
        case keyTemplate = "keytemplate"
        case acl
        case publicURL = "publicurl"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        endpoint = try container.decodeDynamic(String.self, forKey: .key(named: "endpoint"))
        region = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "region")) ?? "us-east-1"
        bucket = try container.decodeDynamic(String.self, forKey: .key(named: "bucket"))
        accessKeyId = try container.decodeDynamic(String.self, forKey: .key(named: "accesskeyid"))
        secretAccessKey = try container.decodeDynamic(String.self, forKey: .key(named: "secretaccesskey"))
        pathStyle = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "pathstyle"))
        keyTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "keytemplate"))
        acl = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "acl"))
        publicURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "publicurl"))
    }

    var usesPathStyle: Bool { pathStyle ?? true }

    var endpointURL: URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized), url.host() != nil else { return nil }
        return url
    }

    func objectURL(for key: String) -> URL? {
        guard let endpointURL, var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let encodedKey = S3Path.encode(key)
        if usesPathStyle {
            components.percentEncodedPath = "\(basePath)/\(S3Path.encodeSegment(bucket))/\(encodedKey)"
        } else {
            components.host = "\(bucket).\(host)"
            components.percentEncodedPath = "\(basePath)/\(encodedKey)"
        }
        return components.url
    }

    func publicURL(for key: String) throws -> URL? {
        guard let template = publicURL?.trimmingCharacters(in: .whitespaces), !template.isEmpty else {
            return objectURL(for: key)
        }
        let host = endpointURL?.host() ?? ""
        let rendered = try ResponseTemplate.render(template) { name in
            switch name.lowercased() {
            case "key": S3Path.encode(key)
            case "rawkey": key
            case "bucket": bucket
            case "region": region
            case "host": host
            case "endpoint": endpointURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            default: nil
            }
        }
        return URL(string: rendered)
    }
}

enum S3Path {
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encodeSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? segment
    }

    static func encode(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).map { encodeSegment(String($0)) }.joined(separator: "/")
    }
}

struct S3KeyContext: Sendable {
    var fileName: String
    var date: Date = .init()
    var uuid: UUID = .init()
    var randomToken: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
}

enum S3KeyTemplate {
    static func render(_ template: String?, context: S3KeyContext) throws -> String {
        let source = (template?.isEmpty ?? true) ? S3Configuration.defaultKeyTemplate : template!
        let fileURL = URL(fileURLWithPath: context.fileName)
        let ext = fileURL.pathExtension.lowercased()
        let name = fileURL.deletingPathExtension().lastPathComponent
        let fileName = ext.isEmpty ? name : "\(name).\(ext)"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: context.date)
        let date = String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let key = try ResponseTemplate.render(source) { placeholder in
            switch placeholder.lowercased() {
            case "filename": fileName
            case "name": name
            case "ext": ext
            case "uuid": context.uuid.uuidString.lowercased()
            case "timestamp": String(Int(context.date.timeIntervalSince1970))
            case "date": date
            case "year": String(format: "%04d", parts.year ?? 0)
            case "month": String(format: "%02d", parts.month ?? 0)
            case "day": String(format: "%02d", parts.day ?? 0)
            case "random": context.randomToken
            default: nil
            }
        }
        return key.drop(while: { $0 == "/" }).description
    }
}

struct SigV4Signer: Sendable {
    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let service: String

    init(accessKeyId: String, secretAccessKey: String, region: String, service: String = "s3") {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.region = region
        self.service = service
    }

    static let emptyPayloadHash = sha256Hex(Data())

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func timestamps(for date: Date) -> (amzDate: String, shortDate: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        return (amzDate, String(amzDate.prefix(8)))
    }

    struct Signature: Equatable {
        let canonicalRequest: String
        let stringToSign: String
        let signature: String
        let signedHeaders: String
        let authorization: String
    }

    func signature(method: String, url: URL, headers: [String: String], payloadHash: String, date: Date) -> Signature {
        let (amzDate, shortDate) = Self.timestamps(for: date)
        var allHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        allHeaders["host"] = allHeaders["host"] ?? hostHeader(for: url)
        allHeaders["x-amz-date"] = amzDate
        allHeaders["x-amz-content-sha256"] = allHeaders["x-amz-content-sha256"] ?? payloadHash

        let sortedNames = allHeaders.keys.sorted()
        let canonicalHeaders = sortedNames.map { name in
            "\(name):\(normalizeHeaderValue(allHeaders[name] ?? ""))\n"
        }.joined()
        let signedHeaders = sortedNames.joined(separator: ";")

        let canonicalRequest = [
            method.uppercased(),
            canonicalURI(for: url),
            canonicalQuery(for: url),
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(shortDate)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signingKey = derivedKey(shortDate: shortDate)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey)
            .map { String(format: "%02x", $0) }.joined()
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return Signature(
            canonicalRequest: canonicalRequest, stringToSign: stringToSign, signature: signature,
            signedHeaders: signedHeaders, authorization: authorization
        )
    }

    func signedHeaders(method: String, url: URL, headers: [String: String], payloadHash: String, date: Date = .init()) -> [String: String] {
        let result = signature(method: method, url: url, headers: headers, payloadHash: payloadHash, date: date)
        var signed = headers
        signed["x-amz-date"] = Self.timestamps(for: date).amzDate
        signed["x-amz-content-sha256"] = payloadHash
        signed["Authorization"] = result.authorization
        return signed
    }

    private func derivedKey(shortDate: String) -> SymmetricKey {
        let secret = SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8))
        let dateKey = hmac(secret, shortDate)
        let regionKey = hmac(dateKey, region)
        let serviceKey = hmac(regionKey, service)
        return hmac(serviceKey, "aws4_request")
    }

    private func hmac(_ key: SymmetricKey, _ message: String) -> SymmetricKey {
        SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)))
    }

    private func hostHeader(for url: URL) -> String {
        guard let host = url.host() else { return "" }
        if let port = url.port, !((url.scheme == "https" && port == 443) || (url.scheme == "http" && port == 80)) {
            return "\(host):\(port)"
        }
        return host
    }

    private func normalizeHeaderValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    private func canonicalURI(for url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        return path.isEmpty ? "/" : path
    }

    private func canonicalQuery(for url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else {
            return ""
        }
        let pairs: [(name: String, value: String)] = items.map { item in
            (S3Path.encodeSegment(item.name), S3Path.encodeSegment(item.value ?? ""))
        }
        let sorted = pairs.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }
        return sorted.map { pair in pair.name + "=" + pair.value }.joined(separator: "&")
    }
}

struct S3UploadRequest: Sendable {
    let url: URL
    let key: String
    let headers: [String: String]
    let publicURL: URL
}

enum S3RequestBuilder {
    enum BuildError: LocalizedError {
        case invalidEndpoint
        case invalidPublicURL

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "The S3 endpoint is not a valid URL"
            case .invalidPublicURL: "The public URL template did not produce a valid URL"
            }
        }
    }

    static func upload(
        configuration: S3Configuration, fileURL: URL, contentType: String, payloadHash: String,
        context: S3KeyContext? = nil, date: Date = .init()
    ) throws -> S3UploadRequest {
        let keyContext = context ?? S3KeyContext(fileName: fileURL.lastPathComponent, date: date)
        let key = try S3KeyTemplate.render(configuration.keyTemplate, context: keyContext)
        guard let objectURL = configuration.objectURL(for: key) else { throw BuildError.invalidEndpoint }
        guard let publicURL = try configuration.publicURL(for: key) else { throw BuildError.invalidPublicURL }
        var headers = ["Content-Type": contentType]
        if let acl = configuration.acl?.trimmingCharacters(in: .whitespaces), !acl.isEmpty {
            headers["x-amz-acl"] = acl
        }
        let signer = SigV4Signer(
            accessKeyId: configuration.accessKeyId, secretAccessKey: configuration.secretAccessKey,
            region: configuration.region
        )
        let signed = signer.signedHeaders(method: "PUT", url: objectURL, headers: headers, payloadHash: payloadHash, date: date)
        return S3UploadRequest(url: objectURL, key: key, headers: signed, publicURL: publicURL)
    }

    static func delete(configuration: S3Configuration, key: String, date: Date = .init()) throws -> (URL, [String: String]) {
        guard let objectURL = configuration.objectURL(for: key) else { throw BuildError.invalidEndpoint }
        let signer = SigV4Signer(
            accessKeyId: configuration.accessKeyId, secretAccessKey: configuration.secretAccessKey,
            region: configuration.region
        )
        let headers = signer.signedHeaders(
            method: "DELETE", url: objectURL, headers: [:], payloadHash: SigV4Signer.emptyPayloadHash, date: date
        )
        return (objectURL, headers)
    }
}
