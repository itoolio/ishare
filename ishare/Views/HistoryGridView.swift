import Defaults
import Foundation
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
    @State private var filter = HistoryFilter()

    private var uploaders: [CustomUploader] {
        Array(savedCustomUploaders ?? [])
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
            }
            content
        }
        .frame(minWidth: 600, minHeight: 400)
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
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(filteredHistory, id: \.self) { item in
                        HistoryCard(item: item, uploaderName: item.uploaderName(among: uploaders))
                    }
                }
                .padding(14)
            }
        }
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
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func title(for uploader: HistoryUploader) -> String {
        switch uploader {
        case .imgur: "Imgur"
        case let .custom(id): uploaders.first { $0.id == id }?.name ?? "Removed Uploader".localized()
        case .unknown: "Other".localized()
        }
    }
}

struct HistoryCard: View {
    let item: HistoryItem
    let uploaderName: String?
    @State private var isHovered = false

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
                    Text(date, format: .relative(presentation: .named))
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
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.menuAccent.opacity(isHovered ? 0.6 : 0), lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { HistoryActions.open(item) }
        .contextMenu { HistoryItemMenuItems(item: item) }
        .help(item.fileUrl ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.card")
    }
}
