import Defaults
import Foundation
import ishareCore

@MainActor
enum ViewCounts {
    private static var isRefreshing = false

    static func refresh(_ items: [HistoryItem], now: Date = Date()) async {
        guard !isRefreshing else { return }
        let stale = items.filter { $0.viewCountUrl != nil && ViewCountParser.needsRefresh(checkedAt: $0.viewCountCheckedAt, now: now) }
        guard !stale.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let uploaders = CustomUploader.allCases
        for item in stale.prefix(40) {
            guard let urlString = item.viewCountUrl, let url = URL(string: urlString) else { continue }
            let uploader = uploaders.first { $0.id == item.uploaderId }
            var request = URLRequest(url: url, timeoutInterval: 15)
            for (name, value) in uploader?.headers ?? [:] {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let count: Int?
            if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? false {
                count = ViewCountParser.count(in: data, path: uploader?.viewCount?.path ?? "views")
            } else {
                count = nil
            }
            updateUploadHistoryItem(item) { current in
                var updated = current
                updated.viewCount = count ?? current.viewCount
                updated.viewCountCheckedAt = now
                return updated
            }
        }
    }
}
