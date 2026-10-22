import Alamofire
import Foundation

struct HTTPUploader: Uploader {
    let uploader: CustomUploader

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
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
            request = UploadService.session.upload(
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
            request = UploadService.session.upload(fileURL, to: url, method: .post, headers: headers)
        }
        let data = try await UploadService.perform(request, progress: progress)
        return try Self.outcome(from: data, uploader: uploader)
    }

    func delete(_ item: HistoryItem) async throws {
        guard let deletionURL = item.deletionUrl, let request = UploadService.deletionRequest(for: deletionURL, uploader: uploader) else { return }
        _ = try await UploadService.response(of: UploadService.session.request(request))
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
}
