import Alamofire
import Foundation
import UniformTypeIdentifiers

struct UploadOutcome: Sendable, Equatable {
    let url: URL
    let deletionURL: String?
    let uploaderID: UUID?
    let s3Key: String?
}

enum UploadTarget: Sendable {
    case imgur(clientID: String)
    case custom(CustomUploader)

    var uploader: any Uploader {
        switch self {
        case let .imgur(clientID):
            ImgurUploader(clientID: clientID)
        case let .custom(uploader) where uploader.kind == .s3:
            S3Uploader(uploader: uploader)
        case let .custom(uploader):
            HTTPUploader(uploader: uploader)
        }
    }
}

enum UploadFailure: LocalizedError, Equatable {
    case missingUploader
    case invalidSpecification([UploaderIssue])
    case http(status: Int, body: String?)
    case responseParsing(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingUploader:
            "No uploader is selected"
        case let .invalidSpecification(issues):
            issues.map(\.message).joined(separator: "\n")
        case let .http(status, body):
            "The server responded with status \(status)" + (body.map { ": \($0.prefix(300))" } ?? "")
        case let .responseParsing(detail):
            "Couldn't read the upload URL from the response (\(detail))"
        case let .transport(detail):
            detail
        }
    }
}

enum MimeType {
    static func forFile(_ url: URL) -> String {
        forExtension(url.pathExtension)
    }

    static func forExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "webp": return "image/webp"
        default:
            return UTType(filenameExtension: ext.lowercased())?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}

enum UploadFileName {
    static func lowercasingExtension(of url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return url.lastPathComponent }
        return url.deletingPathExtension().lastPathComponent + "." + ext.lowercased()
    }
}

@MainActor
enum UploadService {
    static var session: Session = AF
    static var imgurEndpoint = URL(string: "https://api.imgur.com/3/upload")!
    static let successCodes = Set(200 ..< 300)

    static func upload(
        fileURL: URL, to target: UploadTarget,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> UploadOutcome {
        try await target.uploader.upload(fileURL: fileURL, progress: progress)
    }

    static func perform(_ request: UploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> Data {
        request.uploadProgress { value in
            progress(value.fractionCompleted)
        }
        return try await response(of: request)
    }

    static func response(of request: DataRequest) async throws -> Data {
        let response = await request.serializingData(emptyResponseCodes: successCodes, emptyRequestMethods: [.put, .delete, .post, .get]).response
        let status = response.response?.statusCode ?? 0
        let data = response.data ?? Data()
        if let error = response.error, response.response == nil {
            throw UploadFailure.transport(error.underlyingError?.localizedDescription ?? error.localizedDescription)
        }
        guard successCodes.contains(status) else {
            throw UploadFailure.http(status: status, body: String(data: data, encoding: .utf8))
        }
        return data
    }

    static func deletionRequest(for deletionURL: String, uploader: CustomUploader?) -> URLRequest? {
        guard let url = URL(string: deletionURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = (uploader?.deleteRequestType ?? .get).rawValue
        for (name, value) in uploader?.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
