import BezelNotification
import Defaults
import Foundation
import SwiftUI

struct HistoryThumbnail: View {
    let item: HistoryItem

    private var isVideo: Bool {
        let ext = (item.fileUrl.flatMap(URL.init(string:))?.pathExtension ?? item.localPath.map { URL(fileURLWithPath: $0).pathExtension } ?? "").lowercased()
        return ["mp4", "mov"].contains(ext)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.06))
            if isVideo {
                Image(systemName: "video.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            } else if let path = item.localPath, FileManager.default.fileExists(atPath: path),
                      let image = ImageProcessing.thumbnail(for: URL(fileURLWithPath: path), maxPixelSize: 320)
            {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                PreviewImage(url: item.fileUrl.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case let .success(image):
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

struct HistoryGridView: View {
    @Default(.uploadHistory) var uploadHistory

    var body: some View {
        Group {
            if uploadHistory.isEmpty {
                ContentUnavailableView("No uploads yet".localized(), systemImage: "clock.arrow.circlepath")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 10)], spacing: 10) {
                        ForEach(uploadHistory, id: \.self) { item in
                            card(for: item)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func card(for item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 104)
                .overlay { HistoryThumbnail(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.fileUrl.flatMap(URL.init(string:))?.lastPathComponent ?? "")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if let date = item.date {
                Text(date, format: .relative(presentation: .named))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .adaptiveGlass(cornerRadius: 14)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openInBrowser(item) }
        .contextMenu {
            Button("Copy URL".localized()) { copyURL(item) }
            Button("Open in Browser".localized()) { openInBrowser(item) }
            if let path = item.localPath, FileManager.default.fileExists(atPath: path) {
                Button("Open in Editor".localized()) {
                    Task { @MainActor in _ = await ImageEditor.edit(fileURL: URL(fileURLWithPath: path)) }
                }
                Button("Show in Finder".localized()) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            Button("Delete".localized(), role: .destructive) { deleteItem(item) }
        }
    }

    private func copyURL(_ item: HistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.fileUrl ?? "", forType: .string)
        BezelNotification.show(messageText: "Copied URL".localized(), icon: ToastIcon)
    }

    private func openInBrowser(_ item: HistoryItem) {
        if let url = URL(string: item.fileUrl ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    private func deleteItem(_ item: HistoryItem) {
        Task { @MainActor in
            do {
                try await UploadCoordinator.delete(item)
            } catch {
                NSLog("Deletion error: %@", error.localizedDescription)
            }
            uploadHistory.removeAll { $0 == item }
            BezelNotification.show(messageText: "Deleted".localized(), icon: ToastIcon)
        }
    }
}
