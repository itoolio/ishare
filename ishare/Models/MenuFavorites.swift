import Defaults
import Foundation

struct MenuFavorites: Equatable, Sendable {
    static let limit = 6

    private(set) var ids: [String]

    init(_ ids: [String] = []) {
        self.ids = Self.normalized(ids)
    }

    static func normalized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return Array(ids.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(limit))
    }

    var isFull: Bool { ids.count >= Self.limit }
    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func canPin(_ id: String) -> Bool {
        !contains(id) && !isFull
    }

    func pinning(_ id: String) -> MenuFavorites {
        guard canPin(id) else { return self }
        return MenuFavorites(ids + [id])
    }

    func unpinning(_ id: String) -> MenuFavorites {
        MenuFavorites(ids.filter { $0 != id })
    }

    func toggling(_ id: String) -> MenuFavorites {
        contains(id) ? unpinning(id) : pinning(id)
    }

    func moving(_ id: String, by offset: Int) -> MenuFavorites {
        guard let index = ids.firstIndex(of: id) else { return self }
        let destination = min(max(index + offset, 0), ids.count - 1)
        guard destination != index else { return self }
        var reordered = ids
        reordered.remove(at: index)
        reordered.insert(id, at: destination)
        return MenuFavorites(reordered)
    }

    func resolved<Command>(in commands: [Command], id: (Command) -> String) -> [Command] {
        let byID = Dictionary(commands.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    @MainActor static var current: MenuFavorites {
        get { MenuFavorites(Defaults[.menuFavorites]) }
        set { Defaults[.menuFavorites] = newValue.ids }
    }
}

enum MenuFavoriteCommandID {
    static func capture(_ index: Int) -> String? {
        ["capture.region", "capture.window", "capture.screen", "capture.scrolling"][safe: index]
    }

    static func record(_ index: Int, gif: Bool) -> String {
        switch (index, gif) {
        case (0, false): "record.screen"
        case (0, true): "record.gif"
        case (_, false): "record.region"
        case (_, true): "record.regionGif"
        }
    }

    static func footer(_ index: Int) -> String {
        index == 0 ? "editor.open" : "upload.clipboard"
    }

    static let history = "history.open"
}

enum MenuSectionDrag {
    static let prefix = "ishare.menu-section:"

    static func payload(for section: MenuSection) -> String {
        prefix + section.rawValue
    }

    static func section(from payload: String) -> MenuSection? {
        guard payload.hasPrefix(prefix) else { return nil }
        return MenuSection(rawValue: String(payload.dropFirst(prefix.count)))
    }
}

extension MenuLayout {
    func moving(_ section: MenuSection, onto target: MenuSection) -> MenuLayout {
        guard section != target, let from = order.firstIndex(of: section), let to = order.firstIndex(of: target) else { return self }
        return moving(section, by: to - from)
    }
}
