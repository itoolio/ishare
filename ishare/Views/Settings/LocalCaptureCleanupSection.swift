import Defaults
import SwiftUI

struct LocalCaptureCleanupSection: View {
    @Default(.localCaptureRetention) private var retention
    @Default(.keepUploadedLocalCaptures) private var keepUploaded

    var body: some View {
        Section {
            Picker("Delete local captures older than".localized(), selection: $retention) {
                ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings.cleanup.retention")
            Toggle("Keep files that were uploaded".localized(), isOn: $keepUploaded)
                .disabled(retention == .never)
                .accessibilityIdentifier("settings.cleanup.keepUploaded")
        } header: {
            Text("Local Captures".localized())
        } footer: {
            Text("Only screenshots and recordings that ishare named in its save folders are moved to the Trash, once at launch and then daily.".localized())
                .foregroundStyle(.secondary)
        }
    }
}
