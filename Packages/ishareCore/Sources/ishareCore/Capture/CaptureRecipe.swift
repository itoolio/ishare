import CoreGraphics
import Foundation

public enum CaptureRecipe: Codable, Hashable, Sendable {
    case region(displayID: UInt32, rect: CGRect)
    case window(windowID: UInt32, bundleID: String?, title: String?)
    case screen(displayID: UInt32)
    case allDisplays
    case appWindows(bundleID: String, contactSheet: Bool)
    case webPage(address: String, width: CGFloat, pdf: Bool, dismissesCookieBanners: Bool)

    public var kind: String {
        switch self {
        case .region: "region"
        case .window: "window"
        case .screen: "screen"
        case .allDisplays: "displays"
        case .appWindows: "app"
        case .webPage: "web"
        }
    }

    public static func windowMatch(
        _ recipeID: UInt32, bundleID: String?, title: String?, among windows: [(id: UInt32, bundleID: String?, title: String?)]
    ) -> UInt32? {
        if windows.contains(where: { $0.id == recipeID }) { return recipeID }
        let sameApp = windows.filter { bundleID != nil && $0.bundleID == bundleID }
        return (sameApp.first { $0.title == title } ?? sameApp.first)?.id
    }
}
