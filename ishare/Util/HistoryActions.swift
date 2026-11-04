import AppKit
import BezelNotification
import Defaults
import SwiftUI
import ishareCore

@MainActor
enum HistoryActions {
    static func copyURL(_ item: HistoryItem, announce: Bool = true) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.preferredURL?.absoluteString ?? item.fileUrl ?? "", forType: .string)
        if announce {
            BezelNotification.show(messageText: "Copied URL".localized(), icon: ToastIcon)
        }
    }

    static func copy(_ text: String, announcing message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        BezelNotification.show(messageText: message.localized(), icon: ToastIcon)
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

    static func combinableFiles(in items: [HistoryItem]) -> [URL] {
        items.filter(canEdit).compactMap(\.existingLocalFileURL)
    }

    static func canCombine(_ items: [HistoryItem]) -> Bool {
        combinableFiles(in: items).count >= 2
    }

    static func combine(_ items: [HistoryItem]) {
        let files = combinableFiles(in: items)
        guard files.count >= 2 else { return }
        MenuController.shared.perform {
            CombineWindowController.present(urls: files)
        }
    }

    static func liftSubject(_ item: HistoryItem) {
        guard let file = item.existingLocalFileURL else { return }
        MenuController.shared.perform {
            await SubjectLiftFlow.liftAsNewCapture(from: file)
        }
    }

    static func trimBorders(_ item: HistoryItem) {
        guard let file = item.existingLocalFileURL else { return }
        MenuController.shared.perform {
            await BorderTrimmer.trimAsNewCapture(from: file)
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

    static func delete(_ item: HistoryItem) {
        if item.canDeleteFromServer {
            confirmDeleteFromServer(item)
        } else {
            removeFromHistory(item)
        }
    }

    static func undoUpload(_ item: HistoryItem) async {
        await deleteFromServer(item, announcement: "Upload Undone".localized())
    }

    static func copyLinks(_ items: [HistoryItem]) {
        let links = HistorySelection.links(for: items)
        guard !links.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
        BezelNotification.show(messageText: links.count == 1 ? "Copied URL".localized() : String(format: "Copied %d Links".localized(), links.count), icon: ToastIcon)
    }

    static func removeFromHistory(_ items: [HistoryItem]) {
        guard !items.isEmpty else { return }
        removeFromUploadHistory(items)
        BezelNotification.show(messageText: "Removed from History".localized(), icon: ToastIcon)
    }

    static func confirmDeleteFromServer(_ items: [HistoryItem]) {
        let deletable = items.filter(\.canDeleteFromServer)
        guard !deletable.isEmpty else { return }
        guard deletable.count > 1 else {
            confirmDeleteFromServer(deletable[0])
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: "Delete %d Uploads from Server?".localized(), deletable.count)
        var details = "They will be deleted from the server and removed from your history. This can’t be undone.".localized()
        if deletable.count < items.count {
            details += "\n\n" + String(format: "%d selected uploads can’t be deleted from the server and are kept.".localized(), items.count - deletable.count)
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Delete".localized())
        alert.addButton(withTitle: "Cancel".localized())
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await deleteFromServer(deletable)
        }
    }

    static func deleteFromServer(_ items: [HistoryItem]) async {
        var failures: [String] = []
        var deleted = 0
        for item in items {
            do {
                try await UploadCoordinator.delete(item)
                removeFromUploadHistory(item)
                deleted += 1
            } catch {
                Log.upload.error("Deleting from the server failed: \(error.localizedDescription, privacy: .public)")
                failures.append(error.localizedDescription)
            }
        }
        if failures.isEmpty {
            BezelNotification.show(messageText: String(format: "Deleted %d Uploads from Server".localized(), deleted), icon: ToastIcon)
        } else {
            ToastController.showMessage(
                title: String(format: "Couldn’t delete %d uploads".localized(), failures.count),
                message: failures.first ?? "",
                symbol: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    static func deleteFromServer(_ item: HistoryItem, announcement: String = "Deleted from Server".localized()) async {
        do {
            try await UploadCoordinator.delete(item)
            removeFromUploadHistory(item)
            BezelNotification.show(messageText: announcement, icon: ToastIcon)
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

    static func setKeepForever(_ item: HistoryItem, _ keeps: Bool) {
        updateUploadHistoryItem(item) { current in
            var updated = current
            updated.keepForever = keeps ? true : nil
            return updated
        }
        BezelNotification.show(messageText: keeps ? "Kept Forever".localized() : "Auto-Delete Allowed".localized(), icon: ToastIcon)
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
    var shareAnchor: ViewAnchor?
    var showsImageActions = false

    var body: some View {
        if item.isExpired {
            Text("Expired — deleted from server".localized())
        }
        Button("Copy URL".localized()) { HistoryActions.copyURL(item) }
            .disabled(item.fileUrl == nil || item.isExpired)
        if let altText = item.altText, !altText.isEmpty {
            Button("Copy Alt Text".localized()) { HistoryActions.copy(altText, announcing: "Copied Alt Text") }
        }
        if let markdown = item.markdownImage {
            Button("Copy Markdown".localized()) { HistoryActions.copy(markdown, announcing: "Copied Markdown") }
        }
        Button("Open in Browser".localized()) { HistoryActions.open(item) }
            .disabled(item.remoteURL == nil || item.isExpired)
        Button("Show QR Code".localized()) { HistoryActions.showQRCode(item) }
            .disabled(item.preferredURL == nil)
        if HistoryActions.canShareOnLocalNetwork(item) {
            Button("Share on Local Network".localized()) { HistoryActions.shareOnLocalNetwork(item) }
        }
        if HistoryActions.canEdit(item) {
            Button("Open in Editor".localized()) { HistoryActions.edit(item) }
            if showsImageActions {
                Button("Lift Subject".localized()) { HistoryActions.liftSubject(item) }
                Button("Trim Borders".localized()) { HistoryActions.trimBorders(item) }
                Menu("Upscale".localized()) {
                    ForEach(UpscaleFactor.allCases) { factor in
                        Button {
                            HistoryActions.upscale(item, by: factor)
                        } label: {
                            Text(verbatim: "\(factor.rawValue)×")
                        }
                    }
                }
            }
        }
        if showsFinder, item.existingLocalFileURL != nil {
            Button("Show in Finder".localized()) { HistoryActions.revealInFinder(item) }
        }
        if showsImageActions {
            HistoryMoveMenu(items: [item])
        }
        if let shareAnchor {
            Button("Share…".localized()) { SharePicker.show(SharePicker.items(for: item), from: shareAnchor) }
        }
        if let savings = item.savingsDescription {
            Text(savings)
        }
        if let expiresAt = item.expiresAt, !item.isExpired, !item.isKeptForever {
            Text(String(format: "Deleted from the server on %@".localized(), expiresAt.formatted(date: .abbreviated, time: .omitted)))
        }
        Divider()
        if item.canDeleteFromServer {
            Toggle(
                "Keep Forever".localized(),
                isOn: Binding(get: { item.isKeptForever }, set: { HistoryActions.setKeepForever(item, $0) })
            )
        }
        if item.canDeleteFromServer {
            Button("Delete from Server…".localized(), role: .destructive) { HistoryActions.confirmDeleteFromServer(item) }
        }
        Button("Remove from History".localized()) { HistoryActions.removeFromHistory(item) }
    }
}

struct HistoryMoveMenu: View {
    let items: [HistoryItem]

    var body: some View {
        Menu("Move to".localized()) {
            ForEach(HistoryMover.choices()) { choice in
                Button(choice.target.displayName) { HistoryMover.confirmMove(items, to: choice.target) }
            }
        }
        .disabled(items.allSatisfy { $0.isExpired || ($0.existingLocalFileURL == nil && $0.remoteURL == nil) })
    }
}

@MainActor
enum HistoryBulkEdit {
    static func setKeepForever(_ items: [HistoryItem], _ keeps: Bool) {
        update(items) { $0.keepForever = keeps ? true : nil }
        BezelNotification.show(messageText: String(format: (keeps ? "Kept %d Uploads Forever" : "Allowed Auto-Delete for %d Uploads").localized(), items.count), icon: ToastIcon)
    }

    static func setExpiry(_ items: [HistoryItem], days: Int?) {
        let date = BulkRename.expiry(days: days)
        update(items.filter(\.canDeleteFromServer)) { item in
            item.expiresAt = date
            item.keepForever = date == nil ? item.keepForever : nil
        }
    }

    static func rename(_ items: [HistoryItem]) {
        let alert = NSAlert()
        alert.messageText = String(format: "Rename %d Uploads".localized(), items.count)
        alert.informativeText = "Use {{n}} for a number, {{name}} for the file name and {{date}} for today.".localized()
        let field = NSTextField(string: "{{name}}")
        field.frame = CGRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename".localized())
        alert.addButton(withTitle: "Cancel".localized())
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let titles = BulkRename.titles(template: field.stringValue, originals: items.map(\.fileName))
        let byKey = Dictionary(zip(items.map(\.storageKey), titles), uniquingKeysWith: { first, _ in first })
        updateUploadHistory { item in
            guard let title = byKey[item.storageKey] else { return item }
            var updated = item
            updated.title = title
            return updated
        }
    }

    private static func update(_ items: [HistoryItem], _ change: (inout HistoryItem) -> Void) {
        let keys = Set(items.map(\.storageKey))
        updateUploadHistory { item in
            guard keys.contains(item.storageKey) else { return item }
            var updated = item
            change(&updated)
            return updated
        }
    }
}

struct HistoryBulkEditMenu: View {
    let items: [HistoryItem]

    var body: some View {
        Menu(String(format: "Edit %d Uploads".localized(), items.count)) {
            Button("Rename…".localized()) { HistoryBulkEdit.rename(items) }
            Divider()
            Button("Keep Forever".localized()) { HistoryBulkEdit.setKeepForever(items, true) }
            Button("Allow Auto-Delete".localized()) { HistoryBulkEdit.setKeepForever(items, false) }
            Menu("Delete from Server After".localized()) {
                ForEach([1, 7, 30, 90], id: \.self) { days in
                    Button(String(format: "%d Days".localized(), days)) { HistoryBulkEdit.setExpiry(items, days: days) }
                }
                Button("Never".localized()) { HistoryBulkEdit.setExpiry(items, days: nil) }
            }
            .disabled(!items.contains(where: \.canDeleteFromServer))
        }
    }
}
