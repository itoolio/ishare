import AppKit
import BezelNotification
import Defaults
import Foundation

enum UploadType: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case IMGUR, CUSTOM

    var id: Self { self }
}

@MainActor
enum UploadCoordinator {
    static func currentTarget() -> UploadTarget? {
        switch Defaults[.uploadType] {
        case .IMGUR:
            return .imgur(clientID: Defaults[.imgurClientId])
        case .CUSTOM:
            return target(forUploaderID: Defaults[.activeCustomUploader])
        }
    }

    static func target(forUploaderID id: UUID?) -> UploadTarget? {
        guard let id, let uploader = CustomUploader.allCases.first(where: { $0.id == id }) else { return nil }
        return .custom(uploader)
    }

    @discardableResult
    static func upload(fileURL: URL, target explicitTarget: UploadTarget? = nil, localFileURL: URL? = nil) async -> Result<UploadOutcome, any Error> {
        guard let target = explicitTarget ?? currentTarget() else {
            BezelNotification.show(messageText: "No uploader is selected".localized(), icon: ToastIcon)
            return .failure(UploadFailure.missingUploader)
        }
        let progressIndicator = UploadManager.shared
        progressIndicator.begin()
        defer { progressIndicator.uploadCompleted() }
        do {
            let outcome = try await UploadService.upload(fileURL: fileURL, to: target) { fraction in
                Task { @MainActor in
                    progressIndicator.updateProgress(fraction: fraction)
                }
            }
            record(outcome, localFileURL: localFileURL)
            if !Defaults[.copyImageToClipboard] {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(outcome.url.absoluteString, forType: .string)
            }
            return .success(outcome)
        } catch {
            NSLog("Upload failed: %@", error.localizedDescription)
            BezelNotification.show(messageText: "Upload failed".localized(), icon: ToastIcon)
            return .failure(error)
        }
    }

    static func record(_ outcome: UploadOutcome, localFileURL: URL?) {
        addToUploadHistory(
            HistoryItem(
                fileUrl: outcome.url.absoluteString,
                deletionUrl: outcome.deletionURL,
                uploaderId: outcome.uploaderID,
                s3Key: outcome.s3Key,
                localPath: localFileURL?.path,
                date: Date()
            )
        )
    }

    static func delete(_ item: HistoryItem) async throws {
        let uploader = item.uploaderId.flatMap { id in CustomUploader.allCases.first { $0.id == id } }
        if let key = item.s3Key, let uploader {
            try await UploadService.deleteS3Object(key: key, uploader: uploader)
            return
        }
        guard let deletionURL = item.deletionUrl, var request = UploadService.deletionRequest(for: deletionURL, uploader: uploader) else {
            return
        }
        if uploader == nil, request.url?.host()?.contains("imgur.com") == true {
            request.httpMethod = "DELETE"
            request.setValue("Client-ID " + Defaults[.imgurClientId], forHTTPHeaderField: "Authorization")
        }
        _ = try await UploadService.response(of: UploadService.session.request(request))
    }
}

@MainActor
func uploadFile(fileURL: URL, uploadType _: UploadType? = nil, localFileURL: URL? = nil, completion: @Sendable @escaping () -> Void) {
    Task { @MainActor in
        await UploadCoordinator.upload(fileURL: fileURL, localFileURL: localFileURL)
        completion()
    }
}
