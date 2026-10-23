import Defaults
import Foundation
import ishareCore
import SwiftUI

struct HistoryThumbnail: View {
    let item: HistoryItem
    var pointSize: CGFloat = 160
    var contentMode: ContentMode = .fill

    var body: some View {
        let key = ThumbnailKey.forItem(item, pointSize: pointSize)
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.06))
            ThumbnailImage(key: key, contentMode: contentMode) { failed in
                if failed {
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if item.kind == .video, key != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
        }
    }

    private var placeholderSymbol: String {
        switch item.kind {
        case .image: "photo"
        case .video: "video.fill"
        case .other: "doc"
        }
    }
}

struct HistoryGridView: View {
    @Default(.uploadHistory) var uploadHistory
    @Default(.savedCustomUploaders) var savedCustomUploaders
    @Default(.savedLocalUploaders) var savedLocalUploaders
    @State private var filter = HistoryFilter()
    @State private var selection = HistorySelection()
    @State private var shareAnchor = ViewAnchor()

    private var uploaders: [CustomUploader] {
        Array((savedCustomUploaders ?? []).union(savedLocalUploaders))
    }

    private var filteredHistory: [HistoryItem] {
        let uploaders = uploaders
        return filter.apply(to: uploadHistory) { $0.uploaderName(among: uploaders) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !uploadHistory.isEmpty {
                filterBar
                Divider()
                if !selection.isEmpty {
                    selectionBar
                    Divider()
                }
            }
            content
        }
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: filteredHistory) { _, visible in
            selection.retain(visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if uploadHistory.isEmpty {
            ContentUnavailableView("No uploads yet".localized(), systemImage: "clock.arrow.circlepath", description: Text("Uploads appear here after you share a capture.".localized()))
        } else if filteredHistory.isEmpty {
            ContentUnavailableView {
                Label("No Matching Uploads".localized(), systemImage: "magnifyingglass")
            } description: {
                Text("Try a different search or filter.".localized())
            } actions: {
                Button("Clear Filters".localized()) { filter = HistoryFilter() }
                    .accessibilityIdentifier("history.clearFilters")
            }
        } else {
            timeline
        }
    }

    private var timeline: some View {
        let visible = filteredHistory
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(HistoryTimeline.sections(for: visible)) { section in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                            ForEach(section.items, id: \.self) { item in
                                card(for: item, in: visible)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection.clear() }
        }
    }

    private func sectionHeader(_ section: HistoryDaySection) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
            Text(section.items.count, format: .number)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("history.section")
    }

    private func card(for item: HistoryItem, in visible: [HistoryItem]) -> some View {
        HistoryCard(
            item: item,
            uploaderName: item.uploaderName(among: uploaders),
            isSelected: selection.contains(item),
            onSelect: { modifier in selection.click(item, modifier: modifier, in: visible) },
            bulkItems: selection.contains(item) && selection.count > 1 ? selection.ordered(in: visible) : nil
        )
    }

    private var selectedItems: [HistoryItem] {
        selection.ordered(in: filteredHistory)
    }

    private var selectionBar: some View {
        let items = selectedItems
        return HStack(spacing: 8) {
            Text(String(format: "%d selected".localized(), items.count))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .accessibilityIdentifier("history.selection.count")
            Spacer()
            Button("Copy Links".localized(), systemImage: "link") { HistoryActions.copyLinks(items) }
                .disabled(HistorySelection.links(for: items).isEmpty)
                .accessibilityIdentifier("history.bulk.copyLinks")
            Button("Share…".localized(), systemImage: "square.and.arrow.up") {
                SharePicker.show(SharePicker.items(for: items), from: shareAnchor)
            }
            .anchored(to: shareAnchor)
            .accessibilityIdentifier("history.bulk.share")
            Button("Combine…".localized(), systemImage: "square.grid.2x2") { HistoryActions.combine(items) }
                .disabled(!HistoryActions.canCombine(items))
                .help("Combine the selected images into one".localized())
                .accessibilityIdentifier("history.bulk.combine")
            Button("Delete from Server…".localized(), systemImage: "trash", role: .destructive) {
                HistoryActions.confirmDeleteFromServer(items)
            }
            .disabled(!items.contains(where: \.canDeleteFromServer))
            .accessibilityIdentifier("history.bulk.deleteFromServer")
            Button("Remove from History".localized(), systemImage: "minus.circle") {
                HistoryActions.removeFromHistory(items)
                selection.clear()
            }
            .accessibilityIdentifier("history.bulk.remove")
            Button("Deselect".localized()) { selection.clear() }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("history.bulk.deselect")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .adaptiveGlassBar()
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search uploads".localized(), text: $filter.query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("history.search")
                if !filter.query.isEmpty {
                    Button {
                        filter.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear".localized())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .adaptiveGlass(cornerRadius: 8, interactive: true, fallback: .fill(0.07))
            .frame(minWidth: 200)

            Picker("Uploader".localized(), selection: $filter.uploader) {
                Text("All Uploaders".localized()).tag(HistoryUploaderFilter.all)
                Divider()
                ForEach(uploadHistory.distinctUploaders(), id: \.self) { uploader in
                    Text(title(for: uploader)).tag(HistoryUploaderFilter.uploader(uploader))
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("history.filter.uploader")

            Picker("Type".localized(), selection: $filter.kind) {
                ForEach(HistoryKindFilter.allCases) { kind in
                    Text(kind.title.localized()).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("history.filter.type")

            Text(String(format: "%d of %d".localized(), filteredHistory.count, uploadHistory.count))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()

            Button("Select All".localized()) { selection.selectAll(filteredHistory) }
                .keyboardShortcut("a")
                .controlSize(.small)
                .disabled(filteredHistory.isEmpty)
                .accessibilityIdentifier("history.selectAll")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .adaptiveGlassBar()
    }


    private func title(for uploader: HistoryUploader) -> String {
        switch uploader {
        case .imgur: "Imgur"
        case let .custom(id): uploaders.first { $0.id == id }?.name ?? "Removed Uploader".localized()
        case .unknown: "Other".localized()
        }
    }
}

extension HistorySelection.Modifier {
    @MainActor static var current: HistorySelection.Modifier {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { return .extend }
        if flags.contains(.command) { return .toggle }
        return .none
    }
}

struct HistoryCard: View {
    let item: HistoryItem
    let uploaderName: String?
    var isSelected = false
    var onSelect: (HistorySelection.Modifier) -> Void = { _ in }
    var bulkItems: [HistoryItem]?
    @State private var isHovered = false
    @State private var shareAnchor = ViewAnchor()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .overlay { HistoryThumbnail(item: item, pointSize: 220) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.fileName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 4) {
                if let date = item.date {
                    Text(date, format: .dateTime.hour().minute())
                }
                if let uploaderName {
                    Text("·")
                    Text(uploaderName)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .adaptiveGlass(cornerRadius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.menuAccent.opacity(isSelected ? 0.12 : 0)).allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.menuAccent.opacity(isSelected ? 1 : isHovered ? 0.6 : 0), lineWidth: isSelected ? 2 : 1.5))
        .anchored(to: shareAnchor)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag { DragExport.provider(for: item) }
        .onTapGesture(count: 2) { HistoryActions.open(item) }

        .simultaneousGesture(TapGesture().onEnded { onSelect(.current) })
        .contextMenu { contextMenu }
        .help(item.fileUrl ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("history.card")
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let bulkItems {
            Button(String(format: "Copy %d Links".localized(), HistorySelection.links(for: bulkItems).count)) { HistoryActions.copyLinks(bulkItems) }
            Button("Share…".localized()) { SharePicker.show(SharePicker.items(for: bulkItems), from: shareAnchor) }
            if HistoryActions.canCombine(bulkItems) {
                Button("Combine…".localized()) { HistoryActions.combine(bulkItems) }
            }
            Divider()
            if bulkItems.contains(where: \.canDeleteFromServer) {
                Button("Delete from Server…".localized(), role: .destructive) { HistoryActions.confirmDeleteFromServer(bulkItems) }
            }
            Button("Remove from History".localized()) { HistoryActions.removeFromHistory(bulkItems) }
        } else {
            HistoryItemMenuItems(item: item, shareAnchor: shareAnchor, showsImageActions: true)
        }
    }
}
