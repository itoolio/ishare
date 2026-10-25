import AppKit
import Defaults
import Foundation
import ishareCore

@MainActor
enum DuplicateUploads {
    @TaskLocal static var policyOverride: DuplicatePolicy?

    static var load: () -> DuplicateIndex = { Defaults[.uploadHashIndex] }
    static var save: (DuplicateIndex) -> Void = { Defaults[.uploadHashIndex] = $0 }

    static var policy: DuplicatePolicy {
        policyOverride ?? Defaults[.duplicateUploadPolicy]
    }

    static func isTracked(_ target: UploadTarget) -> Bool {
        switch target {
        case .imgur: true
        case let .custom(uploader): uploader.kind != .photos
        case .localNetwork: false
        }
    }

    nonisolated static func hash(of fileURL: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            return try? ContentHash.sha256(of: fileURL)
        }.value
    }

    static func existingItem(hash: String, target: UploadTarget, history: [HistoryItem]) -> HistoryItem? {
        guard isTracked(target) else { return nil }
        let live = Dictionary(history.filter(\.hasLiveLink).compactMap { item in item.fileUrl.map { ($0, item) } }, uniquingKeysWith: { first, _ in first })
        guard let link = load().existingLink(hash: hash, destination: target.statisticsKey, isLive: { live[$0] != nil }) else { return nil }
        return live[link]
    }

    static func remember(hash: String?, target: UploadTarget, outcome: UploadOutcome, now: Date = Date()) {
        guard let hash, isTracked(target), !outcome.isReused, let link = outcome.historyURL else { return }
        var index = load()
        index.remember(hash: hash, destination: target.statisticsKey, link: link, date: now)
        save(index)
    }

    static func forget(_ items: [HistoryItem]) {
        let links = Set(items.compactMap(\.fileUrl))
        guard !links.isEmpty else { return }
        var index = load()
        let before = index
        for link in links {
            index.forget(link: link)
        }
        if index != before {
            save(index)
        }
    }

    static func outcome(reusing item: HistoryItem) -> UploadOutcome? {
        guard let url = item.remoteURL else { return nil }
        var outcome = UploadOutcome(url: url, deletionURL: item.deletionUrl, uploaderID: item.uploaderId, s3Key: item.s3Key)
        outcome.shortURL = item.shortURL
        outcome.localIdentifier = item.localIdentifier
        outcome.isReused = true
        return outcome
    }
}

@MainActor
enum DuplicatePrompt {
    static func ask(existing item: HistoryItem, fileURL: URL, uploaderName: String) -> DuplicateDecision {
        guard !RuntimeEnvironment.isRunningTests else { return .uploadAgain }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Already Uploaded".localized()
        alert.informativeText = String(
            format: "“%@” was already uploaded to %@. Use the existing link or upload it again?".localized(), fileURL.lastPathComponent, uploaderName
        )
        if let link = item.preferredURL?.absoluteString {
            alert.informativeText += "\n\n" + link
        }
        alert.addButton(withTitle: "Use Existing Link".localized())
        alert.addButton(withTitle: "Upload Again".localized())
        return alert.runModal() == .alertFirstButtonReturn ? .reuse : .uploadAgain
    }
}
