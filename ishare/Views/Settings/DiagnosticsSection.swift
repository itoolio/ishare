import AppKit
import SwiftUI

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var reports: [DiagnosticReport] = []
    private let store: DiagnosticsStore
    private var observer: NSObjectProtocol?

    init(store: DiagnosticsStore = .shared) {
        self.store = store
        reload()
        observer = NotificationCenter.default.addObserver(forName: DiagnosticsStore.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        reports = store.reports()
    }

    func reveal(_ report: DiagnosticReport) {
        NSWorkspace.shared.activateFileViewerSelecting([report.url])
    }

    func copy(_ report: DiagnosticReport) {
        guard let contents = store.contents(of: report) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
    }

    func deleteAll() {
        store.deleteAll()
        reload()
    }

    func reportIssue() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        NSWorkspace.shared.open(DiagnosticsIssue.url(reports: reports, appVersion: appVersion, osVersion: osVersion))
    }
}

struct DiagnosticsSection: View {
    @StateObject private var model = DiagnosticsModel()

    var body: some View {
        Section {
            if model.reports.isEmpty {
                Text("No crash or hang reports have been collected.".localized())
                    .foregroundStyle(.secondary)
            }
            ForEach(model.reports) { report in
                DiagnosticReportRow(report: report, onReveal: { model.reveal(report) }, onCopy: { model.copy(report) })
            }
            HStack {
                Button("Include diagnostics when reporting an issue".localized()) { model.reportIssue() }
                    .accessibilityIdentifier("settings.diagnostics.report")
                Spacer()
                Button("Delete All".localized(), role: .destructive) { model.deleteAll() }
                    .disabled(model.reports.isEmpty)
                    .accessibilityIdentifier("settings.diagnostics.deleteAll")
            }
        } header: {
            Text("Diagnostics".localized())
        } footer: {
            Text("macOS hands ishare crash and hang reports, which stay on this Mac. Nothing is uploaded; reporting an issue opens a prefilled GitHub issue you can review first.".localized())
                .foregroundStyle(.secondary)
        }
        .onAppear { model.reload() }
    }
}

struct DiagnosticReportRow: View {
    let report: DiagnosticReport
    let onReveal: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.kind.title)
                Text([report.date.formatted(date: .abbreviated, time: .shortened), report.summary].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onReveal) { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .help("Reveal in Finder".localized())
                .accessibilityLabel("Reveal in Finder".localized())
            Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy".localized())
                .accessibilityLabel("Copy".localized())
        }
    }
}
