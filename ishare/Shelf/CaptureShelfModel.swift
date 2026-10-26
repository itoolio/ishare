import CoreGraphics
import Defaults
import Foundation

enum CaptureShelfMode: String, CaseIterable, Identifiable, Codable, Sendable, Defaults.Serializable {
    case off
    case afterCapture
    case onDemand

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .afterCapture: "Show after capture"
        case .onDemand: "Only from the shortcut and menu"
        }
    }

    var collectsCaptures: Bool { self != .off }
    var showsAfterCapture: Bool { self == .afterCapture }
}

enum CaptureShelfItemKind: String, Codable, Sendable {
    case image
    case video
    case other

    init(fileExtension: String) {
        switch HistoryItemKind(fileExtension: fileExtension) {
        case .image: self = .image
        case .video: self = .video
        case .other: self = .other
        }
    }

    var postCaptureKind: PostCapture.Kind {
        self == .image ? .image : .video
    }
}

struct CaptureShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var fileURL: URL
    let sourceKey: String
    let kind: CaptureShelfItemKind
    let addedAt: Date
    var link: String?

    init(id: UUID = UUID(), fileURL: URL, sourceKey: String? = nil, kind: CaptureShelfItemKind? = nil, addedAt: Date = Date(), link: String? = nil) {
        self.id = id
        self.fileURL = fileURL
        self.sourceKey = sourceKey ?? CaptureShelfItem.key(for: fileURL)
        self.kind = kind ?? CaptureShelfItemKind(fileExtension: fileURL.pathExtension)
        self.addedAt = addedAt
        self.link = link
    }

    var fileName: String { fileURL.lastPathComponent }

    static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    func matches(key: String) -> Bool {
        sourceKey == key || CaptureShelfItem.key(for: fileURL) == key
    }
}

struct CaptureShelfInsertion: Equatable, Sendable {
    var inserted: [CaptureShelfItem] = []
    var duplicates: [CaptureShelfItem] = []
    var evicted: [CaptureShelfItem] = []
}

struct CaptureShelfState: Equatable, Sendable {
    static let defaultCapacity = 24

    private(set) var items: [CaptureShelfItem] = []
    let capacity: Int

    init(items: [CaptureShelfItem] = [], capacity: Int = CaptureShelfState.defaultCapacity) {
        self.capacity = max(1, capacity)
        self.items = []
        _ = insert(items.reversed())
    }

    var isEmpty: Bool { items.isEmpty }

    @discardableResult
    mutating func insert(_ newItems: [CaptureShelfItem]) -> CaptureShelfInsertion {
        var result = CaptureShelfInsertion()
        for item in newItems {
            if let index = items.firstIndex(where: { $0.matches(key: item.sourceKey) || $0.matches(key: CaptureShelfItem.key(for: item.fileURL)) }) {
                let existing = items.remove(at: index)
                items.insert(existing, at: 0)
                if existing.id != item.id {
                    result.duplicates.append(item)
                }
                continue
            }
            items.insert(item, at: 0)
            result.inserted.append(item)
        }
        if items.count > capacity {
            result.evicted = Array(items[capacity...])
            items.removeLast(items.count - capacity)
            let evictedIDs = Set(result.evicted.map(\.id))
            result.inserted.removeAll { evictedIDs.contains($0.id) }
        }
        return result
    }

    @discardableResult
    mutating func remove(_ ids: Set<UUID>) -> [CaptureShelfItem] {
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        return removed
    }

    @discardableResult
    mutating func clear() -> [CaptureShelfItem] {
        defer { items = [] }
        return items
    }

    mutating func update(_ id: UUID, _ change: (inout CaptureShelfItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    func item(_ id: UUID) -> CaptureShelfItem? {
        items.first { $0.id == id }
    }

    func dragItems(startingAt id: UUID, selection: Set<UUID>) -> [CaptureShelfItem] {
        guard selection.contains(id), selection.count > 1 else { return items.filter { $0.id == id } }
        return items.filter { selection.contains($0.id) }
    }
}

struct CaptureShelfSelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []
    private var anchor: UUID?

    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    mutating func click(_ id: UUID, extending: Bool, toggling: Bool, in items: [CaptureShelfItem]) {
        if extending, let anchor, let from = items.firstIndex(where: { $0.id == anchor }), let to = items.firstIndex(where: { $0.id == id }) {
            ids = Set(items[min(from, to) ... max(from, to)].map(\.id))
            return
        }
        if toggling {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        } else {
            ids = [id]
        }
        anchor = id
    }

    mutating func retain(_ items: [CaptureShelfItem]) {
        let present = Set(items.map(\.id))
        ids.formIntersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
    }

    mutating func clear() {
        ids = []
        anchor = nil
    }
}

enum CaptureShelfEdge: String, Codable, Sendable {
    case leading
    case trailing
}

struct CaptureShelfPlacement: Codable, Equatable, Sendable, Defaults.Serializable {
    var edge: CaptureShelfEdge
    var offset: Double

    static let standard = CaptureShelfPlacement(edge: .trailing, offset: 0.5)
}

enum CaptureShelfGeometry {
    static let margin: CGFloat = 12
    static let width: CGFloat = 132
    static let headerHeight: CGFloat = 40
    static let itemHeight: CGFloat = 92
    static let itemSpacing: CGFloat = 8
    static let emptyHeight: CGFloat = 150

    static func contentHeight(itemCount: Int, in visibleFrame: CGRect) -> CGFloat {
        let items = itemCount == 0 ? emptyHeight : CGFloat(itemCount) * itemHeight + CGFloat(max(0, itemCount - 1)) * itemSpacing + itemSpacing * 2
        return min(headerHeight + items, max(headerHeight + itemHeight, visibleFrame.height - margin * 2))
    }

    static func frame(size: CGSize, placement: CaptureShelfPlacement, in visibleFrame: CGRect) -> CGRect {
        let x = placement.edge == .leading ? visibleFrame.minX + margin : visibleFrame.maxX - margin - size.width
        let travel = max(0, visibleFrame.height - margin * 2 - size.height)
        let offset = min(1, max(0, placement.offset))
        let y = visibleFrame.maxY - margin - size.height - travel * offset
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    static func placement(for frame: CGRect, in visibleFrame: CGRect) -> CaptureShelfPlacement {
        let edge: CaptureShelfEdge = frame.midX < visibleFrame.midX ? .leading : .trailing
        let travel = visibleFrame.height - margin * 2 - frame.height
        guard travel > 0 else { return CaptureShelfPlacement(edge: edge, offset: 0) }
        let offset = (visibleFrame.maxY - margin - frame.maxY) / travel
        return CaptureShelfPlacement(edge: edge, offset: Double(min(1, max(0, offset))))
    }

    static func screenKey(displayUUID: String?, localizedName: String, frame: CGRect) -> String {
        displayUUID ?? "\(localizedName)-\(Int(frame.width))x\(Int(frame.height))"
    }
}
