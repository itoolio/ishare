import Defaults
import KeyboardShortcuts
import SwiftUI

struct CaptureShelfSettingsSection: View {
    @Default(.captureShelfMode) private var mode

    var body: some View {
        Section {
            Picker(Self.shelf.title.localized(), selection: $mode) {
                ForEach(CaptureShelfMode.allCases) { mode in
                    Text(mode.title.localized()).tag(mode)
                }
            }
            .accessibilityIdentifier("settings.shelf.mode")
            .settingsEntry(Self.shelf)
            if mode != .off {
                KeyboardShortcuts.Recorder("Show or Hide Capture Shelf:".localized(), name: .toggleCaptureShelf)
            }
        } footer: {
            Text(
                "The shelf keeps your recent captures and recordings at the edge of the screen. Drag them into any app, or drop files onto it to collect them."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .off {
                CaptureShelf.shared.hide()
                CaptureShelf.shared.clear()
            }
        }
    }
}

extension CaptureShelfSettingsSection: SettingsSearchable {
    static let shelf = SettingsSearchEntry(
        "Capture Shelf", pane: .capture,
        keywords: ["Shelf", "Tray", "Recent captures", "Drag and drop", "Show after capture", "Only from the shortcut and menu"],
        anchor: SettingsAnchor.captureShelf
    )
    static let searchEntries = [shelf]
}

extension SettingsAnchor {
    static let captureShelf = "capture.shelf"
}
