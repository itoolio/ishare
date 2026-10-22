import AppKit
import BezelNotification
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var ishareSettings: UTType {
        UTType(exportedAs: "dev.adrian.ishare.settings", conformingTo: .json)
    }
}

@MainActor
enum SettingsTransferFlow {
    static func export(includeHistory: Bool, includeSecrets: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.ishareSettings]
        panel.nameFieldStringValue = "ishare.\(SettingsArchive.fileExtension)"
        Task { @MainActor in
            guard await panel.beginAsyncModal() == .OK, let url = panel.url else { return }
            do {
                let archive = SettingsTransfer.makeArchive(includeHistory: includeHistory, includeSecrets: includeSecrets)
                try SettingsTransfer.encode(archive).write(to: url, options: .atomic)
                BezelNotification.show(messageText: "Settings exported".localized(), icon: ToastIcon)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.ishareSettings, .json]
        Task { @MainActor in
            guard await panel.beginAsyncModal() == .OK, let url = panel.url else { return }
            importArchive(from: url)
        }
    }

    static func importArchive(from url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let archive: SettingsArchive
        do {
            archive = try SettingsTransfer.decode(Data(contentsOf: url))
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Import Error".localized()
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import Settings".localized()
        alert.informativeText = summaryText(archive.summary)
        alert.addButton(withTitle: "Import".localized())
        alert.addButton(withTitle: "Cancel".localized())
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SettingsTransfer.apply(archive)
        BezelNotification.show(messageText: "Settings imported".localized(), icon: ToastIcon)
    }

    static func summaryText(_ summary: SettingsArchive.Summary) -> String {
        var lines = [
            String(format: "Preferences: %d".localized(), summary.preferences),
            String(format: "Uploaders: %d".localized(), summary.uploaders),
            String(format: "Keyboard shortcuts: %d".localized(), summary.shortcuts),
        ]
        if let history = summary.history {
            lines.append(String(format: "History items: %d".localized(), history))
        }
        if summary.includesSecrets {
            lines.append("Includes S3 secret access keys".localized())
        }
        lines.append("Matching settings and uploaders on this Mac are replaced.".localized())
        return lines.joined(separator: "\n")
    }
}

struct SettingsTransferSection: View {
    @State private var includeHistory = false
    @State private var includeSecrets = false

    var body: some View {
        Section("Backup".localized()) {
            Toggle("Include upload history".localized(), isOn: $includeHistory)
            Toggle("Include S3 secret access keys".localized(), isOn: $includeSecrets)
            if includeSecrets {
                Text("Anyone with the exported file can use these keys.".localized())
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Export Settings…".localized()) {
                    SettingsTransferFlow.export(includeHistory: includeHistory, includeSecrets: includeSecrets)
                }
                Button("Import Settings…".localized()) {
                    SettingsTransferFlow.chooseAndImport()
                }
            }
        }
    }
}
