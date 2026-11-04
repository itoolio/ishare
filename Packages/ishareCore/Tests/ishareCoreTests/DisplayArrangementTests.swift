import CoreGraphics
import Testing
@testable import ishareCore

struct DisplayArrangementTests {
    @Test func placesDisplaysWhereTheyAreArranged() throws {
        let frames: [(id: UInt32, frame: CGRect)] = [(1, CGRect(x: 0, y: 0, width: 1440, height: 900)), (2, CGRect(x: 1440, y: -180, width: 1920, height: 1080))]
        let layout = try #require(DisplayArrangement.layout(frames: frames, scale: 2))
        #expect(layout.pixelSize == CGSize(width: 6720, height: 2160))
        #expect(layout.placements[0].pixelRect == CGRect(x: 0, y: 360, width: 2880, height: 1800))
        #expect(layout.placements[1].pixelRect == CGRect(x: 2880, y: 0, width: 3840, height: 2160))
    }

    @Test func needsAtLeastOneDisplay() {
        #expect(DisplayArrangement.layout(frames: [], scale: 2) == nil)
    }
}
