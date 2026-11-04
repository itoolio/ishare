import Foundation

public enum HistoryGrouping: String, CaseIterable, Codable, Sendable {
    case day
    case app
    case project

    static let separators = [" — ", " – ", " - ", " | ", " · "]
    static let maximumProjectLength = 40

    public static func project(fromTitle title: String?, appName: String?) -> String? {
        guard var parts = title.map({ [$0] }) else { return nil }
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        let app = appName?.lowercased()
        let candidates = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { part in
            !part.isEmpty && part.lowercased() != app && part.count <= maximumProjectLength && !looksLikeFile(part)
        }
        guard parts.count > 1 || candidates.count == 1 else { return nil }
        return candidates.last
    }

    static func looksLikeFile(_ text: String) -> Bool {
        let ext = (text as NSString).pathExtension
        return !ext.isEmpty && ext.count <= 5 && !text.contains(" ") && ext.allSatisfy(\.isLetter)
    }
}
