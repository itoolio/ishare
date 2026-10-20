import Foundation
import SwiftyJSON

enum ResponseTemplateError: Error, Equatable {
    case missingValue(String)
}

enum ResponseTemplate {
    static var placeholderPattern: Regex<(Substring, Substring)> { /\{\{([^}]+)\}\}/ }

    static func placeholders(in template: String) -> [String] {
        template.matches(of: placeholderPattern).map { String($0.output.1) }
    }

    static func render(_ template: String, json: JSON) throws -> String {
        try render(template) { path in
            value(at: path, in: json)
        }
    }

    static func render(_ template: String, data: Data) throws -> String {
        let json = JSON(data)
        let rawBody = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try render(template) { path in
            if path == "response" || path == "body" {
                return rawBody
            }
            return value(at: path, in: json)
        }
    }

    static func render(_ template: String, resolve: (String) -> String?) throws -> String {
        var result = ""
        var cursor = template.startIndex
        for match in template.matches(of: placeholderPattern) {
            result += template[cursor ..< match.range.lowerBound]
            let path = String(match.output.1).trimmingCharacters(in: .whitespaces)
            guard let replacement = resolve(path) else {
                throw ResponseTemplateError.missingValue(path)
            }
            result += replacement
            cursor = match.range.upperBound
        }
        result += template[cursor...]
        return result
    }

    static func value(at path: String, in json: JSON) -> String? {
        var current = json
        for component in pathComponents(path) {
            switch component {
            case let .index(index):
                current = current[index]
            case let .key(key):
                current = current[key]
            }
            if current.type == .null || current.type == .unknown {
                return nil
            }
        }
        switch current.type {
        case .string, .number, .bool:
            return current.stringValue
        default:
            return current.rawString(options: []) ?? nil
        }
    }

    enum PathComponent: Equatable {
        case key(String)
        case index(Int)
    }

    static func pathComponents(_ path: String) -> [PathComponent] {
        path.split(separator: ".").flatMap { element in
            element.split(whereSeparator: { $0 == "[" || $0 == "]" }).map { part -> PathComponent in
                if let index = Int(part) {
                    return .index(index)
                }
                return .key(String(part))
            }
        }
    }
}
