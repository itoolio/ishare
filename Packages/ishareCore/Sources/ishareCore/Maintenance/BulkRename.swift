import Foundation

public enum BulkRename {
    public static func titles(template: String, originals: [String], date: Date = Date()) -> [String] {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return originals }
        let width = String(originals.count).count
        let day = date.formatted(.iso8601.year().month().day())
        return originals.enumerated().map { index, original in
            let number = String(index + 1)
            let padded = String(repeating: "0", count: max(0, width - number.count)) + number
            var title = trimmed.replacingOccurrences(of: "{{n}}", with: padded)
                .replacingOccurrences(of: "{{name}}", with: (original as NSString).deletingPathExtension)
                .replacingOccurrences(of: "{{date}}", with: day)
            if !trimmed.contains("{{n}}"), originals.count > 1 {
                title += " \(padded)"
            }
            return title
        }
    }

    public static func expiry(days: Int?, from date: Date = Date()) -> Date? {
        guard let days, days > 0 else { return nil }
        return date.addingTimeInterval(Double(days) * 86400)
    }
}
