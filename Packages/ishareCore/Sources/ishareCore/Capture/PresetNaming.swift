import Foundation

public enum PresetNaming {
    public static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static func uniqueName(_ base: String, among existing: [String], copySuffix: String) -> String {
        let taken = Set(existing.map(normalized))
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard taken.contains(normalized(trimmed)) else { return trimmed }
        let stem = "\(trimmed) \(copySuffix)"
        if !taken.contains(normalized(stem)) { return stem }
        var number = 2
        while taken.contains(normalized("\(stem) \(number)")) {
            number += 1
        }
        return "\(stem) \(number)"
    }

    public static func index<Item>(matching query: String, in items: [Item], id: (Item) -> String, name: (Item) -> String) -> Int? {
        let needle = normalized(query)
        guard !needle.isEmpty else { return nil }
        if let exact = items.firstIndex(where: { normalized(id($0)) == needle || normalized(name($0)) == needle }) {
            return exact
        }
        let prefixed = items.indices.filter { normalized(name(items[$0])).hasPrefix(needle) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    public static func moved<Item>(_ items: [Item], from index: Int, by offset: Int) -> [Item] {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return items }
        var copy = items
        copy.insert(copy.remove(at: index), at: target)
        return copy
    }
}
