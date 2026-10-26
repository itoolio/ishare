import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryExportRequest: Identifiable {
    let id = UUID()
    let all: [HistoryItem]
    let filtered: [HistoryItem]
    let selected: [HistoryItem]
    let filterIsActive: Bool
    let uploaderName: (HistoryItem) -> String?

    var availableScopes: [HistoryExportScope] {
        HistoryExportScope.allCases.filter { scope in
            switch scope {
            case .all: true
            case .filtered: filterIsActive
            case .selection: !selected.isEmpty
            }
        }
    }

    var preferredScope: HistoryExportScope {
        if !selected.isEmpty { return .selection }
        return filterIsActive ? .filtered : .all
    }

    func items(for scope: HistoryExportScope) -> [HistoryItem] {
        HistoryExportScope.items(scope, all: all, filtered: filtered, selected: selected)
    }
}

struct HistoryExportSheet: View {
    let request: HistoryExportRequest
    let onClose: () -> Void
    @State private var format: HistoryExportFormat = .html
    @State private var scope: HistoryExportScope
    @State private var includesDeletionLinks = false
    @State private var isExporting = false
    @State private var errorMessage: String?

    init(request: HistoryExportRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
        _scope = State(initialValue: request.preferredScope)
    }

    private var items: [HistoryItem] { request.items(for: scope) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export History".localized())
                .font(.headline)
            Form {
                Picker("Format:".localized(), selection: $format) {
                    ForEach(HistoryExportFormat.allCases) { format in
                        Text(format.title.localized()).tag(format)
                    }
                }
                .accessibilityIdentifier("history.export.format")
                Picker("Uploads:".localized(), selection: $scope) {
                    ForEach(request.availableScopes) { scope in
                        Text(String(format: "%@ (%d)".localized(), scope.title.localized(), request.items(for: scope).count)).tag(scope)
                    }
                }
                .accessibilityIdentifier("history.export.scope")
                Toggle("Include deletion links".localized(), isOn: $includesDeletionLinks)
                    .accessibilityIdentifier("history.export.deletionLinks")
                if includesDeletionLinks {
                    Label("Anyone with the exported file can delete these uploads.".localized(), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.columns)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack {
                if isExporting {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel".localized(), role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Export…".localized(), action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(items.isEmpty || isExporting)
                    .accessibilityIdentifier("history.export.confirm")
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = HistoryExportWriter.defaultFileName(for: format)
        if let ext = format.fileExtension, let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let inputs = items.map { HistoryExportWriter.Input(item: $0, uploaderName: request.uploaderName($0)) }
        let format = format
        let includesDeletionLinks = includesDeletionLinks
        isExporting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let written = try await HistoryExportWriter.write(inputs, format: format, includesDeletionLinks: includesDeletionLinks, to: url)
                isExporting = false
                onClose()
                NSWorkspace.shared.activateFileViewerSelecting([written])
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
