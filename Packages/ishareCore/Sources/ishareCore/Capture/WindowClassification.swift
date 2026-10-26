import CoreGraphics
import Foundation

public struct WindowDescriptor: Hashable, Sendable {
    public var id: UInt32
    public var layer: Int
    public var frame: CGRect
    public var isOnScreen: Bool
    public var ownerPID: Int32?
    public var ownerBundleID: String?
    public var title: String?

    public init(id: UInt32, layer: Int, frame: CGRect, isOnScreen: Bool = true, ownerPID: Int32?, ownerBundleID: String?, title: String? = nil) {
        self.id = id
        self.layer = layer
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.ownerPID = ownerPID
        self.ownerBundleID = ownerBundleID
        self.title = title
    }
}

public enum WindowKind: String, Hashable, Sendable {
    case standard
    case popup
}

public struct ClassifiedWindow: Hashable, Sendable {
    public var descriptor: WindowDescriptor
    public var kind: WindowKind

    public init(descriptor: WindowDescriptor, kind: WindowKind) {
        self.descriptor = descriptor
        self.kind = kind
    }
}

public struct WindowClassifier: Sendable {
    public static let floatingLayer = 3
    public static let modalPanelLayer = 8
    public static let statusLayer = 25
    public static let popUpMenuLayer = 101
    public static let overlayLayer = 102
    public static let helpLayer = 200

    public static let popupLayers: Set<Int> = [floatingLayer, modalPanelLayer, statusLayer, popUpMenuLayer, overlayLayer, helpLayer]
    public static let systemBundleIDs: Set<String> = [
        "com.apple.dock", "com.apple.notificationcenterui", "com.apple.wallpaper.agent", "com.apple.WindowManager", "com.apple.screencaptureui",
    ]
    public static let minimumStandardSide: CGFloat = 40
    public static let minimumPopupSide: CGFloat = 10
    public static let fullScreenCoverage: CGFloat = 0.9

    public var ownBundleID: String?
    public var ignoredBundleIDs: Set<String>
    public var displayFrames: [CGRect]
    public var menuBarStrips: [CGRect]

    public init(ownBundleID: String?, ignoredBundleIDs: Set<String> = [], displayFrames: [CGRect] = [], menuBarStrips: [CGRect] = []) {
        self.ownBundleID = ownBundleID
        self.ignoredBundleIDs = ignoredBundleIDs
        self.displayFrames = displayFrames
        self.menuBarStrips = menuBarStrips
    }

    public func kind(of window: WindowDescriptor) -> WindowKind? {
        guard window.isOnScreen, window.ownerPID != nil, let bundleID = window.ownerBundleID, !isExcluded(bundleID) else { return nil }
        if window.layer == 0 {
            let side = Self.minimumStandardSide
            return window.frame.width >= side && window.frame.height >= side ? .standard : nil
        }
        guard Self.popupLayers.contains(window.layer),
            window.frame.width >= Self.minimumPopupSide, window.frame.height >= Self.minimumPopupSide,
            !isInMenuBar(window.frame), !coversDisplay(window.frame)
        else { return nil }
        return .popup
    }

    public func classify(_ windows: [WindowDescriptor]) -> [ClassifiedWindow] {
        windows.compactMap { window in kind(of: window).map { ClassifiedWindow(descriptor: window, kind: $0) } }
    }

    private func isExcluded(_ bundleID: String) -> Bool {
        bundleID == ownBundleID || ignoredBundleIDs.contains(bundleID) || Self.systemBundleIDs.contains(bundleID)
    }

    private func isInMenuBar(_ frame: CGRect) -> Bool {
        menuBarStrips.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) }
    }

    private func coversDisplay(_ frame: CGRect) -> Bool {
        displayFrames.contains { display in
            let overlap = display.intersection(frame)
            guard !overlap.isNull, display.width > 0, display.height > 0 else { return false }
            return overlap.width * overlap.height >= display.width * display.height * Self.fullScreenCoverage
        }
    }

    public static func menuBarStrip(forDisplay frame: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0, height))
    }

    public static func preferredIndex(at point: CGPoint, in windows: [ClassifiedWindow]) -> Int? {
        windows.firstIndex { $0.kind == .popup && $0.descriptor.frame.contains(point) }
            ?? windows.firstIndex { $0.descriptor.frame.contains(point) }
    }

    public static func menuTarget(at pointer: CGPoint, in windows: [ClassifiedWindow]) -> Int? {
        windows.firstIndex { $0.kind == .popup && $0.descriptor.frame.contains(pointer) }
            ?? windows.firstIndex { $0.kind == .popup && $0.descriptor.layer == popUpMenuLayer }
            ?? windows.firstIndex { $0.kind == .popup }
    }

    public static func relatedPopups(of index: Int, in windows: [ClassifiedWindow], tolerance: CGFloat = 4) -> [Int] {
        guard windows.indices.contains(index), windows[index].kind == .popup else { return [] }
        let owner = windows[index].descriptor.ownerPID
        let candidates = windows.indices.filter { windows[$0].kind == .popup && windows[$0].descriptor.ownerPID == owner }
        var included: Set<Int> = [index]
        var frontier = [index]
        while let current = frontier.popLast() {
            let frame = windows[current].descriptor.frame.insetBy(dx: -tolerance, dy: -tolerance)
            for candidate in candidates where !included.contains(candidate) && frame.intersects(windows[candidate].descriptor.frame) {
                included.insert(candidate)
                frontier.append(candidate)
            }
        }
        return included.sorted()
    }

    public static func parentWindow(of index: Int, in windows: [ClassifiedWindow]) -> Int? {
        guard windows.indices.contains(index) else { return nil }
        let popup = windows[index].descriptor
        let sameOwner = windows.indices.filter { windows[$0].kind == .standard && windows[$0].descriptor.ownerPID == popup.ownerPID }
        return sameOwner.first { windows[$0].descriptor.frame.intersects(popup.frame) } ?? sameOwner.first
    }

    public static func captureBounds(of frames: [CGRect], shadowMargin: CGFloat, within display: CGRect) -> CGRect? {
        guard let first = frames.first else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let expanded = union.insetBy(dx: -shadowMargin, dy: -shadowMargin)
        let clamped = expanded.intersection(display)
        return clamped.isNull || clamped.isEmpty ? nil : clamped
    }
}
