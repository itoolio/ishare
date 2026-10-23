import ishareCore
import SwiftUI

struct UploadTestSheet: View {
    let uploader: CustomUploader
    let onClose: () -> Void
    @State private var report: UploadTestReport?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let report {
                    UploadTestReportView(report: report)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(String(format: "Uploading a test image to %@…".localized(), uploader.name))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Button("Run Again".localized()) {
                    report = nil
                    Task { await run() }
                }
                .disabled(report == nil)
                Spacer()
                Button("Done".localized(), action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .task { await run() }
    }

    private func run() async {
        report = await UploadTester.run(uploader)
    }
}

struct UploadTestReportView: View {
    let report: UploadTestReport

    var body: some View {
        Form {
            Section {
                LabeledContent("Status".localized()) {
                    HStack(spacing: 6) {
                        Image(systemName: report.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(report.succeeded ? .green : .red)
                        Text(report.statusCode.map(String.init) ?? "No response".localized())
                            .font(.system(.body, design: .monospaced))
                        Text(String(format: "%.2f s", report.duration))
                            .foregroundStyle(.secondary)
                    }
                }
                if let url = report.url {
                    LabeledContent("URL".localized()) {
                        Text(url)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let deletionURL = report.deletionURL {
                    LabeledContent("Deletion URL".localized()) {
                        Text(deletionURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let error = report.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Result".localized())
            }
            if !report.headers.isEmpty {
                Section("Response Headers".localized()) {
                    ForEach(Array(report.headers.enumerated()), id: \.offset) { _, header in
                        LabeledContent(header.name) {
                            Text(header.value)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.system(.footnote, design: .monospaced))
                    }
                }
            }
            Section("Response Body".localized()) {
                ScrollView([.horizontal, .vertical]) {
                    Text(report.body.isEmpty ? "Empty".localized() : report.body)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(report.body.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(minHeight: 120, maxHeight: 260)
            }
        }
        .formStyle(.grouped)
    }
}
