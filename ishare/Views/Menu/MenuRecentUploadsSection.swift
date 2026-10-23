import SwiftUI

struct MenuRecentUploadsSection: View {
    let history: [HistoryItem]
    let previewedItem: HistoryItem?
    let onHoverItem: (HistoryItem?) -> Void
    let onHoverPreview: (Bool) -> Void
    let onClosePreview: () -> Void
    @EnvironmentObject private var app: AppModel
    @Environment(\.menuMetrics) private var metrics

    static let visibleCount = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(history.prefix(Self.visibleCount).enumerated()), id: \.element) { index, item in
                RecentUploadThumbnail(item: item, index: index, size: metrics.thumbnailSize) { hovering in
                    onHoverItem(hovering ? item : nil)
                } onDragStart: {
                    onClosePreview()
                }
                .menuFocusRing(.recent(index), shape: .roundedRectangle(8))
            }
            Spacer(minLength: 0)
            Button {
                app.menuActions.openHistory(history)
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: metrics.thumbnailSize, height: metrics.thumbnailSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ActionTileStyle())
            .help("Open History Window".localized())
            .favoriteContextMenu(MenuFavoriteCommandID.history)
            .menuFocusRing(.history)
            .accessibilityIdentifier("menu.history")
        }
        .overlay(alignment: .bottomLeading) {
            if let previewedItem {
                RecentUploadPreview(item: previewedItem, uploaderName: previewedItem.uploaderName(among: CustomUploader.allCases)) { hovering in
                    onHoverPreview(hovering)
                } onFinish: {
                    onClosePreview()
                }
                .offset(y: -(metrics.thumbnailSize + 8))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.18), value: previewedItem)
        .zIndex(1)
    }
}

struct RecentUploadThumbnail: View {
    let item: HistoryItem
    let index: Int
    var size: CGFloat = 44
    let onHover: (Bool) -> Void
    var onDragStart: () -> Void = {}
    @State private var shareAnchor = ViewAnchor()
    @Environment(\.menuContrast) private var contrast

    var body: some View {
        Button {
            HistoryActions.copyURL(item)
        } label: {
            HistoryThumbnail(item: item, pointSize: size)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(contrast.isHigh ? contrast.borderOpacity : 0.1), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .anchored(to: shareAnchor)
        .onHover(perform: onHover)
        .onDrag {
            onDragStart()
            return DragExport.provider(for: item)
        }
        .contextMenu { HistoryItemMenuItems(item: item, showsFinder: false, shareAnchor: shareAnchor) }
        .accessibilityLabel(item.fileName)
        .accessibilityIdentifier("menu.recent.\(index)")
    }
}
