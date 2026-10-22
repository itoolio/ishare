import AppKit
import BezelNotification
import Defaults
import SwiftUI

@MainActor
enum HistoryActions {
    static func copyURL(_ item: HistoryItem, announce: Bool = true) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.fileUrl ?? "", forType: .string)
        if announce {
            BezelNotification.show(messageText: "Copied URL".localized(), icon: ToastIcon)
        }
    }

    static func open(_ item: HistoryItem) {
        if let url = item.remoteURL {
            NSWorkspace.shared.open(url)
        } else if let file = item.existingLocalFileURL {
            NSWorkspace.shared.open(file)
        }
    }

    static func canEdit(_ item: HistoryItem) -> Bool {
        item.existingLocalFileURL != nil && item.kind == .image && item.fileExtension.lowercased() != "gif"
    }

    static func edit(_ item: HistoryItem) {
        guard let file = item.existingLocalFileURL else { return }
        MenuController.shared.perform {
            await ImageEditor.editAsNewCapture(sourceURL: file)
        }
    }

    static func revealInFinder(_ item: HistoryItem) {
        guard let file = item.existingLocalFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    static func removeFromHistory(_ item: HistoryItem) {
        removeFromUploadHistory(item)
        BezelNotification.show(messageText: "Removed from History".localized(), icon: ToastIcon)
    }

    static func confirmDeleteFromServer(_ item: HistoryItem) {
        guard item.canDeleteFromServer else { return }
        guard !MenuController.shared.isPresented else {
            MenuController.shared.perform { confirmDeleteFromServer(item) }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete from Server?".localized()
        alert.informativeText = String(format: "“%@” will be deleted from the server and removed from your history. This can’t be undone.".localized(), item.fileName)
        alert.addButton(withTitle: "Delete".localized())
        alert.addButton(withTitle: "Cancel".localized())
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await deleteFromServer(item)
        }
    }

    static func deleteFromServer(_ item: HistoryItem) async {
        do {
            try await UploadCoordinator.delete(item)
            removeFromUploadHistory(item)
            BezelNotification.show(messageText: "Deleted from Server".localized(), icon: ToastIcon)
        } catch {
            Log.upload.error("Deleting from the server failed: \(error.localizedDescription, privacy: .public)")
            ToastController.showMessage(
                title: "Couldn’t delete from server".localized(),
                message: error.localizedDescription,
                symbol: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    static func confirmClearHistory() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear History?".localized()
        alert.informativeText = "All uploads are removed from your history. Files stay on the server.".localized()
        alert.addButton(withTitle: "Clear History".localized())
        alert.addButton(withTitle: "Cancel".localized())
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        clearUploadHistory()
        ThumbnailCache.shared.removeAll()
        return true
    }
}

struct HistoryItemMenuItems: View {
    let item: HistoryItem
    var showsFinder = true

    var body: some View {
        Button("Copy URL".localized()) { HistoryActions.copyURL(item) }
            .disabled(item.fileUrl == nil)
        Button("Open in Browser".localized()) { HistoryActions.open(item) }
            .disabled(item.remoteURL == nil)
        if HistoryActions.canEdit(item) {
            Button("Open in Editor".localized()) { HistoryActions.edit(item) }
        }
        if showsFinder, item.existingLocalFileURL != nil {
            Button("Show in Finder".localized()) { HistoryActions.revealInFinder(item) }
        }
        Divider()
        if item.canDeleteFromServer {
            Button("Delete from Server…".localized(), role: .destructive) { HistoryActions.confirmDeleteFromServer(item) }
        }
        Button("Remove from History".localized()) { HistoryActions.removeFromHistory(item) }
    }
}
