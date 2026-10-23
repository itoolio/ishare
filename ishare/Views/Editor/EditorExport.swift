import AppKit
import BezelNotification
import UniformTypeIdentifiers

@MainActor
enum EditorExport {
    static func data(for document: EditorDocument, format: EditorExportFormat) throws -> Data {
        document.commitPendingEdits()
        let input = VectorExportInput(base: document.adjustedBase, annotations: document.annotations, crop: document.crop)
        switch format {
        case .png:
            guard let rendered = document.render() else { throw CocoaError(.fileWriteUnknown) }
            return try ImageEncoder.data(for: rendered, as: .PNG)
        case .pdf:
            guard let data = PDFExporter.data(for: input) else { throw CocoaError(.fileWriteUnknown) }
            return data
        case .svg:
            return Data(SVGExporter.document(for: input).utf8)
        }
    }

    static func contentType(for format: EditorExportFormat) -> UTType {
        switch format {
        case .png: .png
        case .pdf: .pdf
        case .svg: .svg
        }
    }

    static func export(_ document: EditorDocument, as format: EditorExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType(for: format)]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let baseName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "ishare"
        panel.nameFieldStringValue = baseName + "." + format.rawValue
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(for: document, format: format).write(to: url, options: .atomic)
            BezelNotification.show(messageText: "Exported".localized(), icon: ToastIcon)
        } catch {
            Log.app.error("Exporting the edited image failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }
}
