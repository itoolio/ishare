import AppKit
import Foundation
import ishareCore
import Synchronization

struct RecordedResponse: Sendable, Equatable {
    let statusCode: Int?
    let headers: [String: String]
    let body: Data
}

final class ResponseRecorder: Sendable {
    private let recorded = Mutex<[RecordedResponse]>([])

    func record(_ response: HTTPURLResponse?, body: Data) {
        let headers = (response?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        let entry = RecordedResponse(statusCode: response?.statusCode, headers: headers, body: body)
        recorded.withLock { $0.append(entry) }
    }

    var responses: [RecordedResponse] {
        recorded.withLock { $0 }
    }
}

enum UploadDiagnostics {
    @TaskLocal static var recorder: ResponseRecorder?
}

struct UploadTestReport: Sendable, Equatable {
    var statusCode: Int?
    var headers: [(name: String, value: String)]
    var body: String
    var url: String?
    var deletionURL: String?
    var error: String?
    var duration: TimeInterval

    var succeeded: Bool { url != nil && error == nil }

    static func == (lhs: UploadTestReport, rhs: UploadTestReport) -> Bool {
        lhs.statusCode == rhs.statusCode && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value) && lhs.body == rhs.body && lhs.url == rhs.url
            && lhs.deletionURL == rhs.deletionURL && lhs.error == rhs.error
    }
}

@MainActor
enum UploadTester {
    static func run(_ uploader: CustomUploader) async -> UploadTestReport {
        let fileURL: URL
        do {
            fileURL = try makeTestImage()
        } catch {
            return UploadTestReport(headers: [], body: "", error: error.localizedDescription, duration: 0)
        }
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        return await run(uploader, fileURL: fileURL)
    }

    static func run(_ uploader: CustomUploader, fileURL: URL) async -> UploadTestReport {
        let recorder = ResponseRecorder()
        let started = Date()
        let result: Result<UploadOutcome, any Error> = await UploadDiagnostics.$recorder.withValue(recorder) {
            do {
                return try await .success(UploadService.upload(fileURL: fileURL, to: .custom(uploader)))
            } catch {
                return .failure(error)
            }
        }
        let response = recorder.responses.last
        var report = UploadTestReport(
            statusCode: response?.statusCode,
            headers: (response?.headers ?? [:]).sorted { $0.key.lowercased() < $1.key.lowercased() }.map { (name: $0.key, value: $0.value) },
            body: response.map { prettyBody($0.body) } ?? "",
            duration: Date().timeIntervalSince(started)
        )
        switch result {
        case let .success(outcome):
            report.url = outcome.url.absoluteString
            report.deletionURL = outcome.deletionURL
        case let .failure(error):
            report.error = error.localizedDescription
        }
        return report
    }

    static func prettyBody(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            JSONSerialization.isValidJSONObject(object),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let string = String(data: pretty, encoding: .utf8)
        {
            return string
        }
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    static func makeTestImage(size: Int = 16) throws -> URL {
        guard
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "ishare-test.png")
        try ImageEncoder.write(image, as: .PNG, to: url)
        return url
    }
}
