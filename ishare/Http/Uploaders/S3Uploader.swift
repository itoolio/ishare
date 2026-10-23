import Alamofire
import Foundation
import ishareCore

struct S3Uploader: Uploader {
    let uploader: CustomUploader

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty, uploader.s3 != nil else { throw UploadFailure.invalidSpecification(issues) }
        guard let configuration = try S3SecretStore.resolvingSecret(uploader).s3 else { throw UploadFailure.invalidSpecification(issues) }
        let payloadHash = try await Task.detached(priority: .userInitiated) {
            try SigV4Signer.sha256Hex(fileAt: fileURL)
        }.value
        let built = try S3RequestBuilder.upload(
            configuration: configuration, fileURL: fileURL, contentType: MimeType.forFile(fileURL), payloadHash: payloadHash
        )
        let request = UploadService.session.upload(fileURL, to: built.url, method: .put, headers: HTTPHeaders(built.headers))
        _ = try await UploadService.perform(request, progress: progress)
        return UploadOutcome(url: built.publicURL, deletionURL: nil, uploaderID: uploader.id, s3Key: built.key)
    }

    func delete(_ item: HistoryItem) async throws {
        guard let key = item.s3Key, let configuration = try S3SecretStore.resolvingSecret(uploader).s3 else { return }
        let (url, headers) = try S3RequestBuilder.delete(configuration: configuration, key: key)
        _ = try await UploadService.response(of: UploadService.session.request(url, method: .delete, headers: HTTPHeaders(headers)))
    }
}
