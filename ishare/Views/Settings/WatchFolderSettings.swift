import Defaults
import SwiftUI

struct WatchFolderSettings: View {
    @Default(.watchFolderEnabled) var watchFolderEnabled
    @Default(.watchFolderPath) var watchFolderPath
    @Default(.watchFolderFilter) var watchFolderFilter

    var body: some View {
        Section {
            Toggle("Upload new files from a folder".localized(), isOn: $watchFolderEnabled)
                .disabled(watchFolderPath.isEmpty)
            LabeledContent("Folder".localized()) {
                HStack {
                    Text(watchFolderPath.isEmpty ? "None".localized() : NSString(string: watchFolderPath).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…".localized(), action: choose)
                }
            }
            Picker("File types".localized(), selection: $watchFolderFilter) {
                ForEach(WatchFolderFilter.allCases) { filter in
                    Text(filter.title.localized()).tag(filter)
                }
            }
        } header: {
            Text("Watch Folder".localized())
        } footer: {
            Text("Files that appear in this folder are uploaded once they finish writing. Existing files are left alone.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !watchFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: watchFolderPath, isDirectory: true)
        }
        Task { @MainActor in
            guard await panel.beginAsyncModal() == .OK, let url = panel.url else { return }
            WatchFolderService.choose(url)
            watchFolderEnabled = true
        }
    }
}
