import CoreGraphics
import Foundation

public enum AppWindowsResult: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case separate
    case contactSheet

    public var id: Self { self }
}

public struct AppWindowCandidate: Hashable, Sendable {
    public var ownerPID: Int32
    public var appName: String
    public var bundleID: String?

    public init(ownerPID: Int32, appName: String, bundleID: String?) {
        self.ownerPID = ownerPID
        self.appName = appName
        self.bundleID = bundleID
    }
}

public enum AppWindowsPlan {
    public static func windows(of pid: Int32, in windows: [WindowDescriptor]) -> [WindowDescriptor] {
        windows
            .filter { $0.ownerPID == pid && $0.layer == 0 && $0.isOnScreen && $0.frame.width >= 40 && $0.frame.height >= 40 }
            .sorted { first, second in
                first.frame.minY == second.frame.minY ? first.frame.minX < second.frame.minX : first.frame.minY < second.frame.minY
            }
    }

    public static func apps(in windows: [WindowDescriptor], names: [Int32: String], ownPID: Int32) -> [AppWindowCandidate] {
        var seen = Set<Int32>()
        return windows.compactMap { window in
            guard let pid = window.ownerPID, pid != ownPID, window.layer == 0, window.isOnScreen, let name = names[pid], seen.insert(pid).inserted else { return nil }
            return AppWindowCandidate(ownerPID: pid, appName: name, bundleID: window.ownerBundleID)
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    public static func match(_ query: String?, in apps: [AppWindowCandidate], frontmostPID: Int32?) -> AppWindowCandidate? {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return apps.first { $0.ownerPID == frontmostPID } ?? apps.first
        }
        return apps.first { $0.appName.caseInsensitiveCompare(query) == .orderedSame || $0.bundleID?.caseInsensitiveCompare(query) == .orderedSame }
            ?? apps.first { $0.appName.localizedCaseInsensitiveContains(query) }
    }

    public static func contactSheetColumns(for count: Int) -> Int {
        guard count > 1 else { return 1 }
        return Int(Double(count).squareRoot().rounded(.up))
    }
}
