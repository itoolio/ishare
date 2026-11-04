import AppKit
import BezelNotification
import Defaults
import ishareCore
import SwiftUI

enum StorageScanner {
    static func files(in plan: LocalCaptureCleanupPlan) -> [(url: URL, file: StorageFile)] {
        LocalCaptureCleanup.candidates(for: plan).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            let kind: StorageFile.Kind = HistoryItemKind(fileExtension: url.pathExtension) == .video ? .video : .image
            return (url, StorageFile(kind: kind, bytes: Int64(values.fileSize ?? 0), date: values.contentModificationDate ?? .distantPast))
        }
    }

    static func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

@MainActor
final class StorageOverviewModel: ObservableObject {
    @Published private(set) var summary: StorageSummary?
    @Published private(set) var isScanning = false
    private var oldFiles: [URL] = []

    func scan() {
        guard !isScanning, var plan = LocalCaptureCleanup.allCapturesPlan() else { return }
        isScanning = true
        plan.protectedPaths = []
        let remote = Defaults[.uploadHistory].compactMap { item -> (host: String, bytes: Int64)? in
            guard let host = item.remoteURL?.host(), let bytes = item.uploadedSize ?? item.originalSize else { return nil }
            return (host, Int64(bytes))
        }
        let cache = HistoryPreview.cacheDirectory
        Task.detached(priority: .utility) {
            let files = StorageScanner.files(in: plan)
            let cutoff = Date().addingTimeInterval(-Double(StorageSummary.suggestionAge) * 86400)
            let summary = StorageSummary(files: files.map(\.file), cacheBytes: StorageScanner.size(of: cache), remote: remote)
            let old = files.filter { $0.file.date < cutoff }.map(\.url)
            await MainActor.run {
                self.summary = summary
                self.oldFiles = old
                self.isScanning = false
            }
        }
    }

    func trashOldFiles() {
        let moved = LocalCaptureCleanup.moveToTrash(oldFiles)
        BezelNotification.show(messageText: String(format: "Moved %d old captures to the Trash".localized(), moved), icon: ToastIcon)
        scan()
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: HistoryPreview.cacheDirectory)
        scan()
    }
}

struct StorageOverviewSection: View {
    @StateObject private var model = StorageOverviewModel()

    var body: some View {
        Section {
            if let summary = model.summary {
                LabeledContent("Screenshots".localized(), value: "\(summary.imageCount) · \(bytes(summary.imageBytes))")
                LabeledContent("Recordings".localized(), value: "\(summary.videoCount) · \(bytes(summary.videoBytes))")
                LabeledContent("Preview cache".localized(), value: bytes(summary.cacheBytes))
                ForEach(summary.hostsBySize.prefix(5), id: \.host) { host in
                    LabeledContent(host.host, value: bytes(host.bytes))
                }
                if summary.suggestsCleaningOldFiles {
                    HStack {
                        Text(String(format: "%d captures older than %d days use %@".localized(), summary.oldCount, StorageSummary.suggestionAge, bytes(summary.oldBytes)))
                        Spacer()
                        Button("Move to Trash".localized(), action: model.trashOldFiles)
                    }
                }
                if summary.suggestsClearingCache {
                    HStack {
                        Text(String(format: "The preview cache uses %@".localized(), bytes(summary.cacheBytes)))
                        Spacer()
                        Button("Clear".localized(), action: model.clearCache)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Recalculate".localized(), action: model.scan)
                .disabled(model.isScanning)
        } header: {
            Text("Storage".localized())
        } footer: {
            Text("Counts the captures ishare named in its save folders, and what your uploads take up on each host as far as ishare knows.".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: model.scan)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
