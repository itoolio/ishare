import CoreGraphics
import Testing
@testable import ishareCore

struct AppWindowsPlanTests {
    private func window(_ id: UInt32, pid: Int32, frame: CGRect, layer: Int = 0, bundle: String? = "com.example") -> WindowDescriptor {
        WindowDescriptor(id: id, layer: layer, frame: frame, ownerPID: pid, ownerBundleID: bundle)
    }

    @Test func picksTheAppsNormalWindowsInReadingOrder() {
        let windows = [
            window(1, pid: 10, frame: CGRect(x: 500, y: 0, width: 400, height: 300)),
            window(2, pid: 10, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
            window(3, pid: 10, frame: CGRect(x: 0, y: 400, width: 400, height: 300)),
            window(4, pid: 10, frame: CGRect(x: 0, y: 0, width: 20, height: 20)),
            window(5, pid: 10, frame: CGRect(x: 0, y: 0, width: 300, height: 300), layer: 101),
            window(6, pid: 11, frame: CGRect(x: 0, y: 0, width: 300, height: 300)),
        ]
        #expect(AppWindowsPlan.windows(of: 10, in: windows).map(\.id) == [2, 1, 3])
    }

    @Test func listsEachOtherAppOnceAlphabetically() {
        let windows = [
            window(1, pid: 20, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
            window(2, pid: 10, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
            window(3, pid: 20, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
            window(4, pid: 7, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
        ]
        let apps = AppWindowsPlan.apps(in: windows, names: [20: "Safari", 10: "Notes", 7: "ishare"], ownPID: 7)
        #expect(apps.map(\.appName) == ["Notes", "Safari"])
    }

    @Test func contactSheetsAreRoughlySquare() {
        #expect([1, 2, 4, 5, 9, 10].map(AppWindowsPlan.contactSheetColumns(for:)) == [1, 2, 2, 3, 3, 4])
    }
}

struct AppWindowsMatchTests {
    let apps = [
        AppWindowCandidate(ownerPID: 1, appName: "Safari", bundleID: "com.apple.Safari"),
        AppWindowCandidate(ownerPID: 2, appName: "Safari Technology Preview", bundleID: "com.apple.SafariTechnologyPreview"),
        AppWindowCandidate(ownerPID: 3, appName: "Xcode", bundleID: "com.apple.dt.Xcode"),
    ]

    @Test func prefersTheFrontmostAppWithoutAName() {
        #expect(AppWindowsPlan.match(nil, in: apps, frontmostPID: 3)?.ownerPID == 3)
        #expect(AppWindowsPlan.match(" ", in: apps, frontmostPID: 99)?.ownerPID == 1)
    }

    @Test func matchesExactNamesAndBundleIdentifiersBeforePartialNames() {
        #expect(AppWindowsPlan.match("safari", in: apps, frontmostPID: nil)?.ownerPID == 1)
        #expect(AppWindowsPlan.match("com.apple.SafariTechnologyPreview", in: apps, frontmostPID: nil)?.ownerPID == 2)
        #expect(AppWindowsPlan.match("technology", in: apps, frontmostPID: nil)?.ownerPID == 2)
        #expect(AppWindowsPlan.match("Finder", in: apps, frontmostPID: nil) == nil)
    }
}
