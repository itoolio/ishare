import CoreGraphics
import Testing
@testable import ishareCore

struct ChildWindowPlanTests {
    let main = WindowDescriptor(id: 1, layer: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 600), ownerPID: 10, ownerBundleID: "app")

    @Test func findsSheetsAndPopoversOfTheSameApp() {
        let sheet = WindowDescriptor(id: 2, layer: 0, frame: CGRect(x: 300, y: 120, width: 400, height: 300), ownerPID: 10, ownerBundleID: "app")
        let popover = WindowDescriptor(id: 3, layer: 101, frame: CGRect(x: 880, y: 200, width: 200, height: 150), ownerPID: 10, ownerBundleID: "app")
        let otherApp = WindowDescriptor(id: 4, layer: 0, frame: CGRect(x: 300, y: 120, width: 400, height: 300), ownerPID: 11, ownerBundleID: "other")
        let farAway = WindowDescriptor(id: 5, layer: 0, frame: CGRect(x: 2000, y: 1200, width: 400, height: 300), ownerPID: 10, ownerBundleID: "app")
        let desktop = WindowDescriptor(id: 6, layer: 0, frame: CGRect(x: 0, y: 0, width: 5000, height: 4000), ownerPID: 10, ownerBundleID: "app")
        #expect(ChildWindowPlan.related(to: main, in: [main, sheet, popover, otherApp, farAway, desktop]).map(\.id) == [2, 3])
    }

    @Test func coversEveryWindowAndTheShadow() {
        let rect = ChildWindowPlan.captureRect(
            main: main.frame, related: [CGRect(x: 880, y: 200, width: 200, height: 150)], within: CGRect(x: 0, y: 0, width: 1512, height: 982), includesShadow: true)
        #expect(rect == CGRect(x: 60, y: 60, width: 1060, height: 680))
    }
}
