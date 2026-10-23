import SwiftUI

extension ToastCardContent {
    var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: model.isImage ? "photo" : "film")
                    .foregroundStyle(.secondary)
            }
            if model.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .onDrag {
            model.isDragging = true
            return DragExport.provider(fileURL: model.fileURL, historyItem: model.historyItem, isImage: model.kind == .image)
        }
        .onTapGesture {
            if saveToDisk, let url = model.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            model.onDismiss()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.fileName)
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: Text("Copy".localized())) { copy() }
        .accessibilityAction(named: Text("Open".localized())) { open() }
        .accessibilityAction(named: Text("Show in Finder".localized())) { showInFinder() }
        .help("Drag to share or click to show in Finder".localized())
        .overlay(alignment: .bottomTrailing) {
            if model.canAnnotate {
                annotateButton
            }
        }
    }

    private func showInFinder() {
        if let url = model.fileURL, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private var annotateButton: some View {
        Button {
            model.beginAnnotating()
        } label: {
            Image(systemName: "pencil.tip")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.menuAccent))
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(3)
        .help("Annotate".localized())
        .accessibilityLabel("Annotate".localized())
        .accessibilityIdentifier("toast.annotate.open")
    }
}
