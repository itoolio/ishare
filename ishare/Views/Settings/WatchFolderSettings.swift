import Defaults
import ishareCore
import SwiftUI

struct WatchFolderSettings: View {
    @Default(.watchedFolders) var folders
    @Default(.watchFolderUndoLog) var undoLog

    var body: some View {
        Section {
            ForEach($folders) { $folder in
                WatchedFolderRow(folder: $folder) {
                    folders.removeAll { $0.id == folder.id }
                }
            }
            HStack {
                Button("Add Folder…".localized(), action: choose)
                    .accessibilityIdentifier("settings.watchFolder.add")
                Spacer()
                Button("Undo Last Steps".localized()) { WatchFolderUndo.undoLast() }
                    .disabled(undoLog.last == nil)
                    .help(undoLog.last.map { String(format: "Moves %@ back where it was".localized(), $0.fileName) } ?? "")
            }
        } header: {
            Text("Watch Folders".localized())
        } footer: {
            Text(
                "Files that appear in these folders run through each folder’s steps once they finish writing. Existing files are left alone. Undo Last Steps moves the last renamed, moved or trashed file back."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        ForEach($folders) { $folder in
            if folder.isEnabled {
                WatchFolderChainSettings(actions: $folder.actions, title: String(format: "Steps for %@".localized(), folder.displayName))
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        Task { @MainActor in
            guard await panel.beginAsyncModal() == .OK, let url = panel.url else { return }
            WatchFolderService.add(url)
        }
    }
}

private struct WatchedFolderRow: View {
    @Binding var folder: WatchedFolder
    let remove: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: $folder.isEnabled) {
                Text(NSString(string: folder.path).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Picker("File types".localized(), selection: $folder.filter) {
                ForEach(WatchFolderFilter.allCases) { filter in
                    Text(filter.title.localized()).tag(filter)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove Folder".localized())
        }
    }
}
