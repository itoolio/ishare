import CoreGraphics

public enum PresentationDetector {
    public static let edgeTolerance: CGFloat = 1

    public static func isPresenting(windows: [WindowDescriptor], displays: [CGRect], ownPID: Int32, ignoredBundleIDs: Set<String> = defaultIgnoredBundleIDs) -> Bool {
        windows.contains { window in
            guard window.isOnScreen, window.ownerPID != ownPID, window.layer >= 0, window.layer < 1000 else { return false }
            if let bundleID = window.ownerBundleID, ignoredBundleIDs.contains(bundleID) { return false }
            return displays.contains { covers(window.frame, display: $0) }
        }
    }

    public static func covers(_ frame: CGRect, display: CGRect) -> Bool {
        abs(frame.minX - display.minX) <= edgeTolerance && abs(frame.minY - display.minY) <= edgeTolerance
            && abs(frame.width - display.width) <= edgeTolerance && abs(frame.height - display.height) <= edgeTolerance
    }

    public static let defaultIgnoredBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.loginwindow",
    ]
}

public struct HeldResults<Item>: Sendable where Item: Sendable {
    public private(set) var items: [Item] = []

    public init() {}

    public mutating func hold(_ item: Item) {
        items.append(item)
    }

    public mutating func release() -> [Item] {
        defer { items = [] }
        return items
    }
}
