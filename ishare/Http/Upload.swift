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
            Log.upload.info("Uploaded to \(outcome.url.absoluteString, privacy: .public)")
            record(outcome, localFileURL: localFileURL)
            if !Defaults[.copyImageToClipboard] {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(outcome.url.absoluteString, forType: .string)
            }
            return .success(outcome)
        } catch {
            Log.upload.error("Upload failed: \(error.localizedDescription, privacy: .public)")
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
        if let target = target(for: item) {
            try await target.uploader.delete(item)
        } else if let deletionURL = item.deletionUrl, let request = UploadService.deletionRequest(for: deletionURL, uploader: nil) {
            _ = try await UploadService.response(of: UploadService.session.request(request))
        }
    }

    static func target(for item: HistoryItem) -> UploadTarget? {
        if let id = item.uploaderId {
            return target(forUploaderID: id)
        }
        guard item.deletionUrl.flatMap(URL.init(string:))?.host()?.contains("imgur.com") == true else { return nil }
        return .imgur(clientID: Defaults[.imgurClientId])
    }
}

@MainActor
func uploadFile(fileURL: URL, uploadType _: UploadType? = nil, localFileURL: URL? = nil, completion: @Sendable @escaping () -> Void) {
    Task { @MainActor in
        await UploadCoordinator.upload(fileURL: fileURL, localFileURL: localFileURL)
        completion()
    }
}
