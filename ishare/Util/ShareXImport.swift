import Foundation

enum ShareXImportError: LocalizedError, Equatable {
    case missingRequestURL
    case unsupportedBody(String)
    case unsupportedMethod(String)
    case unsupportedDestination(String)
    case unsupportedSyntax(field: String, token: String)

    var errorDescription: String? {
        switch self {
        case .missingRequestURL:
            "The ShareX uploader has no request URL"
        case let .unsupportedBody(body):
            "ishare can't send \(body) request bodies, only multipart form data or binary"
        case let .unsupportedMethod(method):
            "ishare can't upload with the \(method) method"
        case let .unsupportedDestination(destination):
            "ishare can't import \(destination) uploaders"
        case let .unsupportedSyntax(field, token):
            "The \(field) uses \(token), which ishare doesn't support"
        }
    }
}

struct ShareXUploader: Decodable {
    var name: String?
    var destinationType: String?
    var requestMethod: String?
    var requestURL: String?
    var parameters: [String: String]?
    var headers: [String: String]?
    var body: String?
    var arguments: [String: String]?
    var fileFormName: String?
    var url: String?
    var deletionURL: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        name = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "name"))
        destinationType = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "destinationtype"))
        requestMethod = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "requestmethod"))
        requestURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "requesturl"))
        parameters = try container.decodeDynamicIfPresent([String: String].self, forKey: .key(named: "parameters"))
        headers = try container.decodeDynamicIfPresent([String: String].self, forKey: .key(named: "headers"))
        body = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "body"))
        arguments = try container.decodeDynamicIfPresent([String: String].self, forKey: .key(named: "arguments"))
        fileFormName = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "fileformname"))
        url = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "url"))
        deletionURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "deletionurl"))
    }
}

enum ShareXImport {
    static let fileExtension = "sxcu"

    static func uploader(from data: Data, fallbackName: String? = nil) throws -> CustomUploader {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try convert(decoder.decode(ShareXUploader.self, from: data), fallbackName: fallbackName)
    }

    static func convert(_ source: ShareXUploader, fallbackName: String? = nil) throws -> CustomUploader {
        guard let rawRequestURL = source.requestURL?.trimmingCharacters(in: .whitespaces), !rawRequestURL.isEmpty else {
            throw ShareXImportError.missingRequestURL
        }
        try rejectTokens(in: rawRequestURL, field: "request URL")
        let destinations = (source.destinationType ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let fileDestinations: Set<String> = ["ImageUploader", "FileUploader", "TextUploader"]
        if !destinations.isEmpty, !destinations.contains(where: fileDestinations.contains) {
            throw ShareXImportError.unsupportedDestination(source.destinationType ?? "")
        }
        let method = try requestMethod(source.requestMethod)
        let bodyType = try bodyType(source.body)
        for (field, values) in [("headers", source.headers), ("arguments", source.arguments), ("parameters", source.parameters)] {
            for value in (values ?? [:]).values {
                try rejectTokens(in: value, field: field)
            }
        }
        let requestURL = appendingQuery(source.parameters, to: rawRequestURL)
        let responseTemplate = source.url?.trimmingCharacters(in: .whitespaces) ?? ""
        let responseURL = responseTemplate.isEmpty ? "{{response}}" : try convertTemplate(responseTemplate, field: "URL")
        let deletionURL = try source.deletionURL
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { try convertTemplate($0, field: "deletion URL") }
        let isMultipart = bodyType == .multipartFormData
        return CustomUploader(
            name: displayName(source.name, fallback: fallbackName, requestURL: requestURL),
            requestURL: requestURL,
            headers: nilIfEmpty(source.headers),
            formData: isMultipart ? nilIfEmpty(source.arguments) : nil,
            fileFormName: isMultipart ? (source.fileFormName.flatMap { $0.isEmpty ? nil : $0 } ?? "file") : nil,
            requestBodyType: bodyType,
            responseURL: responseURL,
            deletionURL: deletionURL,
            deleteRequestType: deletionURL == nil ? nil : .get,
            requestMethod: method == .post ? nil : method
        )
    }

    static func requestMethod(_ raw: String?) throws -> UploadRequestMethod {
        guard let raw, !raw.isEmpty else { return .post }
        guard let method = UploadRequestMethod(rawValue: raw.uppercased()) else {
            throw ShareXImportError.unsupportedMethod(raw.uppercased())
        }
        return method
    }

    static func bodyType(_ raw: String?) throws -> RequestBodyType {
        switch raw?.lowercased() {
        case nil, "", "multipartformdata": .multipartFormData
        case "binary": .binary
        case .some: throw ShareXImportError.unsupportedBody(raw ?? "")
        }
    }

    static func convertTemplate(_ template: String, field: String) throws -> String {
        let modern = try replaceTokens(in: template, pattern: /\{([A-Za-z]+)(?::([^{}]*))?\}/, field: field)
        return try replaceTokens(in: modern, pattern: /\$([A-Za-z]+)(?::([^$]*))?\$/, field: field)
    }

    private static func replaceTokens(in template: String, pattern: Regex<(Substring, Substring, Substring?)>, field: String) throws -> String {
        var result = ""
        var cursor = template.startIndex
        for match in template.matches(of: pattern) {
            if template[cursor ..< match.range.lowerBound].hasSuffix("{"), template[match.range.upperBound...].hasPrefix("}") {
                continue
            }
            result += template[cursor ..< match.range.lowerBound]
            let function = match.output.1.lowercased()
            let argument = match.output.2.map(String.init)
            switch (function, argument) {
            case ("json", let path?):
                result += "{{\(jsonPath(path))}}"
            case ("response", nil):
                result += "{{response}}"
            default:
                throw ShareXImportError.unsupportedSyntax(field: field, token: String(match.output.0))
            }
            cursor = match.range.upperBound
        }
        result += template[cursor...]
        return result
    }

    private static func rejectTokens(in value: String, field: String) throws {
        if let match = value.firstMatch(of: /\{[A-Za-z]+(?::[^{}]*)?\}|\$[A-Za-z]+(?::[^$]*)?\$/) {
            throw ShareXImportError.unsupportedSyntax(field: field, token: String(match.output))
        }
    }

    static func jsonPath(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$.") {
            trimmed.removeFirst(2)
        } else if trimmed.hasPrefix("$") {
            trimmed.removeFirst()
        }
        return trimmed
    }

    private static func appendingQuery(_ parameters: [String: String]?, to requestURL: String) -> String {
        guard let parameters, !parameters.isEmpty, var components = URLComponents(string: requestURL) else { return requestURL }
        let items = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = (components.queryItems ?? []) + items
        return components.string ?? requestURL
    }

    private static func displayName(_ name: String?, fallback: String?, requestURL: String) -> String {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let fallback, !fallback.isEmpty { return fallback }
        return URL(string: requestURL)?.host() ?? "ShareX"
    }

    private static func nilIfEmpty(_ dictionary: [String: String]?) -> [String: String]? {
        guard let dictionary, !dictionary.isEmpty else { return nil }
        return dictionary
    }
}

enum UploaderFile {
    static let iscuExtension = "iscu"

    static func decode(_ data: Data, fileExtension: String, fallbackName: String? = nil) throws -> CustomUploader {
        switch fileExtension.lowercased() {
        case ShareXImport.fileExtension:
            try ShareXImport.uploader(from: data, fallbackName: fallbackName)
        default:
            try CustomUploader.fromJSON(data)
        }
    }

    static func decode(contentsOf url: URL) throws -> CustomUploader {
        try decode(Data(contentsOf: url), fileExtension: url.pathExtension, fallbackName: url.deletingPathExtension().lastPathComponent)
    }
}
