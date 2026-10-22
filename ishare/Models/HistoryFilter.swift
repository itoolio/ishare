import Foundation

enum HistoryKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case images
    case videos
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .images: "Images"
        case .videos: "Videos"
        case .other: "Other"
        }
    }

    func includes(_ kind: HistoryItemKind) -> Bool {
        switch self {
        case .all: true
        case .images: kind == .image
        case .videos: kind == .video
        case .other: kind == .other
        }
    }
}

enum HistoryUploaderFilter: Hashable, Sendable {
    case all
    case uploader(HistoryUploader)

    func includes(_ uploader: HistoryUploader) -> Bool {
        switch self {
        case .all: true
        case let .uploader(expected): expected == uploader
        }
    }
}

struct HistoryFilter: Equatable, Sendable {
    var query = ""
    var uploader: HistoryUploaderFilter = .all
    var kind: HistoryKindFilter = .all

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || uploader != .all || kind != .all
    }

    static func defaultDateTexts(_ date: Date) -> [String] {
        [
            date.formatted(date: .abbreviated, time: .shortened),
            date.formatted(date: .numeric, time: .omitted),
            date.formatted(date: .long, time: .omitted),
            date.formatted(.dateTime.weekday(.wide)),
            date.formatted(.iso8601.year().month().day()),
        ]
    }

    func searchableTexts(for item: HistoryItem, uploaderName: String?, dateTexts: (Date) -> [String]) -> [String] {
        var texts = [item.fileUrl, item.fileName, item.localFileURL?.lastPathComponent, uploaderName].compactMap { $0 }
        if let date = item.date {
            texts += dateTexts(date)
        }
        return texts.map { $0.lowercased() }
    }

    func matches(_ item: HistoryItem, uploaderName: String?, dateTexts: (Date) -> [String] = HistoryFilter.defaultDateTexts) -> Bool {
        guard kind.includes(item.kind), uploader.includes(item.uploader) else { return false }
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let texts = searchableTexts(for: item, uploaderName: uploaderName, dateTexts: dateTexts)
        return tokens.allSatisfy { token in texts.contains { $0.contains(token) } }
    }

    func apply(to items: [HistoryItem], uploaderName: (HistoryItem) -> String?, dateTexts: (Date) -> [String] = HistoryFilter.defaultDateTexts) -> [HistoryItem] {
        items.filter { matches($0, uploaderName: uploaderName($0), dateTexts: dateTexts) }
    }
}

extension Array where Element == HistoryItem {
    func distinctUploaders() -> [HistoryUploader] {
        var seen = Set<HistoryUploader>()
        return compactMap { item in
            seen.insert(item.uploader).inserted ? item.uploader : nil
        }
    }
}
