import AppKit
import Defaults
import SwiftUI

struct SharingSettingsSection: View {
    @Default(.showQRCodeAfterUpload) private var showQRCodeAfterUpload
    @Default(.localShareExpiry) private var localShareExpiry
    @Default(.localShareMaxDownloads) private var localShareMaxDownloads

    var body: some View {
        Section {
            Toggle("Show QR code after upload".localized(), isOn: $showQRCodeAfterUpload)
                .accessibilityIdentifier("settings.sharing.qrAfterUpload")
                .settingsEntry(Self.sharing)
            Picker("Local network links expire after".localized(), selection: $localShareExpiry) {
                ForEach(LocalShareExpiry.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings.sharing.expiry")
            .settingsEntry(Self.localNetwork)
            Picker("Maximum downloads".localized(), selection: $localShareMaxDownloads) {
                Text("Unlimited".localized()).tag(Int?.none)
                ForEach(LocalShareManager.maxDownloadChoices.filter { $0 > 0 }, id: \.self) { count in
                    Text(String(count)).tag(Int?.some(count))
                }
            }
            .accessibilityIdentifier("settings.sharing.maxDownloads")
        } header: {
            Text("Sharing".localized())
        } footer: {
            Text("Share on Local Network serves a file from this Mac at a temporary link that only devices on the same network can open.".localized())
                .foregroundStyle(.secondary)
        }
    }
}

extension SharingSettingsSection: SettingsSearchable {
    static let sharing = SettingsSearchEntry("Sharing", pane: .advanced, keywords: ["QR code", "Show QR code after upload", "Scan"], anchor: "advanced.sharing")
    static let localNetwork = SettingsSearchEntry(
        "Local network links expire after", pane: .advanced,
        keywords: ["Local Network", "Share on Local Network", "LAN", "Wi-Fi", "Maximum downloads", "Expire"], anchor: "advanced.localNetwork"
    )
    static let searchEntries = [sharing, localNetwork]
}

struct CommandLineToolSection: View {
    @State private var state = CommandLineToolInstaller.state()
    @State private var isInstalling = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if CommandLineToolInstaller.canInstallDirectly {
                LabeledContent(statusText) {
                    Button("Install Command-Line Tool…".localized()) { install() }
                        .disabled(isInstalling || state == .installed || state == .missingTool)
                        .accessibilityIdentifier("settings.cli.install")
                }
                .settingsEntry(Self.commandLine)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Run this in Terminal to install the command-line tool:".localized())
                    Text(CommandLineToolInstaller.shellCommand())
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy Command".localized()) {
                        HistoryActions.copy(CommandLineToolInstaller.shellCommand(), announcing: "Copied Command")
                    }
                    .accessibilityIdentifier("settings.cli.copy")
                }
                .settingsEntry(Self.commandLine)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Command-Line Tool".localized())
        } footer: {
            Text("Use “ishare upload”, “ishare capture region” and more from Terminal, scripts and launchers like Raycast.".localized())
                .foregroundStyle(.secondary)
        }
        .onAppear { state = CommandLineToolInstaller.state() }
    }

    private var statusText: String {
        switch state {
        case .missingTool: "The command-line tool is missing from the app bundle.".localized()
        case .notInstalled: "Not installed".localized()
        case .installed: String(format: "Installed at %@".localized(), CommandLineToolInstaller.linkPath)
        case let .linkedElsewhere(path): String(format: "%@ points to another app".localized(), path)
        }
    }

    private func install() {
        isInstalling = true
        errorMessage = nil
        Task { @MainActor in
            let result = await Task.detached { () -> Result<Void, CommandLineToolError> in
                do {
                    try CommandLineToolInstaller.install()
                    return .success(())
                } catch let error as CommandLineToolError {
                    return .failure(error)
                } catch {
                    return .failure(.failed(error.localizedDescription))
                }
            }.value
            isInstalling = false
            if case let .failure(error) = result, error != .cancelled {
                errorMessage = error.localizedDescription
            }
            state = CommandLineToolInstaller.state()
        }
    }
}

extension CommandLineToolSection: SettingsSearchable {
    static let commandLine = SettingsSearchEntry(
        "Command-Line Tool", pane: .advanced,
        keywords: ["Install command-line tool", "CLI", "Terminal", "Raycast", "Shell", "Script", "URL scheme"], anchor: "advanced.commandLine"
    )
    static let searchEntries = [commandLine]
}

struct HistorySyncToggle: View {
    @Default(.historySyncEnabled) private var historySyncEnabled

    var body: some View {
        if HistorySync.isAvailable {
            Toggle("Sync history via iCloud".localized(), isOn: $historySyncEnabled)
                .accessibilityIdentifier("settings.history.sync")
                .settingsEntry(Self.historySync)
            Text("Links, titles, alt text and deletion links of your latest 200 uploads are kept in sync between your Macs. Files stay on each Mac.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension HistorySyncToggle: SettingsSearchable {
    static let historySync = SettingsSearchEntry(
        "Sync history via iCloud", pane: .general, keywords: ["iCloud", "Sync", "Other Macs", "History"], anchor: "general.historySync"
    )
    static var searchEntries: [SettingsSearchEntry] {
        HistorySync.isAvailable ? [historySync] : []
    }
}
