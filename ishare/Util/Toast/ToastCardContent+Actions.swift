import SwiftUI

extension ToastCardContent {
    var actions: some View {
        HStack(spacing: 6) {
            ToastActionButton(symbol: "doc.on.doc", title: "Copy", identifier: "toast.copy") { copy() }
                .contextMenu {
                    if let item = model.historyItem {
                        Button("Copy URL".localized()) { HistoryActions.copyURL(item) }
                        if let altText = item.altText, !altText.isEmpty {
                            Button("Copy Alt Text".localized()) { HistoryActions.copy(altText, announcing: "Copied Alt Text") }
                        }
                        if let markdown = item.markdownImage {
                            Button("Copy Markdown".localized()) { HistoryActions.copy(markdown, announcing: "Copied Markdown") }
                        }
                        Button("Show QR Code".localized()) { QRCodePanel.show(for: item) }
                            .disabled(item.preferredURL == nil)
                    }
                    if let url = model.fileURL, fileExists {
                        Button("Share on Local Network".localized()) {
                            Task { @MainActor in await LocalShareManager.shared.shareAndPresent(fileURL: url) }
                        }
                    }
                }
            ToastActionButton(symbol: "arrow.up.forward.app", title: "Open", iconOnly: model.canUndo, identifier: "toast.open") { open() }
                .disabled(model.historyItem == nil && !fileExists)
            if model.isImage {
                ToastActionButton(symbol: "pencil.tip.crop.circle", title: "Edit", iconOnly: model.canUndo, identifier: "toast.edit") { model.onEdit() }
            }
            ShareActionButton(items: shareItems, iconOnly: true, identifier: "toast.share")
            if hasDeleteOptions {
                deleteMenu
            }
            if model.canUndo, let item = model.historyItem {
                ToastActionButton(symbol: "arrow.uturn.backward", title: "Undo", identifier: "toast.undo") {
                    model.onDismiss()
                    Task { @MainActor in
                        await HistoryActions.undoUpload(item)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func shareItems() -> [Any] {
        if let url = model.fileURL, FileManager.default.fileExists(atPath: url.path) {
            return [url]
        }
        return model.historyItem.map(SharePicker.items(for:)) ?? []
    }

    private var deleteMenu: some View {
        Menu {
            if let item = model.historyItem {
                if item.canDeleteFromServer {
                    Button("Delete from Server…".localized(), role: .destructive) {
                        model.onDismiss()
                        HistoryActions.confirmDeleteFromServer(item)
                    }
                }
                Button("Remove from History".localized()) {
                    HistoryActions.removeFromHistory(item)
                    model.historyItem = nil
                    model.uploadState = .none
                }
            }
            if canTrashFile, let url = model.fileURL {
                Button("Move to Trash".localized(), role: .destructive) {
                    NSWorkspace.shared.recycle([url])
                    model.onDismiss()
                }
            }
        } label: {
            ToastActionLabel(symbol: "trash", title: "Delete", iconOnly: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Delete".localized())
        .accessibilityIdentifier("toast.delete")
    }

    private var fileExists: Bool {
        model.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private var canTrashFile: Bool {
        saveToDisk && fileExists
    }

    private var hasDeleteOptions: Bool {
        model.historyItem != nil || canTrashFile
    }

    private func copy() {
        if let item = model.historyItem {
            HistoryActions.copyURL(item)
        } else if let url = model.fileURL {
            PostCapture.copyToClipboard(url, kind: model.kind)
        }
    }

    private func open() {
        if let item = model.historyItem {
            HistoryActions.open(item)
        } else if let url = model.fileURL {
            NSWorkspace.shared.open(url)
        }
    }
}
