import Alamofire
import Foundation
import ishareCore

struct HTTPUploader: Uploader {
    let uploader: CustomUploader
    var linkChoice: LinkChoice?

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        let choice = linkChoice ?? LinkOptionsResolver.storedChoice(for: uploader)
        guard let parts = Self.requestParts(for: uploader, fileURL: fileURL, linkChoice: choice) else {
            throw UploadFailure.invalidSpecification([.invalidRequestURL])
        }
        let method = HTTPMethod(rawValue: (uploader.requestMethod ?? .post).rawValue)
        var headers = HTTPHeaders(parts.headers)
        let request: UploadRequest
        switch uploader.requestBodyType ?? .multipartFormData {
        case .multipartFormData:
            let formData = parts.formFields
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
                to: parts.url, method: method, headers: headers
            )
        case .binary:
            headers.add(name: "Content-Type", value: MimeType.forFile(fileURL))
            request = UploadService.session.upload(fileURL, to: parts.url, method: method, headers: headers)
        }
        let data = try await UploadService.perform(request, progress: progress)
        return try Self.outcome(from: data, uploader: uploader)
    }

    nonisolated static func requestParts(for uploader: CustomUploader, fileURL: URL, linkChoice: LinkChoice, now: Date = .init()) -> HTTPRequestParts? {
        guard let url = URL(string: uploader.requestURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        var headers = uploader.headers ?? [:]
        headers["x-file-name"] = UploadFileName.lowercasingExtension(of: fileURL)
        let isMultipart = (uploader.requestBodyType ?? .multipartFormData) == .multipartFormData
        var parts = HTTPRequestParts(url: url, headers: headers, formFields: isMultipart ? uploader.formData ?? [:] : [:])
        LinkOptionsEncoder.apply(linkChoice, spec: uploader.linkOptions, to: &parts, now: now)
        return parts
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
