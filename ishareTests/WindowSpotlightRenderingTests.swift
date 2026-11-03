import CoreImage
import ishareCore
import Testing
@testable import ishare

struct WindowSpotlightRenderingTests {
    private let size = CGSize(width: 100, height: 80)
    private let context = CIContext()

    private func brightness(of image: CIImage, at point: CGPoint) -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Double(pixel[0]) / 255
    }

    private func plan(dimming: Double) -> SpotlightPlan {
        let timeline = SpotlightTimeline(samples: [SpotlightSample(time: 0, windowID: 1, frame: CGRect(x: 20, y: 20, width: 40, height: 30))])
        return SpotlightPlan(timeline: timeline, style: SpotlightStyle(dimming: dimming))
    }

    @Test func dimsEverythingOutsideTheFocusedWindow() {
        let white = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        let result = SpotlightRenderer.apply(plan(dimming: 0.6), to: white, time: 0, videoSize: size)
        #expect(brightness(of: result, at: CGPoint(x: 30, y: 30)) > 0.98)
        let outside = brightness(of: result, at: CGPoint(x: 5, y: 5))
        #expect(outside < 0.8 && outside > 0.2)
    }

    @Test func leavesFramesWithoutAFocusedWindowUntouched() {
        let white = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        let empty = SpotlightPlan(timeline: SpotlightTimeline(samples: [SpotlightSample(time: 0, windowID: nil, frame: nil)]), style: SpotlightStyle())
        let result = SpotlightRenderer.apply(empty, to: white, time: 0, videoSize: size)
        #expect(brightness(of: result, at: CGPoint(x: 5, y: 5)) > 0.98)
    }

    @Test func mapsSamplesIntoFlippedVideoCoordinatesAndPauseTime() throws {
        let capture = SpotlightCapture(
            samples: [SpotlightSample(time: 10, windowID: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 40))], sourceSize: CGSize(width: 100, height: 80),
            style: SpotlightStyle())
        let plan = try #require(capture.plan(recordingStart: 10, videoSize: CGSize(width: 200, height: 160), pauses: RecordingPauseTimeline()))
        let frame = try #require(plan.timeline.frame(at: 0))
        #expect(frame.rect == CGRect(x: 0, y: 80, width: 100, height: 80))
    }
}
