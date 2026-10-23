import SwiftUI
import UniformTypeIdentifiers

struct UploadStatisticsSettings: View {
    @ObservedObject var store: UploadStatisticsStore = .shared
    @State private var window: UploadStatisticsWindow = .last30Days
    @State private var confirmReset = false

    var body: some View {
        Section {
            Picker("Period".localized(), selection: $window) {
                ForEach(UploadStatisticsWindow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if store.database.ledgers.isEmpty {
                Text("No uploads have been recorded yet".localized())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.database.sortedKeys, id: \.self) { key in
                    if let ledger = store.database.ledgers[key] {
                        UploadStatisticsRow(name: ledger.name, summary: ledger.summary(in: window))
                    }
                }
            }
        } header: {
            Text("Upload Statistics".localized())
        } footer: {
            HStack {
                Text("Statistics stay on this Mac and are never synced.".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export CSV…".localized(), action: exportCSV)
                Button("Reset".localized(), role: .destructive) { confirmReset = true }
            }
            .disabled(store.database.ledgers.isEmpty)
            .padding(.top, 6)
        }
        .confirmationDialog("Reset all upload statistics?".localized(), isPresented: $confirmReset) {
            Button("Reset".localized(), role: .destructive) { store.reset() }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "ishare-upload-statistics.csv"
        let contents = Data(store.csv.utf8)
        Task { @MainActor in
            if await panel.beginAsyncModal() == .OK, let url = panel.url {
                try? contents.write(to: url, options: .atomic)
            }
        }
    }
}

struct UploaderStatisticsSection: View {
    let key: String
    @ObservedObject var store: UploadStatisticsStore = .shared

    var body: some View {
        if let ledger = store.ledger(for: key) {
            Section {
                ForEach(UploadStatisticsWindow.allCases) { window in
                    UploadStatisticsDetail(title: window.title, summary: ledger.summary(in: window))
                }
            } header: {
                Text("Statistics".localized())
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset Statistics".localized(), role: .destructive) { store.reset(key) }
                }
                .padding(.top, 6)
            }
        }
    }
}

private struct UploadStatisticsRow: View {
    let name: String
    let summary: UploadStatisticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 13, weight: .medium))
            Text(UploadStatisticsFormat.overview(summary))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let failure = UploadStatisticsFormat.lastFailure(summary) {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

private struct UploadStatisticsDetail: View {
    let title: String
    let summary: UploadStatisticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            LabeledContent("Uploads".localized(), value: String(summary.uploads))
            LabeledContent("Total Size".localized(), value: UploadStatisticsFormat.bytes(summary.bytes))
            LabeledContent("Average Duration".localized(), value: UploadStatisticsFormat.duration(summary.averageDuration))
            LabeledContent("95th Percentile Duration".localized(), value: UploadStatisticsFormat.duration(summary.p95Duration))
            LabeledContent("Failure Rate".localized(), value: UploadStatisticsFormat.rate(summary.failureRate))
            LabeledContent("Last Success".localized(), value: UploadStatisticsFormat.date(summary.lastSuccess))
            if let failure = UploadStatisticsFormat.lastFailure(summary) {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }
}

enum UploadStatisticsFormat {
    static let placeholder = "–"

    static func overview(_ summary: UploadStatisticsSummary) -> String {
        [
            String(format: "%d uploads".localized(), summary.uploads),
            bytes(summary.bytes),
            String(format: "avg %@".localized(), duration(summary.averageDuration)),
            String(format: "p95 %@".localized(), duration(summary.p95Duration)),
            String(format: "%@ failed".localized(), rate(summary.failureRate)),
        ].joined(separator: " · ")
    }

    static func lastFailure(_ summary: UploadStatisticsSummary) -> String? {
        guard let date = summary.lastFailure else { return nil }
        let when = String(format: "Last failure %@".localized(), self.date(date))
        return [when, summary.lastError].compactMap { $0 }.joined(separator: ": ")
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return placeholder }
        return Duration.milliseconds(Int((seconds * 1000).rounded()))
            .formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow, maximumUnitCount: 1, fractionalPart: .show(length: 1)))
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return placeholder }
        return value.formatted(.percent.precision(.fractionLength(0 ... 1)))
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return placeholder }
        return value.formatted(.relative(presentation: .named))
    }
}
