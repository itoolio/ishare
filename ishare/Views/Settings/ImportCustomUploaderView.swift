import Defaults
import ishareCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportCustomUploaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.savedLocalUploaders) var savedLocalUploaders
    @Default(.activeCustomUploader) var activeCustomUploader
    @Default(.uploadType) var uploadType
    @Default(.uploadDestination) var uploadDestination
    @State private var importError: ImportError?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Import Custom Uploader".localized())
                .font(.title3.weight(.semibold))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Drag and drop .iscu or ShareX .sxcu files here or click to select".localized())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: choose)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in importUploader(from: url) }
                    }
                    return true
                }
            Button("Cancel".localized()) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .alert(item: $importError) { error in
            Alert(title: Text("Error".localized()), message: Text(error.localizedDescription), dismissButton: .default(Text("OK".localized())))
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "iscu") ?? .json, UTType(filenameExtension: ShareXImport.fileExtension) ?? .json, .json]
        Task { @MainActor in
            if await panel.beginAsyncModal() == .OK, let url = panel.url {
                importUploader(from: url)
            }
        }
    }

    private func importUploader(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let uploader = try UploaderFile.decode(contentsOf: url)
            UploaderStore.save(uploader)
            activeCustomUploader = uploader.id
            uploadType = .CUSTOM
            uploadDestination = .custom(uploader.id)
            dismiss()
        } catch {
            importError = ImportError(error: error)
        }
    }
}

struct ImportError: Identifiable {
    let id = UUID()
    let error: any Error

    var localizedDescription: String {
        error.localizedDescription
    }
}
