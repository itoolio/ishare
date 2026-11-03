import CoreGraphics
import Testing
@testable import ishareCore

struct OtherSpaceWindowsTests {
    let names: [Int32: String] = [1: "Safari", 2: "Xcode", 3: "ishare"]

    func window(_ id: UInt32, pid: Int32, frame: CGRect, onScreen: Bool = false, layer: Int = 0, title: String? = "Doc") -> WindowDescriptor {
        WindowDescriptor(id: id, layer: layer, frame: frame, isOnScreen: onScreen, ownerPID: pid, ownerBundleID: nil, title: title)
    }

    @Test func listsOnlyNormalWindowsThatAreNotOnTheCurrentSpace() {
        let windows = OtherSpaceWindows.windows(
            in: [
                window(1, pid: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
                window(2, pid: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), onScreen: true),
                window(3, pid: 2, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 3),
                window(4, pid: 2, frame: CGRect(x: 0, y: 0, width: 50, height: 600)),
                window(5, pid: 3, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
            ], names: names, displaySizes: [], ownPID: 3)
        #expect(windows.map(\.id) == [1])
    }

    @Test func putsFullScreenAppsFirstAndMarksThem() {
        let windows = OtherSpaceWindows.windows(
            in: [
                window(1, pid: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), title: "Docs"),
                window(2, pid: 2, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), title: "Project"),
            ], names: names, displaySizes: [CGSize(width: 1512, height: 982)], ownPID: 99)
        #expect(windows.map(\.id) == [2, 1])
        #expect(windows[0].menuTitle == "Xcode — Project ⤢")
        #expect(windows[1].menuTitle == "Safari — Docs")
    }

    @Test func sortsByAppThenTitle() {
        let windows = OtherSpaceWindows.windows(
            in: [
                window(1, pid: 2, frame: CGRect(x: 0, y: 0, width: 800, height: 600), title: "B"),
                window(2, pid: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), title: "Z"),
                window(3, pid: 2, frame: CGRect(x: 0, y: 0, width: 800, height: 600), title: "A"),
            ], names: names, displaySizes: [], ownPID: 99)
        #expect(windows.map(\.id) == [2, 3, 1])
    }
}
