import CoreGraphics
import Testing
@testable import ishareCore

struct WebcamLayoutTests {
    let video = CGSize(width: 1920, height: 1080)
    let bubble = CGRect(x: 1700, y: 40, width: 180, height: 180)

    @Test func keepsTheBubbleInTheCorner() {
        let placement = WebcamLayoutPlanner.placement(layout: .bubble, videoSize: video, sourceSize: video, bubble: bubble, time: 1, sections: [])
        #expect(placement.webcam == bubble && placement.isRound && placement.screen == CGRect(origin: .zero, size: video))
    }

    @Test func putsTheWebcamBesideTheScreen() {
        let placement = WebcamLayoutPlanner.placement(layout: .sideBySide, videoSize: video, sourceSize: video, bubble: bubble, time: 1, sections: [])
        #expect(placement.webcam == CGRect(x: 1382, y: 0, width: 538, height: 1080))
        #expect(placement.screen.maxX <= 1382)
        #expect(!placement.isRound)
    }

    @Test func goesFullScreenAtEachMarker() {
        let atMarker = WebcamLayoutPlanner.placement(layout: .fullScreenAtMarkers, videoSize: video, sourceSize: video, bubble: bubble, time: 11, sections: [10])
        #expect(atMarker.webcam == CGRect(origin: .zero, size: video))
        let later = WebcamLayoutPlanner.placement(layout: .fullScreenAtMarkers, videoSize: video, sourceSize: video, bubble: bubble, time: 14, sections: [10])
        #expect(later.webcam == bubble)
    }
}
