import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct SpotlightTimelineTests {
    private let left = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let right = CGRect(x: 200, y: 0, width: 100, height: 100)

    @Test func holdsTheFirstWindowFromTheStart() throws {
        let timeline = SpotlightTimeline(samples: [SpotlightSample(time: 1, windowID: 1, frame: left)])
        #expect(try #require(timeline.frame(at: 0)).rect == left)
        #expect(try #require(timeline.frame(at: 5)) == SpotlightFrame(rect: left, strength: 1))
        #expect(!timeline.isEmpty)
    }

    @Test func glidesSmoothlyToANewlyFocusedWindow() throws {
        let timeline = SpotlightTimeline(samples: [
            SpotlightSample(time: 0, windowID: 1, frame: left),
            SpotlightSample(time: 0.1, windowID: 1, frame: left),
            SpotlightSample(time: 1, windowID: 2, frame: right),
        ])
        #expect(timeline.changeCount == 1)
        #expect(try #require(timeline.frame(at: 1)).rect == left)
        let middle = try #require(timeline.frame(at: 1 + SpotlightTimeline.focusTransition / 2)).rect
        #expect(abs(middle.minX - 100) < 0.001)
        let early = try #require(timeline.frame(at: 1 + SpotlightTimeline.focusTransition / 4)).rect
        #expect(early.minX < 50)
        #expect(try #require(timeline.frame(at: 1 + SpotlightTimeline.focusTransition)).rect == right)
    }

    @Test func followsAMovingWindowQuicklyAndLinearly() throws {
        let moved = left.offsetBy(dx: 40, dy: 0)
        let timeline = SpotlightTimeline(samples: [
            SpotlightSample(time: 0, windowID: 1, frame: left),
            SpotlightSample(time: 1, windowID: 1, frame: moved),
        ])
        let halfway = try #require(timeline.frame(at: 1 + SpotlightTimeline.followDuration / 2)).rect
        #expect(abs(halfway.minX - 20) < 0.001)
        #expect(try #require(timeline.frame(at: 1 + SpotlightTimeline.followDuration)).rect == moved)
    }

    @Test func fadesOutWhenNoWindowIsFocusedAndBackInAtTheNextOne() throws {
        let timeline = SpotlightTimeline(samples: [
            SpotlightSample(time: 0, windowID: 1, frame: left),
            SpotlightSample(time: 1, windowID: nil, frame: nil),
            SpotlightSample(time: 3, windowID: 2, frame: right),
        ])
        let fading = try #require(timeline.frame(at: 1 + SpotlightTimeline.focusTransition / 2))
        #expect(fading.rect == left)
        #expect(abs(fading.strength - 0.5) < 0.001)
        #expect(timeline.frame(at: 2) == nil)
        let appearing = try #require(timeline.frame(at: 3 + SpotlightTimeline.focusTransition / 2))
        #expect(appearing.rect == right)
        #expect(abs(appearing.strength - 0.5) < 0.001)
        #expect(try #require(timeline.frame(at: 4)).strength == 1)
    }

    @Test func restartsATransitionFromWhereTheLastOneWas() throws {
        let timeline = SpotlightTimeline(samples: [
            SpotlightSample(time: 0, windowID: 1, frame: left),
            SpotlightSample(time: 1, windowID: 2, frame: right),
            SpotlightSample(time: 1 + SpotlightTimeline.focusTransition / 2, windowID: 1, frame: left),
        ])
        let atSwitch = try #require(timeline.frame(at: 1 + SpotlightTimeline.focusTransition / 2)).rect
        #expect(abs(atSwitch.minX - 100) < 0.001)
        #expect(try #require(timeline.frame(at: 3)).rect == left)
    }

    @Test func isEmptyWithoutAnyFocusedWindow() {
        #expect(SpotlightTimeline(samples: []).isEmpty)
        #expect(SpotlightTimeline(samples: [SpotlightSample(time: 0, windowID: nil, frame: nil)]).isEmpty)
        #expect(SpotlightTimeline(samples: []).frame(at: 1) == nil)
    }

    @Test func clampsTheDimmingAmount() {
        #expect(SpotlightStyle(dimming: 0.1).dimming == 0.3)
        #expect(SpotlightStyle(dimming: 0.95).dimming == 0.8)
        #expect(SpotlightStyle(dimming: 0.6).dimming == 0.6)
    }
}

struct SpotlightGeometryTests {
    @Test func mapsAWindowIntoTheVideo() throws {
        let source = CGRect(x: 100, y: 50, width: 800, height: 600)
        let rect = try #require(
            SpotlightGeometry.videoRect(windowFrame: CGRect(x: 200, y: 150, width: 200, height: 100), sourceRect: source, videoSize: CGSize(width: 1600, height: 1200)))
        #expect(rect == CGRect(x: 200, y: 200, width: 400, height: 200))
    }

    @Test func clipsToTheRecordedAreaAndLetterboxes() throws {
        let source = CGRect(x: 0, y: 0, width: 400, height: 200)
        let rect = try #require(
            SpotlightGeometry.videoRect(windowFrame: CGRect(x: -100, y: 100, width: 200, height: 300), sourceRect: source, videoSize: CGSize(width: 400, height: 400)))
        #expect(rect == CGRect(x: 0, y: 200, width: 100, height: 100))
        #expect(SpotlightGeometry.videoRect(windowFrame: CGRect(x: 500, y: 0, width: 50, height: 50), sourceRect: source, videoSize: CGSize(width: 400, height: 200)) == nil)
    }

    @Test func flipsIntoBottomLeftCoordinates() {
        #expect(SpotlightGeometry.flipped(CGRect(x: 10, y: 20, width: 30, height: 40), videoHeight: 100) == CGRect(x: 10, y: 40, width: 30, height: 40))
    }
}

struct FocusedWindowPickerTests {
    private func window(_ id: UInt32, pid: Int32, layer: Int = 0, size: CGFloat = 300) -> WindowDescriptor {
        WindowDescriptor(id: id, layer: layer, frame: CGRect(x: 0, y: 0, width: size, height: size), ownerPID: pid, ownerBundleID: nil)
    }

    @Test func picksTheFrontmostNormalWindowOfTheActiveApp() {
        let windows = [window(1, pid: 9, layer: 25), window(2, pid: 7), window(3, pid: 9, size: 20), window(4, pid: 9), window(5, pid: 9)]
        #expect(FocusedWindowPicker.focusedWindow(in: windows, frontmostPID: 9)?.id == 4)
        #expect(FocusedWindowPicker.focusedWindow(in: windows, frontmostPID: 7)?.id == 2)
        #expect(FocusedWindowPicker.focusedWindow(in: windows, frontmostPID: 3) == nil)
        #expect(FocusedWindowPicker.focusedWindow(in: windows, frontmostPID: nil) == nil)
    }
}
