import SwiftUI

extension ToastCardContent {
    @ViewBuilder
    var replacementPrompt: some View {
        if model.replacedItem != nil {
            HStack(spacing: 6) {
                Text("Delete the previous upload from the server?".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Keep".localized()) { model.replacedItem = nil }
                    .accessibilityIdentifier("toast.replaced.keep")
                Button("Delete".localized(), role: .destructive) { model.deleteReplacedUpload() }
                    .accessibilityIdentifier("toast.replaced.delete")
            }
            .controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("toast.replaced")
        }
    }

    @ViewBuilder
    var detail: some View {
        if let message = model.message {
            Text(message.message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        } else {
            switch model.uploadState {
            case let .uploading(progress):
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.menuAccent)
                        .controlSize(.small)
                    Text(String(format: "Uploading… %d%%".localized(), Int((progress * 100).rounded())))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("toast.progress")
            case .failed:
                Label("Upload failed".localized(), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            case .uploaded, .none:
                if let url = model.historyItem.flatMap({ $0.preferredURL?.absoluteString ?? $0.fileUrl }) {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("toast.url")
                } else {
                    Text(saveToDisk ? "Saved to disk".localized() : "Captured".localized())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
