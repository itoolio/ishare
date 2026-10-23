import Alamofire
import Foundation
import ishareCore

struct WebDAVUploader: Uploader {
    let uploader: CustomUploader
    var now: @Sendable () -> Date = { Date() }

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let configuration = try resolvedConfiguration()
        let plan = try WebDAVRequestBuilder.plan(
            configuration: configuration, fileName: fileURL.lastPathComponent, contentType: MimeType.forFile(fileURL), date: now()
        )
        let credential = credential(for: configuration)
        for directory in plan.directories {
            try await createDirectory(directory, credential: credential)
        }
        var request = UploadService.session.upload(
            fileURL, to: plan.upload.url, method: .put, headers: HTTPHeaders(plan.upload.headers)
        )
        if let credential {
            request = request.authenticate(with: credential)
        }
        _ = try await UploadService.perform(request, progress: progress)
        return UploadOutcome(url: plan.resultURL, deletionURL: nil, uploaderID: uploader.id, s3Key: plan.path)
    }

    func delete(_ item: HistoryItem) async throws {
        guard let path = item.s3Key else { return }
        let configuration = try resolvedConfiguration()
        let built = try WebDAVRequestBuilder.delete(configuration: configuration, path: path)
        var request = UploadService.session.request(built.url, method: .delete, headers: HTTPHeaders(built.headers))
        if let credential = credential(for: configuration) {
            request = request.authenticate(with: credential)
        }
        _ = try await UploadService.response(of: request)
    }

    private func resolvedConfiguration() throws -> WebDAVConfiguration {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty else { throw UploadFailure.invalidSpecification(issues) }
        guard let configuration = try UploaderSecrets.resolvingSecrets(uploader).webdav else {
            throw UploadFailure.invalidSpecification([.missingRemoteConfiguration])
        }
        return configuration
    }

    private func credential(for configuration: WebDAVConfiguration) -> URLCredential? {
        guard configuration.authenticationMethod == .digest, let username = configuration.username, !username.isEmpty else { return nil }
        return URLCredential(user: username, password: configuration.password ?? "", persistence: .forSession)
    }

    private func createDirectory(_ directory: WebDAVRequest, credential: URLCredential?) async throws {
        var request = UploadService.session.request(directory.url, method: HTTPMethod(rawValue: directory.method), headers: HTTPHeaders(directory.headers))
        if let credential {
            request = request.authenticate(with: credential)
        }
        let response = await request.serializingData(emptyResponseCodes: Set(100 ..< 600)).response
        UploadDiagnostics.recorder?.record(response.response, body: response.data ?? Data())
        guard let status = response.response?.statusCode else {
            throw UploadFailure.transport(response.error?.localizedDescription ?? "The WebDAV server didn't respond")
        }
        guard WebDAVRequestBuilder.directoryAcceptedStatuses.contains(status) else {
            throw WebDAVError.directoryFailed(path: directory.url.path(percentEncoded: false), status: status)
        }
    }
}

extension WebDAVError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The WebDAV URL must be a valid http or https URL".localized()
        case let .directoryFailed(path, status):
            String(format: "Creating the folder %@ on the WebDAV server failed with status %d".localized(), path, status)
        }
    }
}
