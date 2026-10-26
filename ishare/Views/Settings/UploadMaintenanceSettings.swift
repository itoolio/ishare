import Defaults
import ishareCore
import SwiftUI

struct UploadMaintenanceSettings: View {
    @Default(.duplicateUploadPolicy) var duplicateUploadPolicy
    @Default(.keepsExpiredUploadsInHistory) var keepsExpiredUploadsInHistory
    @Default(.uploaderHealthCheckFrequency) var uploaderHealthCheckFrequency
    @Default(.uploaderHealthLastCheck) var uploaderHealthLastCheck
    @Default(.uploaderHealthRecords) var uploaderHealthRecords
    @State private var isTesting = false
    @State private var isDeleting = false
    @State private var lastOutcome: String?

    var body: some View {
        Section {
            Picker("When a file was already uploaded".localized(), selection: $duplicateUploadPolicy) {
                ForEach(DuplicatePolicy.allCases) { policy in
                    Text(policy.titleKey.localized()).tag(policy)
                }
            }
            .settingsEntry(Self.duplicates)
            Text(
                "ishare remembers a fingerprint of each file it uploads on this Mac. When you upload the same file to the same uploader again and its link is still in your history, ishare can copy the existing link instead."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Duplicates".localized())
        }

        Section {
            Toggle("Keep expired uploads in history".localized(), isOn: $keepsExpiredUploadsInHistory)
                .settingsEntry(Self.autoDelete)
            Text(
                "Choose when uploads are deleted in each uploader's settings. Expired uploads stay in your history marked “Expired — deleted from server” unless you turn this off."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button("Delete Expired Uploads Now".localized()) {
                isDeleting = true
                Task { @MainActor in
                    await UploadExpiryService.runNow()
                    isDeleting = false
                }
            }
            .disabled(isDeleting)
        } header: {
            Text("Auto-Delete".localized())
        }

        Section {
            Picker("Check the default uploader".localized(), selection: $uploaderHealthCheckFrequency) {
                ForEach(HealthCheckFrequency.allCases) { frequency in
                    Text(frequency.titleKey.localized()).tag(frequency)
                }
            }
            .settingsEntry(Self.healthCheck)
            if let status = lastCheckDescription {
                LabeledContent("Last check".localized()) {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack {
                Button("Test Now".localized()) {
                    isTesting = true
                    Task { @MainActor in
                        lastOutcome = Self.describe(await UploaderHealthCheck.run(forced: true))
                        isTesting = false
                    }
                }
                .disabled(isTesting)
                if isTesting {
                    ProgressView().controlSize(.small)
                } else if let lastOutcome {
                    Text(lastOutcome)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(
                "ishare uploads a 1×1 pixel image and deletes it again, or only contacts the server when the uploader can't delete files. Checks are skipped on battery below 20% and on Low Data Mode or metered networks."
                    .localized()
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Uploader Health Check".localized())
        }
    }

    private var lastCheckDescription: String? {
        guard let target = UploadCoordinator.currentTarget(), let record = uploaderHealthRecords[UploaderHealthCheck.key(for: target)] else {
            return uploaderHealthLastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) }
        }
        return UploaderHealthBadge.description(record)
    }

    static func describe(_ outcome: HealthCheckOutcome) -> String {
        switch outcome {
        case let .checked(record):
            record.succeeded ? "The uploader works".localized() : UploaderHealthCheck.failureMessage(record)
        case .skipped(.lowBattery):
            "Skipped because the battery is low".localized()
        case .skipped(.constrainedNetwork), .skipped(.expensiveNetwork):
            "Skipped on a metered or Low Data Mode network".localized()
        case .skipped(.noUploader):
            "No uploader is selected".localized()
        case .skipped(.unsupportedUploader):
            "This uploader can't be checked".localized()
        case .skipped:
            "Skipped".localized()
        }
    }
}

extension UploadMaintenanceSettings {
    static let duplicates = SettingsSearchEntry(
        "When a file was already uploaded", pane: .uploaders,
        keywords: ["Duplicate", "Reuse", "Existing link", "Already uploaded", "Hash", "SHA-256"], anchor: "uploaders.duplicates"
    )
    static let autoDelete = SettingsSearchEntry(
        "Keep expired uploads in history", pane: .uploaders,
        keywords: ["Auto-Delete", "Expire", "Expired", "Delete after", "Retention", "Keep Forever"], anchor: "uploaders.autoDelete"
    )
    static let healthCheck = SettingsSearchEntry(
        "Check the default uploader", pane: .uploaders,
        keywords: ["Health check", "Test", "Monitor", "Broken uploader", "Status"], anchor: "uploaders.healthCheck"
    )
}

struct UploaderHealthBadge: View {
    let record: HealthCheckRecord

    var body: some View {
        Image(systemName: record.succeeded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(record.succeeded ? Color.green : Color.orange)
            .helpAndAccessibilityLabel(Self.description(record))
    }

    static func description(_ record: HealthCheckRecord) -> String {
        let date = record.date.formatted(date: .abbreviated, time: .shortened)
        guard !record.succeeded else { return String(format: "Working, checked %@".localized(), date) }
        return String(format: "Not working, checked %@: %@".localized(), date, record.message ?? "Unknown error".localized())
    }
}
