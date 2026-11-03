import CoreGraphics
import Testing
@testable import ishareCore

struct PresentationDetectorTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func detectsAnotherAppCoveringAWholeDisplay() {
        let keynote = WindowDescriptor(id: 1, layer: 0, frame: display, ownerPID: 42, ownerBundleID: "com.apple.iWork.Keynote")
        #expect(PresentationDetector.isPresenting(windows: [keynote], displays: [display], ownPID: 7))
    }

    @Test func ignoresOrdinaryWindowsDesktopAndOwnWindows() {
        let small = WindowDescriptor(id: 1, layer: 0, frame: CGRect(x: 10, y: 40, width: 800, height: 600), ownerPID: 42, ownerBundleID: "com.example.app")
        let finderDesktop = WindowDescriptor(id: 2, layer: 0, frame: display, ownerPID: 50, ownerBundleID: "com.apple.finder")
        let own = WindowDescriptor(id: 3, layer: 0, frame: display, ownerPID: 7, ownerBundleID: "dev.adrian.ishare")
        let wallpaper = WindowDescriptor(id: 4, layer: -2_147_483_624, frame: display, ownerPID: 60, ownerBundleID: "com.apple.wallpaper")
        #expect(!PresentationDetector.isPresenting(windows: [small, finderDesktop, own, wallpaper], displays: [display], ownPID: 7))
    }

    @Test func toleratesOnePointOfRounding() {
        #expect(PresentationDetector.covers(CGRect(x: 0.5, y: 0, width: 1511.5, height: 982), display: display))
        #expect(!PresentationDetector.covers(CGRect(x: 0, y: 25, width: 1512, height: 957), display: display))
    }

    @Test func heldResultsAreReleasedInOrderOnce() {
        var held = HeldResults<Int>()
        held.hold(1)
        held.hold(2)
        #expect(held.release() == [1, 2])
        #expect(held.release().isEmpty)
    }
}
