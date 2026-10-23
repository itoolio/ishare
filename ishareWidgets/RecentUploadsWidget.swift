import AppKit
import SwiftUI
import WidgetKit

struct RecentUploadsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let thumbnails: [String: NSImage]

    static let placeholder = RecentUploadsEntry(
        date: .now,
        snapshot: WidgetSnapshot(items: (0 ..< 4).map {
            WidgetSnapshot.Item(id: "\($0)", url: nil, name: "ishare-\($0).png", date: .now, thumbnail: nil, isVideo: false)
        }),
        thumbnails: [:]
    )

    static func load() -> RecentUploadsEntry {
        let snapshot = WidgetSharedContainer.readSnapshot()
        var thumbnails: [String: NSImage] = [:]
        if let directory = WidgetSharedContainer.thumbnailDirectory {
            for item in snapshot.items {
                guard let name = item.thumbnail, let image = NSImage(contentsOf: directory.appending(path: name)) else { continue }
                thumbnails[item.id] = image
            }
        }
        return RecentUploadsEntry(date: .now, snapshot: snapshot, thumbnails: thumbnails)
    }
}

struct RecentUploadsProvider: TimelineProvider {
    func placeholder(in _: Context) -> RecentUploadsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (RecentUploadsEntry) -> Void) {
        let entry = RecentUploadsEntry.load()
        completion(context.isPreview && entry.snapshot.items.isEmpty ? .placeholder : entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<RecentUploadsEntry>) -> Void) {
        completion(Timeline(entries: [.load()], policy: .never))
    }
}

struct RecentUploadsWidget: Widget {
    static let kind = "dev.adrian.ishare.widgets.recentUploads"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecentUploadsProvider()) { entry in
            RecentUploadsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WidgetStrings.recentUploads)
        .description(WidgetStrings.recentUploadsDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentUploadsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentUploadsEntry

    private var items: [WidgetSnapshot.Item] {
        Array(entry.snapshot.items.prefix(family == .systemSmall ? 4 : 6))
    }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title)
                Text(WidgetStrings.noUploads)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .widgetURL(WidgetSnapshot.captureRegionURL)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(WidgetStrings.recentUploads)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: family == .systemSmall ? 2 : 3), spacing: 6) {
                    ForEach(items) { item in
                        tile(for: item)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func tile(for item: WidgetSnapshot.Item) -> some View {
        let content = UploadTile(item: item, image: entry.thumbnails[item.id])
        if let url = item.url {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

struct UploadTile: View {
    let item: WidgetSnapshot.Item
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.isVideo ? "film" : "doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(item.name)
        .accessibilityLabel(item.name)
    }
}
