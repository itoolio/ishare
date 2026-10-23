import SwiftUI

struct UploadQueueSettings: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        UploadQueueSection(queue: app.uploadQueue)
    }
}

private struct UploadQueueSection: View {
    @ObservedObject var queue: UploadQueue
    @State private var retrying: Set<UUID> = []

    var body: some View {
        Section {
            if queue.items.isEmpty {
                Text("No failed uploads are waiting".localized())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(queue.items) { item in
                    row(for: item)
                }
            }
        } header: {
            Text("Upload Queue".localized())
        } footer: {
            if !queue.items.isEmpty {
                HStack {
                    Button("Retry All".localized()) {
                        Task { await queue.retryAll() }
                    }
                    Spacer()
                    Button("Discard All".localized(), role: .destructive) {
                        queue.discardAll()
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func row(for item: QueuedUpload) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isPaused ? "exclamationmark.icloud" : "arrow.clockwise.icloud")
                .foregroundStyle(item.isPaused ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if retrying.contains(item.id) {
                ProgressView().controlSize(.small)
            }
            Button {
                retrying.insert(item.id)
                Task {
                    await queue.retry(item.id)
                    retrying.remove(item.id)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Retry".localized())
            Button {
                queue.discard(item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Discard".localized())
        }
    }

    private func status(for item: QueuedUpload) -> String {
        let attempts = String(format: "%@ · %d attempts".localized(), item.destinationName, item.attempts)
        let next = item.isPaused
            ? "Retrying paused".localized()
            : String(format: "Next try %@".localized(), item.nextAttemptAt.formatted(.relative(presentation: .named)))
        return [attempts, next, item.lastError].compactMap { $0 }.joined(separator: " · ")
    }
}
