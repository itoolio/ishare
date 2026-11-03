import CoreGraphics
import Foundation

public struct OtherSpaceWindow: Hashable, Sendable {
    public var id: UInt32
    public var appName: String
    public var title: String
    public var isFullScreen: Bool

    public var menuTitle: String {
        let label = title.isEmpty ? appName : "\(appName) — \(title)"
        return isFullScreen ? "\(label) ⤢" : label
    }
}

public enum OtherSpaceWindows {
    public static let minimumSide: CGFloat = 120

    public static func windows(in descriptors: [WindowDescriptor], names: [Int32: String], displaySizes: [CGSize], ownPID: Int32) -> [OtherSpaceWindow] {
        descriptors
            .compactMap { window -> OtherSpaceWindow? in
                guard let pid = window.ownerPID, pid != ownPID, window.layer == 0, !window.isOnScreen,
                    window.frame.width >= minimumSide, window.frame.height >= minimumSide, let name = names[pid]
                else { return nil }
                let isFullScreen = displaySizes.contains { abs($0.width - window.frame.width) < 1 && abs($0.height - window.frame.height) < 1 }
                return OtherSpaceWindow(id: window.id, appName: name, title: window.title ?? "", isFullScreen: isFullScreen)
            }
            .sorted { first, second in
                if first.isFullScreen != second.isFullScreen { return first.isFullScreen }
                let byApp = first.appName.localizedCaseInsensitiveCompare(second.appName)
                return byApp == .orderedSame ? first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending : byApp == .orderedAscending
            }
    }
}
