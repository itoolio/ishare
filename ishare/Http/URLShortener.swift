import Alamofire
import Defaults
import Foundation
import ishareCore

enum URLShortenerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case isgd
    case vgd
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .isgd: "is.gd"
        case .vgd: "v.gd"
        case .custom: "Custom"
        }
    }
}

enum ShortenerRequestMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case get = "GET"
    case post = "POST"

    var id: Self { self }
}

struct CustomShortener: Codable, Hashable, Sendable {
    var requestURL: String = ""
    var method: ShortenerRequestMethod = .get
    var headers: [String: String] = [:]
    var body: String = ""
    var responseTemplate: String = "{{response}}"
}

struct URLShortenerConfiguration: Codable, Hashable, Sendable, Defaults.Serializable {
    var kind: URLShortenerKind = .none
    var custom = CustomShortener()

    static let none = URLShortenerConfiguration()

    var isEnabled: Bool { kind != .none }

    var request: CustomShortener? {
        switch kind {
        case .none: nil
        case .isgd: CustomShortener(requestURL: "https://is.gd/create.php?format=simple&url={{url_encoded}}")
        case .vgd: CustomShortener(requestURL: "https://v.gd/create.php?format=simple&url={{url_encoded}}")
        case .custom: custom
        }
    }
}

enum URLShortenerError: LocalizedError, Equatable {
    case invalidRequest(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRequest(detail):
            String(format: "The URL shortener request is invalid (%@)".localized(), detail)
        case let .invalidResponse(detail):
            String(format: "The URL shortener returned no usable URL (%@)".localized(), detail)
        }
    }
}

enum URLShortenerRequest {
    static let encodingAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    static func encoded(_ url: URL) -> String {
        url.absoluteString.addingPercentEncoding(withAllowedCharacters: encodingAllowed) ?? url.absoluteString
    }

    static func fill(_ template: String, with url: URL) throws -> String {
        do {
            return try ResponseTemplate.render(template) { placeholder in
                switch placeholder {
                case "url": url.absoluteString
                case "url_encoded": encoded(url)
                default: nil
                }
            }
        } catch let ResponseTemplateError.missingValue(placeholder) {
            throw URLShortenerError.invalidRequest(placeholder)
        }
    }

    static func make(_ shortener: CustomShortener, for url: URL) throws -> URLRequest {
        let address = try fill(shortener.requestURL.trimmingCharacters(in: .whitespaces), with: url)
        guard let requestURL = URL(string: address), let scheme = requestURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw URLShortenerError.invalidRequest(address)
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = shortener.method.rawValue
        for (name, value) in shortener.headers.sorted(by: { $0.key < $1.key }) {
            request.setValue(try fill(value, with: url), forHTTPHeaderField: name)
        }
        if shortener.method == .post, !shortener.body.isEmpty {
            request.httpBody = Data(try fill(shortener.body, with: url).utf8)
        }
        return request
    }

    static func shortURL(from data: Data, template: String) throws -> URL {
        let rendered: String
        do {
            rendered = try ResponseTemplate.render(template.isEmpty ? "{{response}}" : template, data: data)
        } catch let ResponseTemplateError.missingValue(path) {
            throw URLShortenerError.invalidResponse(path)
        }
        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else {
            throw URLShortenerError.invalidResponse(String(trimmed.prefix(200)))
        }
        return url
    }
}

@MainActor
enum URLShortenerService {
    static func shorten(_ url: URL, with configuration: URLShortenerConfiguration) async throws -> URL? {
        guard let shortener = configuration.request else { return nil }
        let request = try URLShortenerRequest.make(shortener, for: url)
        let data = try await UploadService.response(of: UploadService.session.request(request))
        return try URLShortenerRequest.shortURL(from: data, template: shortener.responseTemplate)
    }

    static func shortenedOrNil(_ url: URL, with configuration: URLShortenerConfiguration) async -> URL? {
        guard configuration.isEnabled else { return nil }
        do {
            return try await shorten(url, with: configuration)
        } catch {
            Log.upload.error("Shortening \(url.absoluteString, privacy: .public) failed, using the long URL: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
