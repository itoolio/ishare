import Foundation

struct HistoryDaySection: Identifiable, Equatable, Sendable {
    enum Day: Hashable, Sendable {
        case date(Date)
        case undated
    }

    let day: Day
    let title: String
    let items: [HistoryItem]

    var id: Day { day }
}

enum HistoryTimeline {
    static func sections(
        for items: [HistoryItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        localize: (String) -> String = { $0.localized() }
    ) -> [HistoryDaySection] {
        var order: [HistoryDaySection.Day] = []
        var grouped: [HistoryDaySection.Day: [HistoryItem]] = [:]
        for item in items {
            let day: HistoryDaySection.Day = item.date.map { .date(calendar.startOfDay(for: $0)) } ?? .undated
            if grouped[day] == nil {
                order.append(day)
            }
            grouped[day, default: []].append(item)
        }
        let sorted = order.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (.date(a), .date(b)): a > b
            case (.date, .undated): true
            case (.undated, _): false
            }
        }
        return sorted.map { day in
            HistoryDaySection(day: day, title: title(for: day, now: now, calendar: calendar, locale: locale, localize: localize), items: grouped[day] ?? [])
        }
    }

    static func title(for day: HistoryDaySection.Day, now: Date, calendar: Calendar, locale: Locale, localize: (String) -> String) -> String {
        guard case let .date(date) = day else { return localize("Undated") }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: date, to: today).day ?? 0
        switch days {
        case 0: return localize("Today")
        case 1: return localize("Yesterday")
        case 2 ..< 7:
            var style = Date.FormatStyle.dateTime.weekday(.wide)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style.locale(locale))
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            var style = sameYear ? Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day() : Date.FormatStyle.dateTime.month(.abbreviated).day().year()
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style.locale(locale))
        }
    }
}

struct HistorySelection: Equatable, Sendable {
    enum Modifier: Sendable {
        case none
        case toggle
        case extend
    }

    private(set) var selected: Set<HistoryItem> = []
    private(set) var anchor: HistoryItem?

    var isEmpty: Bool { selected.isEmpty }
    var count: Int { selected.count }

    func contains(_ item: HistoryItem) -> Bool {
        selected.contains(item)
    }

    func ordered(in items: [HistoryItem]) -> [HistoryItem] {
        items.filter(selected.contains)
    }

    mutating func click(_ item: HistoryItem, modifier: Modifier, in items: [HistoryItem]) {
        switch modifier {
        case .none:
            selected = [item]
            anchor = item
        case .toggle:
            if selected.remove(item) == nil {
                selected.insert(item)
            }
            anchor = item
        case .extend:
            guard let anchor, let start = items.firstIndex(of: anchor), let end = items.firstIndex(of: item) else {
                selected = [item]
                self.anchor = item
                return
            }
            selected.formUnion(items[min(start, end) ... max(start, end)])
        }
    }

    mutating func selectAll(_ items: [HistoryItem]) {
        selected = Set(items)
        anchor = items.first
    }

    mutating func clear() {
        selected = []
        anchor = nil
    }

    mutating func retain(_ items: [HistoryItem]) {
        selected.formIntersection(items)
        if let anchor, !selected.contains(anchor) {
            self.anchor = nil
        }
    }

    static func links(for items: [HistoryItem]) -> [String] {
        items.compactMap { $0.fileUrl?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
