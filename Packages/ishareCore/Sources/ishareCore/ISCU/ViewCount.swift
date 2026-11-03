import Foundation
import SwiftyJSON

public struct ViewCountSpec: Codable, Hashable, Sendable {
    public var url: String
    public var path: String

    public init(url: String, path: String) {
        self.url = url
        self.path = path
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        url = try container.decodeDynamic(String.self, forKey: .key(named: "url"))
        path = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "path")) ?? "views"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(path, forKey: .path)
    }

    enum CodingKeys: String, CodingKey {
        case url
        case path
    }
}

public enum ViewCountParser {
    public static let refreshInterval: TimeInterval = 10 * 60

    public static func count(in data: Data, path: String) -> Int? {
        guard let json = try? JSON(data: data), let raw = ResponseTemplate.value(at: path, in: json) else { return nil }
        if let value = Int(raw) { return value }
        if let value = Double(raw), value.isFinite { return Int(value) }
        return nil
    }

    public static func needsRefresh(checkedAt: Date?, now: Date = Date(), interval: TimeInterval = refreshInterval) -> Bool {
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= interval
    }

    public static func label(for count: Int) -> String {
        switch count {
        case ..<1000: String(count)
        case ..<1_000_000: String(format: "%.1fK", Double(count) / 1000).replacingOccurrences(of: ".0K", with: "K")
        default: String(format: "%.1fM", Double(count) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}
