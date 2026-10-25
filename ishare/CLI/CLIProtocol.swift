import Foundation
import Security

enum CLICaptureMode: String, Codable, CaseIterable, Sendable {
    case region
    case window
    case screen
    case scrolling
    case menu
}

enum CLIRecordAction: String, Codable, CaseIterable, Sendable {
    case start
    case stop
    case toggle
}

enum CLICommand: Codable, Equatable, Sendable {
    case upload(files: [String], uploader: String?)
    case capture(mode: CLICaptureMode, upload: Bool)
    case record(CLIRecordAction)
    case listUploaders
    case history(limit: Int)
}

struct CLIRequest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = CLIRequest.currentVersion
    let id: UUID
    let command: CLICommand
    var createdAt = Date()
}

struct CLIUploadResult: Codable, Equatable, Sendable {
    let file: String
    var link: String?
    var error: String?
}

struct CLICaptureResult: Codable, Equatable, Sendable {
    let file: String?
    var link: String?
}

struct CLIUploaderInfo: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: String
    let selected: Bool
}

struct CLIHistoryEntry: Codable, Equatable, Sendable {
    let link: String?
    var shortLink: String?
    var title: String
    var date: Date?
    var uploader: String?
    var altText: String?
    var deletionLink: String?
    var localPath: String?
}

struct CLIResponsePayload: Codable, Equatable, Sendable {
    var message: String?
    var uploads: [CLIUploadResult]?
    var capture: CLICaptureResult?
    var uploaders: [CLIUploaderInfo]?
    var history: [CLIHistoryEntry]?
    var recording: Bool?
}

struct CLIResponse: Codable, Equatable, Sendable {
    let id: UUID
    let success: Bool
    var error: String?
    var payload = CLIResponsePayload()

    static func failure(_ id: UUID, _ message: String) -> CLIResponse {
        CLIResponse(id: id, success: false, error: message)
    }
}

enum CLICoding {
    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<Value: Encodable>(_ value: Value, pretty: Bool = false) throws -> Data {
        try encoder(pretty: pretty).encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try decoder().decode(type, from: data)
    }
}

enum CLIAppGroup {
    static let identifier = "L988J7YMK5.group.dev.adrian.ishare"
    static let notificationName = Notification.Name("dev.adrian.ishare.cli.response")
    static let urlScheme = "ishare"
    static let bundleIdentifiers = ["dev.adrian.ishare"]

    static var signedIdentifier: String {
        guard let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil),
            let groups = value as? [String],
            let group = groups.first(where: { $0.hasSuffix("group.dev.adrian.ishare") })
        else { return identifier }
        return group
    }

    static var mailboxDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: signedIdentifier)?
            .appending(path: "CommandLine", directoryHint: .isDirectory)
    }

    static func requestURL(for id: UUID) -> URL {
        URL(string: "\(urlScheme)://cli?id=\(id.uuidString)")!
    }
}

struct CLIMailbox: Sendable {
    let directory: URL

    static let staleAge: TimeInterval = 15 * 60

    var requestsDirectory: URL { directory.appending(path: "requests", directoryHint: .isDirectory) }
    var responsesDirectory: URL { directory.appending(path: "responses", directoryHint: .isDirectory) }

    func requestFile(for id: UUID) -> URL {
        requestsDirectory.appending(path: "\(id.uuidString).json")
    }

    func responseFile(for id: UUID) -> URL {
        responsesDirectory.appending(path: "\(id.uuidString).json")
    }

    func write(_ request: CLIRequest) throws {
        try FileManager.default.createDirectory(at: requestsDirectory, withIntermediateDirectories: true)
        try CLICoding.encode(request).write(to: requestFile(for: request.id), options: .atomic)
    }

    func takeRequest(_ id: UUID) throws -> CLIRequest {
        let file = requestFile(for: id)
        let data = try Data(contentsOf: file)
        try? FileManager.default.removeItem(at: file)
        let request = try CLICoding.decode(CLIRequest.self, from: data)
        guard request.id == id else { throw CLIProtocolError.mismatchedRequest }
        guard request.version <= CLIRequest.currentVersion else { throw CLIProtocolError.unsupportedVersion(request.version) }
        return request
    }

    func write(_ response: CLIResponse) throws {
        try FileManager.default.createDirectory(at: responsesDirectory, withIntermediateDirectories: true)
        try CLICoding.encode(response).write(to: responseFile(for: response.id), options: .atomic)
    }

    func takeResponse(for id: UUID) -> CLIResponse? {
        let file = responseFile(for: id)
        guard let data = try? Data(contentsOf: file), let response = try? CLICoding.decode(CLIResponse.self, from: data) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return response.id == id ? response : nil
    }

    func removeRequest(_ id: UUID) {
        try? FileManager.default.removeItem(at: requestFile(for: id))
    }

    func removeStaleFiles(now: Date = Date()) {
        for folder in [requestsDirectory, responsesDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
                if now.timeIntervalSince(modified) > Self.staleAge {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}

enum CLIProtocolError: Error, Equatable, CustomStringConvertible {
    case mismatchedRequest
    case unsupportedVersion(Int)
    case noMailbox
    case launchFailed(String)
    case timedOut(TimeInterval)

    var description: String {
        switch self {
        case .mismatchedRequest: "The request file doesn't match its ID."
        case let .unsupportedVersion(version): "ishare doesn't understand request version \(version). Update ishare."
        case .noMailbox: "The ishare app group container isn't available."
        case let .launchFailed(reason): "Couldn't reach ishare: \(reason)"
        case let .timedOut(seconds): "ishare didn't answer within \(Int(seconds)) seconds."
        }
    }
}
