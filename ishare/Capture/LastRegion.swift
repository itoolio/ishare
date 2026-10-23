import AppKit
import Defaults
import Foundation
import ishareCore

struct StoredRegion: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var savedAt: Date

    init(rect: CGRect, savedAt: Date) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
        self.savedAt = savedAt
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct LastRegions: Codable, Hashable, Sendable, Defaults.Serializable {
    var regions: [String: StoredRegion] = [:]

    mutating func remember(_ rect: CGRect, forDisplay key: String, at date: Date = .now) {
        guard ScreenGeometry.isMeaningfulSelection(rect) else { return }
        regions[key] = StoredRegion(rect: rect.integral, savedAt: date)
    }

    func region(forDisplay key: String, within bounds: CGRect) -> CGRect? {
        guard let stored = regions[key] else { return nil }
        let clamped = ScreenGeometry.clamp(stored.rect, to: bounds)
        return ScreenGeometry.isMeaningfulSelection(clamped) ? clamped : nil
    }

    func mostRecentDisplay(among keys: [String]) -> String? {
        keys.compactMap { key in regions[key].map { (key, $0.savedAt) } }
            .max { $0.1 < $1.1 }?
            .0
    }
}

@MainActor
enum LastRegionStore {
    static func key(for displayID: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return "display-\(displayID)" }
        return string
    }

    static func localBounds(of displayID: CGDirectDisplayID) -> CGRect {
        CGRect(origin: .zero, size: CGDisplayBounds(displayID).size)
    }

    static func remember(_ rect: CGRect, for displayID: CGDirectDisplayID) {
        Defaults[.lastCaptureRegions].remember(rect, forDisplay: key(for: displayID))
    }

    static func region(for displayID: CGDirectDisplayID) -> CGRect? {
        Defaults[.lastCaptureRegions].region(forDisplay: key(for: displayID), within: localBounds(of: displayID))
    }

    static func regions(for displayIDs: [CGDirectDisplayID]) -> [CGDirectDisplayID: CGRect] {
        var result: [CGDirectDisplayID: CGRect] = [:]
        for displayID in displayIDs {
            result[displayID] = region(for: displayID)
        }
        return result
    }

    static func preferredDisplay(among displayIDs: [CGDirectDisplayID], underMouse: CGDirectDisplayID?) -> CGDirectDisplayID? {
        if let underMouse, displayIDs.contains(underMouse), region(for: underMouse) != nil {
            return underMouse
        }
        let keys = displayIDs.map { ($0, key(for: $0)) }
        guard let recent = Defaults[.lastCaptureRegions].mostRecentDisplay(among: keys.map(\.1)) else { return nil }
        return keys.first { $0.1 == recent }?.0
    }
}
