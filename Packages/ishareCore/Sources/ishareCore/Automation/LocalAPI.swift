import Foundation

public struct LocalAPIRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    public enum Parsed: Equatable, Sendable {
        case incomplete
        case invalid
        case complete(LocalAPIRequest)
    }

    public static let maximumSize = 1_048_576
    public static let defaultPort: UInt16 = 47811

    public static func parse(_ data: Data) -> Parsed {
        guard data.count <= maximumSize else { return .invalid }
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), let target = URLComponents(string: String(parts[1])) else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return .incomplete }
        var query: [String: String] = [:]
        for item in target.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return .complete(LocalAPIRequest(method: String(parts[0]).uppercased(), path: target.path, query: query, headers: headers, body: Data(body.prefix(length))))
    }

    public func isAuthorized(token: String) -> Bool {
        guard !token.isEmpty, let header = headers["authorization"], header.hasPrefix("Bearer ") else { return false }
        let supplied = Array(header.dropFirst("Bearer ".count).utf8)
        let expected = Array(token.utf8)
        guard supplied.count == expected.count else { return false }
        return zip(supplied, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public var toolName: String? {
        let components = path.split(separator: "/")
        guard components.count == 2, components[0] == "v1" else { return nil }
        return String(components[1])
    }

    public static func response(status: Int, body: Data, contentType: String = "application/json") -> Data {
        let reason =
            switch status {
            case 200: "OK"
            case 400: "Bad Request"
            case 401: "Unauthorized"
            case 404: "Not Found"
            case 405: "Method Not Allowed"
            case 422: "Unprocessable Content"
            default: "Error"
            }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        return Data(head.utf8) + body
    }

    public static func makeToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
