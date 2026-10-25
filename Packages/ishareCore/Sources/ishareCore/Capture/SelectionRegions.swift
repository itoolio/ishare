import CoreGraphics
import Foundation

public struct SelectionRegion: Hashable, Sendable, Identifiable {
    public let id: Int
    public var displayID: UInt32
    public var rect: CGRect

    public init(id: Int, displayID: UInt32, rect: CGRect) {
        self.id = id
        self.displayID = displayID
        self.rect = rect
    }
}

public struct SelectionRegionList: Hashable, Sendable {
    public private(set) var regions: [SelectionRegion] = []
    private var nextID = 1
    public static let maximumCount = 50

    public init() {}

    public var isEmpty: Bool { regions.isEmpty }
    public var count: Int { regions.count }

    @discardableResult
    public mutating func add(_ rect: CGRect, displayID: UInt32) -> SelectionRegion? {
        guard ScreenGeometry.isMeaningfulSelection(rect), regions.count < Self.maximumCount else { return nil }
        let region = SelectionRegion(id: nextID, displayID: displayID, rect: rect)
        nextID += 1
        regions.append(region)
        return region
    }

    @discardableResult
    public mutating func remove(id: Int) -> SelectionRegion? {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return nil }
        return regions.remove(at: index)
    }

    public mutating func removeAll() {
        regions.removeAll()
    }

    @discardableResult
    public mutating func move(id: Int, by delta: CGVector, within bounds: CGRect) -> SelectionRegion? {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return nil }
        regions[index].rect = ScreenGeometry.moved(regions[index].rect, by: delta, within: bounds)
        return regions[index]
    }

    public func number(of id: Int) -> Int? {
        regions.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    public func region(at point: CGPoint, displayID: UInt32) -> SelectionRegion? {
        regions.last { $0.displayID == displayID && $0.rect.contains(point) }
    }

    public func regions(onDisplay displayID: UInt32) -> [SelectionRegion] {
        regions.filter { $0.displayID == displayID }
    }

    public var displayIDs: [UInt32] {
        var seen = Set<UInt32>()
        return regions.map(\.displayID).filter { seen.insert($0).inserted }
    }
}

public enum MultiRegionResult: String, Codable, Sendable, CaseIterable {
    case combined
    case separate
}

public enum MultiRegionPolicy {
    public static func keepsSelection(keepModifierHeld: Bool, toggleEnabled: Bool, hasKeptRegions: Bool, allowsMultiple: Bool) -> Bool {
        allowsMultiple && (keepModifierHeld || toggleEnabled || hasKeptRegions)
    }

    public static func finalRegions(kept: [SelectionRegion], pending: SelectionRegion?) -> [SelectionRegion] {
        guard let pending, ScreenGeometry.isMeaningfulSelection(pending.rect) else { return kept }
        return kept + [pending]
    }
}
