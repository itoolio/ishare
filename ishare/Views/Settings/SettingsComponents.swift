import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct SettingsPaneRow: View {
    let pane: SettingsPane
    let keyword: String?
    let isSearching: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.title.localized())
                    .fontWeight(isSearching ? .semibold : .regular)
                if let keyword {
                    Text(keyword.localized().trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FolderRow: View {
    let title: String
    let kind: SaveLocation.Kind
    @Default(.capturePath) private var capturePath
    @Default(.recordingPath) private var recordingPath

    private var path: String {
        kind == .captures ? capturePath : recordingPath
    }

    var body: some View {
        LabeledContent(title.localized()) {
            HStack {
                Text(NSString(string: path).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Choose…".localized()) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
                    Task { @MainActor in
                        if await panel.beginAsyncModal() == .OK, let url = panel.url {
                            SaveLocation.choose(url, for: kind)
                        }
                    }
                }
                Button {
                    NSWorkspace.shared.open(SaveLocation.directory(for: kind))
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open in Finder".localized())
            }
        }
    }
}

struct PrefixRow: View {
    let key: Defaults.Key<String>
    @State private var value = ""

    var body: some View {
        LabeledContent("File prefix:".localized()) {
            HStack {
                TextField("", text: Binding(get: { Defaults[key] }, set: { Defaults[key] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button {
                    Defaults[key] = key.defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Set to default".localized())
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent(title.localized()) {
            if granted {
                Label("Allowed".localized(), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…".localized(), action: action)
            }
        }
    }
}
