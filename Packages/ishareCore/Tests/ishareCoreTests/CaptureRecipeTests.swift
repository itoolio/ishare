import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct CaptureRecipeTests {
    @Test func survivesBeingSaved() throws {
        let recipes: [CaptureRecipe] = [
            .region(displayID: 1, rect: CGRect(x: 10, y: 20, width: 300, height: 200)), .window(windowID: 7, bundleID: "com.apple.Safari", title: "Docs"),
            .screen(displayID: 2), .allDisplays, .appWindows(bundleID: "com.apple.dt.Xcode", contactSheet: true),
            .webPage(address: "example.com", width: 1024, pdf: true, dismissesCookieBanners: false),
        ]
        let decoded = try JSONDecoder().decode([CaptureRecipe].self, from: JSONEncoder().encode(recipes))
        #expect(decoded == recipes)
        #expect(recipes.map(\.kind) == ["region", "window", "screen", "displays", "app", "web"])
    }

    @Test func findsTheSameWindowAgainOrOneFromTheSameApp() {
        let windows: [(id: UInt32, bundleID: String?, title: String?)] = [(3, "com.apple.Safari", "Mail"), (4, "com.apple.Safari", "Docs"), (5, "com.apple.Notes", nil)]
        #expect(CaptureRecipe.windowMatch(5, bundleID: "com.apple.Notes", title: nil, among: windows) == 5)
        #expect(CaptureRecipe.windowMatch(9, bundleID: "com.apple.Safari", title: "Docs", among: windows) == 4)
        #expect(CaptureRecipe.windowMatch(9, bundleID: "com.apple.Safari", title: "Gone", among: windows) == 3)
        #expect(CaptureRecipe.windowMatch(9, bundleID: "com.apple.Xcode", title: nil, among: windows) == nil)
    }
}
