import AppKit
import BezelNotification
import Defaults
import Foundation
import ishareCore

enum HistoryMove {
    static func replacing(_ old: HistoryItem, withUploadAt newURL: String?, in history: [HistoryItem]) -> [HistoryItem]? {
        guard let newURL, let newIndex = history.firstIndex(where: { $0.fileUrl == newURL && $0.storageKey != old.storageKey }),
            let oldIndex = history.firstIndex(where: { $0.storageKey == old.storageKey })
        else { return nil }
        var merged = history[newIndex]
        merged.date = old.date ?? merged.date
        merged.title = merged.title ?? old.title
        merged.altText = merged.altText ?? old.altText
        merged.localPath = merged.localPath ?? old.localPath
        merged.keepForever = old.keepForever
        var updated = history
        updated[oldIndex] = merged
        updated.remove(at: newIndex)
        return updated
    }

    static func movable(_ items: [HistoryItem], to target: UploadDestination) -> [HistoryItem] {
        items.filter { item in
            guard item.existingLocalFileURL != nil || item.remoteURL != nil, !item.isExpired else { return false }
            return item.uploaderId.map { UploadDestination.custom($0) != target } ?? true
        }
    }
}

@MainActor
enum HistoryMover {
    struct Choice: Identifiable {
        let target: UploadTarget
        var id: String { target.displayName }
    }

    static func choices() -> [Choice] {
        [Choice(target: .imgur(clientID: Defaults[.imgurClientId]))] + CustomUploader.allCases.map { Choice(target: .custom($0)) }
    }

    static func confirmMove(_ items: [HistoryItem], to target: UploadTarget) {
        let movable = HistoryMove.movable(items, to: target.destination)
        guard !movable.isEmpty else {
            BezelNotification.show(messageText: "Nothing to move".localized(), icon: ToastIcon)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(format: "Move %d uploads to %@?".localized(), movable.count, target.displayName)
        alert.informativeText =
            "ishare uploads each file again and replaces its link in your history. Links you already shared keep pointing to the old host unless you delete them there.".localized()
        let deletesOld = NSButton(checkboxWithTitle: "Delete them from the old host afterwards".localized(), target: nil, action: nil)
        deletesOld.state = .off
        deletesOld.isEnabled = movable.contains(where: \.canDeleteFromServer)
        alert.accessoryView = deletesOld
        alert.addButton(withTitle: "Move".localized())
        alert.addButton(withTitle: "Cancel".localized())
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deletes = deletesOld.state == .on
        Task { await move(movable, to: target, deletingOld: deletes) }
    }

    static func move(_ items: [HistoryItem], to target: UploadTarget, deletingOld: Bool) async {
        var moved = 0
        var failures: [String] = []
        await ProcessingHUDPresenter.run(String(format: "Moving to %@".localized(), target.displayName)) { progress in
            for (index, item) in items.enumerated() {
                do {
                    try await move(item, to: target, deletingOld: deletingOld)
                    moved += 1
                } catch {
                    Log.upload.error("Moving \(item.fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    failures.append(error.localizedDescription)
                }
                progress(Double(index + 1) / Double(items.count))
            }
        }
        if failures.isEmpty {
            BezelNotification.show(messageText: String(format: "Moved %d uploads".localized(), moved), icon: ToastIcon)
        } else {
            ToastController.showMessage(
                title: String(format: "Couldn’t move %d uploads".localized(), failures.count), message: failures.first ?? "",
                symbol: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private static func move(_ item: HistoryItem, to target: UploadTarget, deletingOld: Bool) async throws {
        let (file, isTemporary) = try await sourceFile(for: item)
        defer {
            if isTemporary { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        }
        let outcome = try await UploadCoordinator.uploadOnce(fileURL: file, target: target, localFileURL: item.existingLocalFileURL)
        if let updated = HistoryMove.replacing(item, withUploadAt: outcome.historyURL, in: Defaults[.uploadHistory]) {
            Defaults[.uploadHistory] = updated
        }
        if deletingOld, item.canDeleteFromServer {
            try? await UploadCoordinator.delete(item)
        }
    }

    private static func sourceFile(for item: HistoryItem) async throws -> (URL, Bool) {
        if let local = item.existingLocalFileURL {
            return (local, false)
        }
        guard let remote = item.remoteURL else { throw UploadFailure.missingUploader }
        let (downloaded, _) = try await URLSession.shared.download(from: remote)
        let folder = FileManager.default.temporaryDirectory.appending(path: "ishare-move-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = remote.lastPathComponent.isEmpty ? item.fileName : remote.lastPathComponent
        let destination = folder.appending(path: name)
        try FileManager.default.moveItem(at: downloaded, to: destination)
        return (destination, true)
    }
}
