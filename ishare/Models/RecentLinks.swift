import Foundation

struct RecentLink: Equatable, Sendable {
    let item: HistoryItem
    let url: String

    var displayTitle: String {
        guard let components = URLComponents(string: url), let host = components.host else { return url }
        let path = components.percentEncodedPath
        return path.isEmpty || path == "/" ? host : host + path
    }
}

enum RecentLinks {
    static let limit = 20

    static func links(from history: [HistoryItem], limit: Int = limit) -> [RecentLink] {
        var seen = Set<String>()
        var links: [RecentLink] = []
        for item in history {
            guard links.count < limit, let url = item.fileUrl?.trimmingCharacters(in: .whitespaces), !url.isEmpty, seen.insert(url).inserted else { continue }
            links.append(RecentLink(item: item, url: url))
        }
        return links
    }
}
