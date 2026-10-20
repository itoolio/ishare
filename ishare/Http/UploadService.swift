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
        switch target {
        case let .imgur(clientID):
            try await uploadToImgur(fileURL: fileURL, clientID: clientID, progress: progress)
        case let .custom(uploader):
            switch uploader.kind {
            case .custom:
                try await uploadToCustom(fileURL: fileURL, uploader: uploader, progress: progress)
            case .s3:
                try await uploadToS3(fileURL: fileURL, uploader: uploader, progress: progress)
            }
        }
    }

    static func uploadToImgur(
        fileURL: URL, clientID: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadOutcome {
        let formName = ["mp4", "mov"].contains(fileURL.pathExtension.lowercased()) ? "video" : "image"
        let fileName = "ishare.\(fileURL.pathExtension.lowercased())"
        let mimeType = MimeType.forFile(fileURL)
        let request = session.upload(
            multipartFormData: { form in
                form.append(fileURL, withName: formName, fileName: fileName, mimeType: mimeType)
            },
            to: imgurEndpoint, method: .post, headers: ["Authorization": "Client-ID " + clientID]
        )
        let data = try await perform(request, progress: progress)
        let link = try ResponseTemplate.render("{{data.link}}", data: data)
        guard let url = URL(string: link) else { throw UploadFailure.responseParsing(link) }
        let deleteHash = try? ResponseTemplate.render("{{data.deletehash}}", data: data)
        return UploadOutcome(
            url: url, deletionURL: deleteHash.map { "https://api.imgur.com/3/image/\($0)" }, uploaderID: nil, s3Key: nil
        )
    }

    static func uploadToCustom(
        fileURL: URL, uploader: CustomUploader, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let url = URL(string: uploader.requestURL.trimmingCharacters(in: .whitespaces)) else {
            throw UploadFailure.invalidSpecification([.invalidRequestURL])
        }
        var headers = HTTPHeaders(uploader.headers ?? [:])
        headers.add(name: "x-file-name", value: UploadFileName.lowercasingExtension(of: fileURL))
        let request: UploadRequest
        switch uploader.requestBodyType ?? .multipartFormData {
        case .multipartFormData:
            let formData = uploader.formData ?? [:]
            let formName = uploader.fileFormName ?? "file"
            let fileName = UploadFileName.lowercasingExtension(of: fileURL)
            let mimeType = MimeType.forFile(fileURL)
            request = session.upload(
                multipartFormData: { form in
                    for (key, value) in formData.sorted(by: { $0.key < $1.key }) {
                        form.append(Data(value.utf8), withName: key)
                    }
                    form.append(fileURL, withName: formName, fileName: fileName, mimeType: mimeType)
                },
                to: url, method: .post, headers: headers
            )
        case .binary:
            headers.add(name: "Content-Type", value: MimeType.forFile(fileURL))
            request = session.upload(fileURL, to: url, method: .post, headers: headers)
        }
        let data = try await perform(request, progress: progress)
        return try outcome(from: data, uploader: uploader)
    }

    static func outcome(from data: Data, uploader: CustomUploader) throws -> UploadOutcome {
        let fileURLString: String
        do {
            fileURLString = try ResponseTemplate.render(uploader.responseURL, data: data)
        } catch let ResponseTemplateError.missingValue(path) {
            throw UploadFailure.responseParsing(path)
        }
        guard let url = URL(string: fileURLString.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
            throw UploadFailure.responseParsing(fileURLString)
        }
        let deletionURL = uploader.deletionURL.flatMap { template -> String? in
            guard !template.isEmpty else { return nil }
            return try? ResponseTemplate.render(template, data: data)
        }
        return UploadOutcome(url: url, deletionURL: deletionURL, uploaderID: uploader.id, s3Key: nil)
    }

    static func uploadToS3(
        fileURL: URL, uploader: CustomUploader, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty, let configuration = uploader.s3 else { throw UploadFailure.invalidSpecification(issues) }
        let payloadHash = try await Task.detached(priority: .userInitiated) {
            try SigV4Signer.sha256Hex(fileAt: fileURL)
        }.value
        let built = try S3RequestBuilder.upload(
            configuration: configuration, fileURL: fileURL, contentType: MimeType.forFile(fileURL), payloadHash: payloadHash
        )
        let request = session.upload(fileURL, to: built.url, method: .put, headers: HTTPHeaders(built.headers))
        _ = try await perform(request, progress: progress)
        return UploadOutcome(url: built.publicURL, deletionURL: nil, uploaderID: uploader.id, s3Key: built.key)
    }

    static func deleteS3Object(key: String, uploader: CustomUploader) async throws {
        guard let configuration = uploader.s3 else { throw UploadFailure.missingUploader }
        let (url, headers) = try S3RequestBuilder.delete(configuration: configuration, key: key)
        let request = session.request(url, method: .delete, headers: HTTPHeaders(headers))
        _ = try await response(of: request)
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
