import Defaults
import Foundation
import ishareCore
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

struct AssistantAnswers: Equatable, Sendable {
    var service = ""
    var endpoint = ""
    var authHeaderName = ""
    var authHeaderValue = ""
    var fileFieldName = ""
    var exampleResponse = ""
    var notes = ""

    var prompt: String {
        var lines = ["Build an ishare custom uploader."]
        if !service.isEmpty { lines.append("Service: \(service)") }
        if !endpoint.isEmpty { lines.append("Upload endpoint: \(endpoint)") }
        if !authHeaderName.isEmpty { lines.append("Authentication header name: \(authHeaderName)") }
        if !fileFieldName.isEmpty { lines.append("Multipart file field name: \(fileFieldName)") }
        if !exampleResponse.isEmpty { lines.append("Example JSON response after a successful upload:\n\(exampleResponse)") }
        if !notes.isEmpty { lines.append("Additional notes from the user:\n\(notes)") }
        return lines.joined(separator: "\n")
    }
}

struct GeneratedUploaderSpec: Equatable, Sendable {
    var name: String
    var requestURL: String
    var bodyType: String
    var fileFormName: String
    var headerNames: [String]
    var headerValues: [String]
    var formFieldNames: [String]
    var formFieldValues: [String]
    var responseURL: String
    var deletionURL: String
    var deletionMethod: String
}

enum UploaderAssistantMapper {
    static func template(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("{{") || trimmed.lowercased().hasPrefix("http") {
            return trimmed
        }
        let path = trimmed.hasPrefix("$.") ? String(trimmed.dropFirst(2)) : trimmed
        return "{{\(path)}}"
    }

    static func uploader(from spec: GeneratedUploaderSpec, answers: AssistantAnswers) -> CustomUploader {
        var headers: [String: String] = [:]
        for (name, value) in zip(spec.headerNames, spec.headerValues) where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            headers[name] = value
        }
        let authName = answers.authHeaderName.trimmingCharacters(in: .whitespaces)
        if !authName.isEmpty {
            headers = headers.filter { $0.key.lowercased() != authName.lowercased() }
            headers[authName] = answers.authHeaderValue
        }
        var formData: [String: String] = [:]
        for (name, value) in zip(spec.formFieldNames, spec.formFieldValues) where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            formData[name] = value
        }
        let isBinary = spec.bodyType.lowercased().contains("binary") || spec.bodyType.lowercased() == "raw"
        let endpoint = answers.endpoint.trimmingCharacters(in: .whitespaces)
        let fileField = answers.fileFieldName.trimmingCharacters(in: .whitespaces).isEmpty ? spec.fileFormName : answers.fileFieldName
        let deletion = template(spec.deletionURL)
        let name = spec.name.trimmingCharacters(in: .whitespaces).isEmpty ? answers.service : spec.name
        return CustomUploader(
            name: name.isEmpty ? "Uploader" : name,
            requestURL: endpoint.isEmpty ? spec.requestURL.trimmingCharacters(in: .whitespaces) : endpoint,
            headers: headers.isEmpty ? nil : headers,
            formData: isBinary || formData.isEmpty ? nil : formData,
            fileFormName: isBinary || fileField.trimmingCharacters(in: .whitespaces).isEmpty ? nil : fileField.trimmingCharacters(in: .whitespaces),
            requestBodyType: isBinary ? .binary : .multipartFormData,
            responseURL: template(spec.responseURL),
            deletionURL: deletion.isEmpty ? nil : deletion,
            deleteRequestType: deletion.isEmpty ? nil : (spec.deletionMethod.uppercased() == "DELETE" ? .delete : .get)
        )
    }
}

enum UploaderAssistantAvailability {
    static var isAvailable: Bool {
        if ScreenshotMode.isActive {
            return true
        }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }
}

enum AssistantError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Apple Intelligence is not available on this Mac"
    }
}


enum AssistantRefinement {
    static func jsonObjects(in text: String) -> [Any] {
        var results: [Any] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"":
                inString = depth > 0
            case "{", "[":
                if depth == 0 { start = index }
                depth += 1
            case "}", "]":
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let begin = start {
                    let candidate = String(text[begin ... index])
                    if let object = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) {
                        results.append(object)
                    }
                    start = nil
                }
            default:
                break
            }
        }
        return results
    }

    static func urlPath(in object: Any, prefix: String = "") -> String? {
        if let dictionary = object as? [String: Any] {
            let preferred = ["url", "link", "src", "href", "fileurl", "file_url", "image"]
            let keys = dictionary.keys.sorted { lhs, rhs in
                let left = preferred.firstIndex(of: lhs.lowercased()) ?? preferred.count
                let right = preferred.firstIndex(of: rhs.lowercased()) ?? preferred.count
                return left == right ? lhs < rhs : left < right
            }
            for key in keys where !key.lowercased().contains("delet") {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                if let value = dictionary[key] as? String, value.lowercased().hasPrefix("http") {
                    return path
                }
                if let nested = dictionary[key], !(nested is String), let found = urlPath(in: nested, prefix: path) {
                    return found
                }
            }
        }
        if let array = object as? [Any] {
            for (index, element) in array.enumerated() {
                if let value = element as? String, value.lowercased().hasPrefix("http") {
                    return "\(prefix)[\(index)]"
                }
                if let found = urlPath(in: element, prefix: "\(prefix)[\(index)]") {
                    return found
                }
            }
        }
        return nil
    }

    static func isUsableDeletionTemplate(_ template: String, examples: [Any]) -> Bool {
        let placeholders = ResponseTemplate.placeholders(in: template)
        guard placeholders.allSatisfy({ $0.wholeMatch(of: /[A-Za-z0-9_\-.\[\]]+/) != nil }) else { return false }
        if template.lowercased().hasPrefix("http") {
            return true
        }
        guard template.hasPrefix("{{") else { return false }
        guard let example = examples.last, let data = try? JSONSerialization.data(withJSONObject: example) else { return true }
        return (try? ResponseTemplate.render(template, data: data)).map { $0.lowercased().hasPrefix("http") } ?? false
    }

    static func refine(_ uploader: CustomUploader, conversation: String) -> CustomUploader {
        var responseURL = uploader.responseURL
        let examples = jsonObjects(in: conversation)
        if let example = examples.last, let data = try? JSONSerialization.data(withJSONObject: example) {
            let resolves = (try? ResponseTemplate.render(responseURL, data: data)).map { $0.lowercased().hasPrefix("http") } ?? false
            if !resolves, let path = urlPath(in: example) {
                responseURL = "{{\(path)}}"
            }
        }
        var deletionURL = uploader.deletionURL
        if let deletion = deletionURL, !isUsableDeletionTemplate(deletion, examples: examples) {
            deletionURL = nil
        }
        let headerValues = Set((uploader.headers ?? [:]).values)
        let formData = uploader.formData?.filter { !headerValues.contains($0.value) }
        return CustomUploader(
            id: uploader.id, name: uploader.name, requestURL: uploader.requestURL, headers: uploader.headers,
            formData: (formData?.isEmpty ?? true) ? nil : formData, fileFormName: uploader.fileFormName,
            requestBodyType: uploader.requestBodyType, responseURL: responseURL, deletionURL: deletionURL,
            deleteRequestType: deletionURL == nil ? nil : uploader.deleteRequestType
        )
    }
}
