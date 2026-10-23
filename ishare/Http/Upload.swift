import AppKit
import BezelNotification
import Defaults
import Foundation

enum UploadType: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case IMGUR, CUSTOM

    var id: Self { self }
}

struct UploadEnvironment {
    var recordHistory: @MainActor (HistoryItem) -> Void
    var notify: @MainActor (String) -> Void
    var enqueue: @MainActor (URL, UploadTarget, String?, any Error) throws -> Void
    var deliver: @MainActor (URL) -> Void
    var showsProgress = true

    @MainActor static let live = UploadEnvironment(
        recordHistory: { addToUploadHistory($0) },
        notify: { BezelNotification.show(messageText: $0, icon: ToastIcon) },
        enqueue: { fileURL, target, localPath, error in
            try UploadQueue.shared.enqueue(fileURL: fileURL, target: target, localPath: localPath, error: error)
        },
        deliver: { url in
            let actions = UploadPlan.deliveryActions(
                copyURL: Defaults[.copyURLAfterUpload], copyImage: Defaults[.copyImageToClipboard], openURL: Defaults[.openURLAfterUpload]
            )
            if actions.copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            if actions.open {
                NSWorkspace.shared.open(url)
            }
        }
    )
}

enum UploadPlan {
    static func additional(_ destinations: [UploadDestination], excluding primary: UploadDestination) -> [UploadDestination] {
        var seen: Set<UploadDestination> = [primary]
        return destinations.filter { seen.insert($0).inserted }
    }

    static func urlToDeliver(_ results: [Result<UploadOutcome, any Error>]) -> URL? {
        results.lazy.compactMap { try? $0.get().deliveredURL }.first
    }

    static func hasSuccess(_ results: [Result<UploadOutcome, any Error>]) -> Bool {
        results.contains { if case .success = $0 { true } else { false } }
    }

    static func deliveryActions(copyURL: Bool, copyImage: Bool, openURL: Bool) -> (copy: Bool, open: Bool) {
        (copyURL && !copyImage, openURL)
    }
}

@MainActor
enum UploadCoordinator {
    static var environment = UploadEnvironment.live

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

    static func target(for destination: UploadDestination) -> UploadTarget? {
        switch destination {
        case .builtIn(.IMGUR): .imgur(clientID: Defaults[.imgurClientId])
        case .builtIn(.CUSTOM): currentTarget()
        case let .custom(id): target(forUploaderID: id)
        }
    }

    static func additionalTargets(for primary: UploadTarget, destinations: [UploadDestination] = Defaults[.additionalUploadDestinations]) -> [UploadTarget] {
        UploadPlan.additional(destinations, excluding: primary.destination).compactMap(target(for:))
    }

    @discardableResult
    static func upload(fileURL: URL, target explicitTarget: UploadTarget? = nil, localFileURL: URL? = nil) async -> Result<UploadOutcome, any Error> {
        guard let primary = explicitTarget ?? currentTarget() else {
            environment.notify("No uploader is selected".localized())
            return .failure(UploadFailure.missingUploader)
        }
        let additional = explicitTarget == nil ? additionalTargets(for: primary) : []
        return await upload(fileURL: fileURL, primary: primary, additional: additional, shortener: Defaults[.urlShortener], localFileURL: localFileURL)
    }

    @discardableResult
    static func upload(fileURL: URL, preset: UploadPreset, localFileURL: URL? = nil) async -> Result<UploadOutcome, any Error> {
        guard let primary = target(for: preset.destination) else {
            environment.notify("No uploader is selected".localized())
            return .failure(UploadFailure.missingUploader)
        }
        let additional = additionalTargets(for: primary, destinations: preset.additionalDestinations)
        let shortener = preset.shortener ?? Defaults[.urlShortener]
        return await upload(fileURL: fileURL, primary: primary, additional: additional, shortener: shortener, localFileURL: localFileURL)
    }

    static func upload(
        fileURL: URL, primary: UploadTarget, additional: [UploadTarget], shortener: URLShortenerConfiguration, localFileURL: URL?
    ) async -> Result<UploadOutcome, any Error> {
        let results = await upload(fileURL: fileURL, to: [primary] + additional, localFileURL: localFileURL, shortener: shortener)
        if let url = UploadPlan.urlToDeliver(results) {
            environment.deliver(url)
        }
        return results[0]
    }

    static func upload(
        fileURL: URL, to targets: [UploadTarget], localFileURL: URL?, shortener: URLShortenerConfiguration = .none
    ) async -> [Result<UploadOutcome, any Error>] {
        let progressIndicator: UploadManager? = environment.showsProgress ? UploadManager.shared : nil
        progressIndicator?.begin()
        var results: [Result<UploadOutcome, any Error>] = []
        defer {
            progressIndicator?.uploadCompleted(succeeded: UploadPlan.hasSuccess(results))
        }
        let count = Double(targets.count)
        for (index, target) in targets.enumerated() {
            do {
                var outcome = try await UploadService.upload(fileURL: fileURL, to: target) { fraction in
                    Task { @MainActor in
                        progressIndicator?.updateProgress(fraction: (Double(index) + fraction) / count)
                    }
                }
                Log.upload.info("Uploaded to \(outcome.url.absoluteString, privacy: .public)")
                if !UploadPlan.hasSuccess(results) {
                    outcome.shortURL = await URLShortenerService.shortenedOrNil(outcome.url, with: shortener)
                }
                record(outcome, localFileURL: localFileURL)
                results.append(.success(outcome))
            } catch {
                handleFailure(error, fileURL: fileURL, target: target, localFileURL: localFileURL)
                results.append(.failure(error))
            }
        }
        return results
    }

    static func completeQueued(_ outcome: UploadOutcome, localFileURL: URL?) async {
        var outcome = outcome
        outcome.shortURL = await URLShortenerService.shortenedOrNil(outcome.url, with: Defaults[.urlShortener])
        record(outcome, localFileURL: localFileURL)
        deliver(outcome.deliveredURL)
    }

    static func handleFailure(_ error: any Error, fileURL: URL, target: UploadTarget, localFileURL: URL?) {
        Log.upload.error("Upload to \(target.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        let failure = error as? UploadFailure
        if case let .unsupportedFile(destination, fileExtension) = failure {
            environment.notify(String(format: "%@ can't host .%@ files. Choose a custom uploader instead.".localized(), destination, fileExtension))
        } else if failure?.isRetryable == true, (try? environment.enqueue(fileURL, target, localFileURL?.path, error)) != nil {
            environment.notify("Upload failed, ishare will retry it later".localized())
        } else {
            environment.notify("Upload failed".localized())
        }
    }

    static func deliver(_ url: URL) {
        environment.deliver(url)
    }

    static func record(_ outcome: UploadOutcome, localFileURL: URL?) {
        environment.recordHistory(
            HistoryItem(
                fileUrl: outcome.url.absoluteString,
                deletionUrl: outcome.deletionURL,
                uploaderId: outcome.uploaderID,
                s3Key: outcome.s3Key,
                localPath: localFileURL?.path,
                date: Date(),
                shortUrl: outcome.shortURL?.absoluteString
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
