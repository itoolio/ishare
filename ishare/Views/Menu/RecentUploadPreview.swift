import ishareCore
import SwiftUI

struct RecentUploadPreview: View {
    let item: HistoryItem
    let uploaderName: String?
    let onHover: (Bool) -> Void
    let onFinish: () -> Void
    @EnvironmentObject private var app: AppModel
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(width: 272, height: 150)
                .overlay { HistoryThumbnail(item: item, pointSize: 280, contentMode: .fit) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            details
            actions
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(contrast.borderOpacity), lineWidth: 1))
        .onHover(perform: onHover)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.preview")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.fileName)
                .font(.system(size: 12, weight: Font.Weight.semibold.emphasized(contrast)))
                .lineLimit(1)
                .truncationMode(.middle)
            if let url = item.preferredURL?.absoluteString ?? item.fileUrl {
                Text(url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            let facts = Self.facts(for: item)
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("menu.preview.facts")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ToastActionButton(symbol: "doc.on.doc", title: "Copy URL", identifier: "menu.preview.copy") {
                HistoryActions.copyURL(item)
                onFinish()
            }
            .disabled(item.fileUrl == nil)
            ToastActionButton(symbol: "safari", title: "Open", iconOnly: true, identifier: "menu.preview.open") {
                onFinish()
                app.menuActions.dismiss()
                HistoryActions.open(item)
            }
            if HistoryActions.canEdit(item) {
                ToastActionButton(symbol: "pencil.tip.crop.circle", title: "Edit", iconOnly: true, identifier: "menu.preview.edit") {
                    onFinish()
                    HistoryActions.edit(item)
                }
            }
            ShareActionButton(items: { SharePicker.items(for: item) }, iconOnly: true, identifier: "menu.preview.share")
            deleteMenu
        }
    }

    private var deleteMenu: some View {
        Menu {
            if item.canDeleteFromServer {
                Button("Delete from Server…".localized(), role: .destructive) {
                    onFinish()
                    HistoryActions.confirmDeleteFromServer(item)
                }
            }
            Button("Remove from History".localized()) {
                onFinish()
                HistoryActions.removeFromHistory(item)
            }
        } label: {
            ToastActionLabel(symbol: "trash", title: "Delete", iconOnly: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Delete".localized())
        .accessibilityIdentifier("menu.preview.delete")
    }

    static func facts(for item: HistoryItem, now: Date = Date(), fileSize: (URL) -> Int? = { (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }) -> [String] {
        var facts: [String] = []
        if let host = item.preferredURL?.host() {
            facts.append(host)
        }
        if let bytes = item.uploadedSize ?? item.existingLocalFileURL.flatMap(fileSize) {
            facts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if let views = item.viewCount {
            facts.append(String(format: "%@ views".localized(), ViewCountParser.label(for: views)))
        }
        if item.isKeptForever {
            facts.append("Kept forever".localized())
        } else if let expiresAt = item.expiresAt, !item.isExpired {
            facts.append(String(format: "Deletes %@".localized(), expiresAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))))
        }
        return facts
    }

    private var metadata: String {
        let date = item.date?.formatted(date: .abbreviated, time: .shortened)
        return [date, uploaderName].compactMap { $0 }.joined(separator: " · ")
    }
}
