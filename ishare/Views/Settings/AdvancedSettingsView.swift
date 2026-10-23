import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct AdvancedSettingsView: View {
    @Default(.imgurClientId) var imgurClientId

    var body: some View {
        Form {
            Section {
                Text("Warning! Only modify these settings if you know what you're doing!".localized())
                    .foregroundStyle(.secondary)
            }
            Section("Imgur".localized()) {
                LabeledContent("Imgur Client ID:".localized()) {
                    HStack {
                        TextField("", text: $imgurClientId)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                        Button {
                            imgurClientId = Defaults.Keys.imgurClientId.defaultValue
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .helpAndAccessibilityLabel("Set to default".localized())
                    }
                }
            }
            SharingSettingsSection()
            CommandLineToolSection()
            LocalCaptureCleanupSection()
            DiagnosticsSection()
            SettingsTransferSection()
        }
        .formStyle(.grouped)
    }
}

extension AdvancedSettingsView: SettingsSearchable {
    static var searchEntries: [SettingsSearchEntry] {
        baseSearchEntries + SharingSettingsSection.searchEntries + CommandLineToolSection.searchEntries
    }

    static let baseSearchEntries: [SettingsSearchEntry] = [
        SettingsSearchEntry("Backup", pane: .advanced, keywords: [
            "Export Settings", "Import Settings", "Include upload history", "Include S3 secret access keys",
        ]),
        SettingsSearchEntry("Advanced", pane: .advanced, keywords: [
            "Imgur Client ID", "Client ID",
        ]),
    ]
}
