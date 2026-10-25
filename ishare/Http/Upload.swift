import AppKit
import BezelNotification
import Defaults
import Foundation
import ishareCore

enum UploadType: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case IMGUR, CUSTOM

    var id: Self { self }
}

@MainActor
protocol UploadEnvironment {
    var showsProgress: Bool { get }
    func recordHistory(_ item: HistoryItem)
    func notify(_ message: String)
    func enqueue(_ fileURL: URL, target: UploadTarget, localPath: String?, error: any Error) throws
    func deliver(_ url: URL)
    func copyText(_ text: String)
    func resolveLinkChoice(for target: UploadTarget) async -> LinkChoiceResolution
    var currentHistory: [HistoryItem] { get }
    func resolveDuplicate(of item: HistoryItem, fileURL: URL, target: UploadTarget) async -> DuplicateDecision
    func promote(_ item: HistoryItem)
}

extension UploadEnvironment {
    func copyText(_: String) {}

    var currentHistory: [HistoryItem] { Defaults[.uploadHistory] }

    func resolveDuplicate(of _: HistoryItem, fileURL _: URL, target _: UploadTarget) async -> DuplicateDecision {
        .uploadAgain
    }

    func promote(_: HistoryItem) {}
}

struct LiveUploadEnvironment: UploadEnvironment {
    var showsProgress: Bool { true }

    func recordHistory(_ item: HistoryItem) {
        addToUploadHistory(item)
    }

    func notify(_ message: String) {
        BezelNotification.show(messageText: message, icon: ToastIcon)
    }

    func enqueue(_ fileURL: URL, target: UploadTarget, localPath: String?, error: any Error) throws {
        try UploadQueue.shared.enqueue(fileURL: fileURL, target: target, localPath: localPath, error: error)
    }

    func deliver(_ url: URL) {
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
        if Defaults[.showQRCodeAfterUpload], !url.isFileURL, !LocalNetworkAddress.isPrivateHost(url.host() ?? "") {
            QRCodePanel.show(url)
        }
    }

    func copyText(_ text: String) {
        guard Defaults[.copyURLAfterUpload], !Defaults[.copyImageToClipboard] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func resolveLinkChoice(for target: UploadTarget) async -> LinkChoiceResolution {
        await LinkOptionsResolver.resolve(for: target)
    }

    func resolveDuplicate(of item: HistoryItem, fileURL: URL, target: UploadTarget) async -> DuplicateDecision {
        DuplicatePrompt.ask(existing: item, fileURL: fileURL, uploaderName: target.displayName)
    }

    func promote(_ item: HistoryItem) {
        let key = item.storageKey
        var history = Defaults[.uploadHistory]
        guard let index = history.firstIndex(where: { $0.storageKey == key }), index > 0 else { return }
        history.insert(history.remove(at: index), at: 0)
        Defaults[.uploadHistory] = history
    }
}

struct UploadJob: Sendable {
    var fileURL: URL
    var target: UploadTarget
    var linkChoice: LinkChoice
    var localFileURL: URL?
    var shortener: URLShortenerConfiguration?
    var contentHash: String?
    var origin: UploadOrigin? = nil
}

enum UploadPlan {
    static func additional(_ destinations: [UploadDestination], excluding primary: UploadDestination) -> [UploadDestination] {
        var seen: Set<UploadDestination> = [primary]
        return destinations.filter { seen.insert($0).inserted }
    }

    static func urlToDeliver(_ results: [Result<UploadOutcome, any Error>]) -> URL? {
        results.lazy.compactMap { try? $0.get().deliveredURL }.first
    }

    static func clipboardTextToDeliver(_ results: [Result<UploadOutcome, any Error>]) -> String? {
        guard let outcome = results.lazy.compactMap({ try? $0.get() }).first(where: { $0.deliveredURL != nil }) else { return nil }
        return outcome.shortURL == nil ? outcome.clipboardText : nil
    }

    static func hasSuccess(_ results: [Result<UploadOutcome, any Error>]) -> Bool {
        results.contains { if case .success = $0 { true } else { false } }
    }

    static func hasShareableSuccess(_ results: [Result<UploadOutcome, any Error>]) -> Bool {
        results.contains { (try? $0.get().deliveredURL) != nil }
    }

    static func deliveryActions(copyURL: Bool, copyImage: Bool, openURL: Bool) -> (copy: Bool, open: Bool) {
        (copyURL && !copyImage, openURL)
    }
}

@MainActor
enum UploadCoordinator {
    static var environment: any UploadEnvironment = LiveUploadEnvironment()

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
        case .localNetwork: .localNetwork
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

    static func uploadOnce(fileURL: URL, target: UploadTarget, localFileURL: URL? = nil) async throws -> UploadOutcome {
        let hash = await DuplicateUploads.hash(of: fileURL)
        if let reused = await reuseExistingUpload(hash: hash, fileURL: fileURL, target: target) {
            return reused
        }
        let job = UploadJob(
            fileURL: fileURL, target: target, linkChoice: LinkOptionsResolver.storedChoice(for: target), localFileURL: localFileURL,
            shortener: nil, contentHash: hash
        )
        return try await process(job)
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
            if let text = UploadPlan.clipboardTextToDeliver(results) {
                environment.copyText(text)
            }
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
        let contentHash = await DuplicateUploads.hash(of: fileURL)
        for (index, target) in targets.enumerated() {
            if let reused = await reuseExistingUpload(hash: contentHash, fileURL: fileURL, target: target) {
                results.append(.success(reused))
                continue
            }
            guard case let .use(linkChoice) = await environment.resolveLinkChoice(for: target) else {
                environment.notify("Upload cancelled".localized())
                results.append(.failure(UploadFailure.cancelled))
                continue
            }
            let job = UploadJob(
                fileURL: fileURL, target: target, linkChoice: linkChoice, localFileURL: localFileURL,
                shortener: UploadPlan.hasShareableSuccess(results) ? nil : shortener, contentHash: contentHash
            )
            do {
                let outcome = try await process(job) { fraction in
                    Task { @MainActor in
                        progressIndicator?.updateProgress(fraction: (Double(index) + fraction) / count)
                    }
                }
                results.append(.success(outcome))
            } catch {
                handleFailure(error, fileURL: fileURL, target: target, localFileURL: localFileURL)
                results.append(.failure(error))
            }
        }
        return results
    }

    static func process(_ job: UploadJob, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> UploadOutcome {
        let policy = UploadPreparationPolicy.current(for: job.target, origin: job.origin ?? UploadOrigin.current)
        let prepared = await UploadPreparation.prepare(job.fileURL, policy: policy)
        defer { prepared.discard() }
        var outcome = try await UploadStatistics.recordingUpload(fileURL: prepared.fileURL, to: job.target, linkChoice: job.linkChoice, progress: progress)
        outcome.originalBytes = prepared.originalBytes
        outcome.uploadedBytes = prepared.optimizedBytes
        outcome = LinkRewriting.rewrite(outcome, for: job.target)
        Log.upload.info("Uploaded to \(outcome.url.absoluteString, privacy: .public)")
        if let saved = outcome.savedBytes, let original = outcome.originalBytes {
            Log.upload.info("\(ByteSavings.description(saved: saved, original: original), privacy: .public)")
        }
        if let shortener = job.shortener, outcome.canBeShortened {
            outcome.shortURL = await URLShortenerService.shortenedOrNil(outcome.url, with: shortener)
        }
        record(outcome, target: job.target, localFileURL: job.localFileURL)
        var hash = job.contentHash
        if hash == nil {
            hash = await DuplicateUploads.hash(of: job.fileURL)
        }
        DuplicateUploads.remember(hash: hash, target: job.target, outcome: outcome)
        WebhookDispatcher.uploadCompleted(
            outcome, fileURL: prepared.fileURL, uploaderName: job.target.displayName, savedBytes: outcome.savedBytes,
            waitsForAltText: AltText.isEnabled && MimeType.isImageOrVideo(prepared.fileURL)
        )
        return outcome
    }

    static func reuseExistingUpload(hash: String?, fileURL: URL, target: UploadTarget) async -> UploadOutcome? {
        guard let hash, let existing = DuplicateUploads.existingItem(hash: hash, target: target, history: environment.currentHistory) else { return nil }
        let decision: DuplicateDecision
        if let automatic = DuplicateUploads.policy.automaticDecision {
            decision = automatic
        } else {
            decision = await environment.resolveDuplicate(of: existing, fileURL: fileURL, target: target)
        }
        guard decision == .reuse, let outcome = DuplicateUploads.outcome(reusing: existing) else { return nil }
        Log.upload.info("Reusing the existing link for \(fileURL.lastPathComponent, privacy: .public)")
        environment.promote(existing)
        environment.notify("Already uploaded".localized())
        return outcome
    }

    static func retryQueued(fileURL: URL, item: QueuedUpload) async throws -> UploadOutcome {
        guard let target = target(for: item.destination) else { throw UploadFailure.missingUploader }
        let job = UploadJob(
            fileURL: fileURL, target: target, linkChoice: LinkOptionsResolver.storedChoice(for: target),
            localFileURL: item.localPath.map { URL(fileURLWithPath: $0) }, shortener: Defaults[.urlShortener],
            contentHash: nil, origin: item.isImported == true ? .imported : .capture
        )
        return try await process(job)
    }

    static func completeQueued(_ outcome: UploadOutcome) {
        if let url = outcome.deliveredURL {
            deliver(url)
        }
    }

    static func handleFailure(_ error: any Error, fileURL: URL, target: UploadTarget, localFileURL: URL?) {
        Log.upload.error("Upload to \(target.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        let failure = error as? UploadFailure
        if case let .unsupportedFile(destination, fileExtension) = failure {
            environment.notify(String(format: "%@ can't host .%@ files. Choose a custom uploader instead.".localized(), destination, fileExtension))
        } else if failure?.isRetryable == true, (try? environment.enqueue(fileURL, target: target, localPath: localFileURL?.path, error: error)) != nil {
            environment.notify("Upload failed, ishare will retry it later".localized())
        } else {
            environment.notify("Upload failed".localized())
        }
    }

    static func deliver(_ url: URL) {
        environment.deliver(url)
    }

    static func record(_ outcome: UploadOutcome, target: UploadTarget? = nil, localFileURL: URL?, now: Date = Date()) {
        environment.recordHistory(historyItem(for: outcome, target: target, localFileURL: localFileURL, now: now))
    }

    static func historyItem(for outcome: UploadOutcome, target: UploadTarget?, localFileURL: URL?, now: Date) -> HistoryItem {
        var item = HistoryItem(
            fileUrl: outcome.historyURL,
            deletionUrl: outcome.deletionURL,
            uploaderId: outcome.uploaderID,
            s3Key: outcome.s3Key,
            localPath: localFileURL?.path,
            date: now,
            shortUrl: outcome.shortURL?.absoluteString,
            localIdentifier: outcome.localIdentifier,
            originalSize: outcome.savedBytes == nil ? nil : outcome.originalBytes,
            uploadedSize: outcome.savedBytes == nil ? nil : outcome.uploadedBytes
        )
        if case let .custom(uploader) = target, item.canDeleteFromServer, item.remoteURL != nil {
            item.expiresAt = UploadExpiry.expiryDate(uploadedAt: now, days: uploader.effectiveAutoDeleteDays)
        }
        return item
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
