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
                        .help("Set to default".localized())
                    }
                }
            }
            SettingsTransferSection()
        }
        .formStyle(.grouped)
    }
}
