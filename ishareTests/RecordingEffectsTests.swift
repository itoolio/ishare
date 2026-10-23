import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ishare

struct CameraPlannerTests {
    let frame = CGSize(width: 1920, height: 1080)

    private func click(_ time: Double, _ x: CGFloat, _ y: CGFloat) -> ActivityEvent {
        ActivityEvent(time: time, point: CGPoint(x: x, y: y), kind: .click)
    }

    private func plan(_ events: [ActivityEvent], pointer: [PointerSample] = [], duration: Double = 30, settings: AutoZoomSettings = AutoZoomSettings(followsPointer: false)) -> CameraPath {
        CameraPlanner.plan(activity: events, pointer: pointer, duration: duration, frameSize: frame, settings: settings)
    }

    private func assertWellFormed(_ path: CameraPath, duration: Double) {
        for segment in path.segments {
            #expect(segment.start >= 0)
            #expect(segment.start <= segment.peak)
            #expect(segment.peak <= segment.release)
            #expect(segment.release <= segment.end)
            #expect(segment.end <= duration)
        }
        for (previous, next) in zip(path.segments, path.segments.dropFirst()) {
            #expect(previous.end <= next.start)
        }
        let bounds = CGRect(origin: .zero, size: frame)
        for step in 0 ... Int(duration * 20) {
            let rect = path.visibleRect(at: Double(step) / 20)
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        }
    }

    @Test func returnsNoSegmentsWithoutActivity() {
        #expect(plan([]).isEmpty)
        #expect(CameraPlanner.plan(activity: [click(1, 10, 10)], pointer: [], duration: 0, frameSize: frame, settings: AutoZoomSettings()).isEmpty)
    }

    @Test func zoomsInAroundASingleClickAndBackOut() throws {
        let settings = AutoZoomSettings(zoom: 2, easeDuration: 0.5, holdTime: 1, followsPointer: false)
        let path = plan([click(5, 960, 540)], settings: settings)
        let segment = try #require(path.segments.first)
        #expect(path.segments.count == 1)
        #expect(segment.start == 4.5)
        #expect(segment.peak == 5)
        #expect(segment.release == 6)
        #expect(segment.end == 6.5)
        #expect(path.scale(at: 4) == 1)
        #expect(path.scale(at: 5.5) == 2)
        #expect(path.scale(at: 7) == 1)
        let rect = path.visibleRect(at: 5.5)
        #expect(rect.size == CGSize(width: 960, height: 540))
        #expect(rect.midX == 960)
        #expect(rect.midY == 540)
        let keyframes = path.keyframes
        #expect(keyframes.map(\.time) == [4.5, 5, 6, 6.5])
        #expect(keyframes.first?.scale == 1)
        #expect(keyframes[1].scale == 2)
        #expect(keyframes.last?.scale == 1)
        assertWellFormed(path, duration: 30)
    }

    @Test func easesTheZoomSmoothly() throws {
        let path = plan([click(5, 960, 540)], settings: AutoZoomSettings(zoom: 3, easeDuration: 1, holdTime: 1, followsPointer: false))
        let samples = stride(from: 4.0, through: 5.0, by: 0.05).map { path.scale(at: $0) }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(abs(path.scale(at: 4.5) - 2) < 0.001)
    }

    @Test func clampsTheViewportToTheFrameNearCorners() {
        let path = plan([click(2, 5, 5), click(10, 1915, 1075)])
        let topLeft = path.visibleRect(at: 2)
        #expect(topLeft.origin == .zero)
        let bottomRight = path.visibleRect(at: 10)
        #expect(abs(bottomRight.maxX - 1920) < 0.001)
        #expect(abs(bottomRight.maxY - 1080) < 0.001)
        assertWellFormed(path, duration: 30)
    }

    @Test func clampsSettingsToTheirRanges() {
        let settings = AutoZoomSettings(zoom: 9, easeDuration: 0, holdTime: 99)
        #expect(settings.zoom == 3)
        #expect(settings.easeDuration == AutoZoomSettings.easeRange.lowerBound)
        #expect(settings.holdTime == AutoZoomSettings.holdRange.upperBound)
        #expect(AutoZoomSettings(zoom: 1).zoom == 1.5)
    }

    @Test func keepsNearbyClicksInOneSegmentAndPansBetweenThem() throws {
        let path = plan([click(2, 800, 500), click(2.8, 900, 520), click(3.6, 1000, 560)])
        #expect(path.segments.count == 1)
        let segment = try #require(path.segments.first)
        #expect(segment.focus.count == 3)
        #expect(path.visibleRect(at: 2).midX < path.visibleRect(at: 3.6).midX)
        assertWellFormed(path, duration: 30)
    }

    @Test func zoomsOutWhenActivityStops() {
        let settings = AutoZoomSettings(zoom: 2, easeDuration: 0.5, holdTime: 1, followsPointer: false)
        let path = plan([click(2, 900, 500), click(10, 900, 500)], settings: settings)
        #expect(path.segments.count == 2)
        #expect(path.scale(at: 6) == 1)
        assertWellFormed(path, duration: 30)
    }

    @Test func bridgesShortPausesInsteadOfBouncing() {
        let settings = AutoZoomSettings(zoom: 2, easeDuration: 0.5, holdTime: 1, followsPointer: false)
        let path = plan([click(2, 900, 500), click(3.8, 920, 510)], settings: settings)
        #expect(path.segments.count == 1)
        #expect(path.scale(at: 3.4) == 2)
    }

    @Test func zoomsOutWhenActivityMovesFarWithoutOverlapping() {
        let settings = AutoZoomSettings(zoom: 2, easeDuration: 0.6, holdTime: 1.5, followsPointer: false)
        let path = plan([click(2, 100, 100), click(2.4, 1800, 1000), click(2.8, 100, 1000), click(3.0, 1800, 100)], settings: settings)
        #expect(path.segments.count == 4)
        assertWellFormed(path, duration: 30)
    }

    @Test func neverRunsPastTheEndOfTheRecording() throws {
        let path = plan([click(9.8, 900, 500)], duration: 10)
        let segment = try #require(path.segments.first)
        #expect(segment.end <= 10)
        assertWellFormed(path, duration: 10)
    }

    @Test func ignoresEventsOutsideTheRecording() {
        #expect(plan([click(-1, 10, 10), click(40, 10, 10)]).isEmpty)
    }

    @Test func staysWellFormedForDenseRandomActivity() {
        var generator = SeededGenerator(seed: 42)
        let events = (0 ..< 200).map { _ in
            click(Double.random(in: 0 ... 60, using: &generator), CGFloat.random(in: -50 ... 2000, using: &generator), CGFloat.random(in: -50 ... 1200, using: &generator))
        }
        let path = plan(events, duration: 60, settings: AutoZoomSettings(zoom: 2.5, easeDuration: 0.4, holdTime: 0.8, followsPointer: false))
        #expect(!path.isEmpty)
        assertWellFormed(path, duration: 60)
    }

    @Test func followsThePointerWhileZoomed() throws {
        let pointer = stride(from: 0.0, through: 8.0, by: 1.0 / 30).map { time in
            PointerSample(time: time, point: CGPoint(x: 400 + time * 120, y: 500))
        }
        let path = plan([click(2, 640, 500), click(3, 760, 500)], pointer: pointer, settings: AutoZoomSettings(zoom: 2, easeDuration: 0.5, holdTime: 2, followsPointer: true))
        let segment = try #require(path.segments.first)
        #expect(segment.motion == .track)
        #expect(path.visibleRect(at: 4.5).midX > path.visibleRect(at: 2).midX)
        assertWellFormed(path, duration: 30)
    }

    @Test func holdsTheCameraWhileThePointerStaysInTheDeadZone() {
        let samples = [
            PointerSample(time: 0, point: CGPoint(x: 500, y: 500)),
            PointerSample(time: 0.1, point: CGPoint(x: 540, y: 520)),
            PointerSample(time: 0.2, point: CGPoint(x: 900, y: 500)),
        ]
        let held = CameraPlanner.deadZoned(samples, initial: CGPoint(x: 500, y: 500), viewport: CGSize(width: 960, height: 540))
        #expect(held[1].point == CGPoint(x: 500, y: 500))
        #expect(abs(held[2].point.x - (900 - 960 * CameraPlanner.deadZoneFraction)) < 0.001)
    }

    @Test func anchorsTypingAtTheLastClick() {
        let clicks = [PointerSample(time: 1, point: CGPoint(x: 10, y: 20))]
        let pointer = [PointerSample(time: 0, point: CGPoint(x: 99, y: 99)), PointerSample(time: 3, point: CGPoint(x: 500, y: 500))]
        let events = ActivityEvent.collect(clicks: clicks, keyTimes: [0.5, 2], pointer: pointer)
        #expect(events.map(\.time) == [0.5, 1, 2])
        #expect(events[0].point == CGPoint(x: 99, y: 99))
        #expect(events[0].kind == .typing)
        #expect(events[2].point == CGPoint(x: 10, y: 20))
    }
}

struct PointerEffectsTests {
    @Test func smoothingStartsAtTheFirstSampleAndLagsBehindJumps() {
        let samples = (0 ... 30).map { index in
            PointerSample(time: Double(index) / 30, point: index < 5 ? .zero : CGPoint(x: 100, y: 0))
        }
        let smoothed = PointerSmoother.smooth(samples)
        #expect(smoothed.first?.point == .zero)
        #expect(smoothed[5].point.x > 0)
        #expect(smoothed[5].point.x < 100)
        #expect(smoothed[6].point.x > smoothed[5].point.x)
        #expect(abs((smoothed.last?.point.x ?? 0) - 100) < 1)
        #expect(smoothed.map(\.time) == samples.map(\.time))
    }

    @Test func resamplesAtAFixedInterval() {
        let samples = [PointerSample(time: 0, point: .zero), PointerSample(time: 1, point: CGPoint(x: 10, y: 0))]
        let resampled = PointerSmoother.resample(samples, interval: 0.25)
        #expect(resampled.map(\.time) == [0, 0.25, 0.5, 0.75, 1])
        #expect(resampled[2].point == CGPoint(x: 5, y: 0))
    }

    @Test func detectsIdlePeriods() {
        let samples = stride(from: 0.0, through: 10.0, by: 0.5).map { time in
            PointerSample(time: time, point: time < 2 ? CGPoint(x: time * 10, y: 0) : time < 8 ? CGPoint(x: 20, y: 0) : CGPoint(x: time * 10, y: 0))
        }
        let intervals = PointerIdleDetector.hiddenIntervals(samples: samples, clicks: [], idleDelay: 3, duration: 10)
        #expect(intervals == [5 ... 8])
        let clicked = PointerIdleDetector.hiddenIntervals(samples: samples, clicks: [5], idleDelay: 3, duration: 10)
        #expect(clicked.isEmpty)
        let still = [PointerSample(time: 0, point: .zero), PointerSample(time: 9, point: .zero)]
        #expect(PointerIdleDetector.hiddenIntervals(samples: still, clicks: [], idleDelay: 3, duration: 9) == [3 ... 9])
    }

    @Test func fadesTheIdlePointerOutAndShowsItAgainOnMovement() {
        let track = PointerTrack(samples: [], hiddenIntervals: [4 ... 8])
        #expect(track.opacity(at: 3) == 1)
        #expect(track.opacity(at: 4) == 1)
        #expect(abs(track.opacity(at: 4 + PointerTrack.fadeDuration / 2) - 0.5) < 0.001)
        #expect(track.opacity(at: 6) == 0)
        #expect(track.opacity(at: 8) == 1)
    }

    @Test func interpolatesPointerPositionsAndHidesItInGaps() {
        let track = PointerTrack(samples: [
            PointerSample(time: 0, point: .zero),
            PointerSample(time: 0.1, point: CGPoint(x: 10, y: 20)),
            PointerSample(time: 2, point: CGPoint(x: 50, y: 50)),
        ])
        #expect(track.position(at: 0.05) == CGPoint(x: 5, y: 10))
        #expect(track.position(at: 1) == nil)
        #expect(track.position(at: 2.05) == CGPoint(x: 50, y: 50))
        #expect(track.position(at: 3) == nil)
    }

    @Test func animatesRipplesAndEndsThem() throws {
        let start = try #require(ClickRippleAnimation.frame(elapsed: 0))
        let middle = try #require(ClickRippleAnimation.frame(elapsed: ClickRippleAnimation.lifetime / 2))
        #expect(start.alpha == 1)
        #expect(middle.diameterScale > start.diameterScale)
        #expect(middle.alpha < start.alpha)
        #expect(ClickRippleAnimation.frame(elapsed: ClickRippleAnimation.lifetime) == nil)
        #expect(ClickRippleAnimation.frame(elapsed: -0.1) == nil)
        let clicks = [OverlayClick(time: 1, point: .zero), OverlayClick(time: 5, point: CGPoint(x: 1, y: 1))]
        #expect(ClickRippleAnimation.active(clicks, at: 1.2).count == 1)
    }

    @Test func rendersThePointerOnlyWhenAnEffectNeedsIt() {
        #expect(!PointerEffectSettings().rendersPointer)
        #expect(PointerEffectSettings(smoothing: true).rendersPointer)
        #expect(PointerEffectSettings(scale: 2).rendersPointer)
        #expect(PointerEffectSettings(hidesWhenIdle: true).rendersPointer)
        #expect(!PointerEffectSettings(recordsPointer: false, smoothing: true).rendersPointer)
        #expect(PointerEffectSettings(ripples: true).isActive)
        #expect(!PointerEffectSettings(ripples: true).rendersPointer)
        #expect(PointerEffectSettings(scale: 7).scale == 3)
    }

    @Test func mapsLoggedPointerActivityIntoVideoCoordinates() {
        var log = PointerActivityLog()
        let source = CGRect(x: 100, y: 100, width: 400, height: 300)
        log.recordSample(at: CGPoint(x: 300, y: 250), sourceRect: source, time: 10.5)
        log.recordSample(at: CGPoint(x: 900, y: 900), sourceRect: source, time: 10.6)
        log.recordClick(at: CGPoint(x: 100, y: 100), sourceRect: source, time: 11)
        log.recordKey(time: 9)
        log.recordKey(time: 12)
        let activity = log.activity(recordingStart: 10, videoSize: CGSize(width: 800, height: 600))
        #expect(activity.pointer == [PointerSample(time: 0.5, point: CGPoint(x: 400, y: 300))])
        #expect(activity.clicks == [PointerSample(time: 1, point: .zero)])
        #expect(activity.keyTimes == [2])
    }

    @Test func plansEffectsFromSettings() {
        let activity = PointerActivity(
            pointer: [PointerSample(time: 0, point: .zero), PointerSample(time: 1, point: CGPoint(x: 10, y: 10))],
            clicks: [PointerSample(time: 0.5, point: CGPoint(x: 5, y: 5))]
        )
        let size = CGSize(width: 100, height: 100)
        let none = RecordingEffectsPlan.make(activity: activity, pointer: PointerEffectSettings(), autoZoom: nil, videoSize: size, duration: 2)
        #expect(none.isEmpty)
        let full = RecordingEffectsPlan.make(activity: activity, pointer: PointerEffectSettings(smoothing: true, scale: 2, ripples: true), autoZoom: AutoZoomSettings(), videoSize: size, duration: 2)
        #expect(full.pointer?.scale == 2)
        #expect(full.ripples.count == 1)
        #expect(full.camera?.segments.count == 1)
        #expect(full.withoutCamera().camera == nil)
    }
}

struct LiveDrawingTests {
    private let red = CaptureColor(red: 1, green: 0, blue: 0)

    @Test func recordsStrokesAndUndoesThem() {
        var board = LiveDrawingBoard(fadeDelay: 0)
        board.begin(at: .zero, tool: .pen, color: red)
        board.extend(to: CGPoint(x: 0.1, y: 0))
        board.extend(to: CGPoint(x: 10, y: 0))
        board.finish(at: 1)
        #expect(board.marks.count == 1)
        #expect(board.marks[0].points == [.zero, CGPoint(x: 10, y: 0)])
        board.extend(to: CGPoint(x: 20, y: 0))
        #expect(board.marks[0].points.count == 2)
        board.undo()
        #expect(board.isEmpty)
    }

    @Test func arrowsKeepOnlyTheirEndpoints() {
        var board = LiveDrawingBoard(fadeDelay: 0)
        board.begin(at: .zero, tool: .arrow, color: red)
        board.extend(to: CGPoint(x: 5, y: 5))
        board.extend(to: CGPoint(x: 30, y: 0))
        #expect(board.marks[0].points == [.zero, CGPoint(x: 30, y: 0)])
    }

    @Test func fadesMarksAfterTheDelay() {
        var board = LiveDrawingBoard(fadeDelay: 2)
        board.begin(at: .zero, tool: .highlighter, color: red)
        #expect(board.opacity(of: board.marks[0], at: 100) == 1)
        board.finish(at: 10)
        let mark = board.marks[0]
        #expect(board.opacity(of: mark, at: 11.9) == 1)
        #expect(abs(board.opacity(of: mark, at: 12 + LiveDrawingBoard.fadeDuration / 2) - 0.5) < 0.001)
        #expect(board.needsAnimation(at: 12.1))
        board.prune(at: 13)
        #expect(board.isEmpty)
        #expect(!board.needsAnimation(at: 20))
    }

    @Test func keepsMarksUntilClearedWithoutAFadeDelay() {
        var board = LiveDrawingBoard(fadeDelay: 0)
        board.begin(at: .zero, tool: .pen, color: red)
        board.finish(at: 0)
        board.prune(at: 1000)
        #expect(board.marks.count == 1)
        #expect(!board.needsAnimation(at: 1000))
        board.clear()
        #expect(board.isEmpty)
    }

    @Test func pointsArrowHeadsBackAlongTheShaft() throws {
        let head = try #require(LiveDrawingBoard.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), length: 20))
        #expect(head.0.x < 100 && head.1.x < 100)
        #expect(abs(head.0.y + head.1.y) < 0.001)
        #expect(abs(CGPoint(x: 100, y: 0).distance(to: head.0) - 20) < 0.001)
        #expect(LiveDrawingBoard.arrowHead(from: .zero, to: CGPoint(x: 0.5, y: 0), length: 20) == nil)
        #expect(LiveDrawingBoard.arrowHeadLength(lineWidth: 4, start: .zero, end: CGPoint(x: 10, y: 0)) == 5)
    }

    @Test func describesToolsAndFadeChoices() {
        #expect(LiveDrawingTool.highlighter.opacity < 1)
        #expect(LiveDrawingTool.highlighter.lineWidth > LiveDrawingTool.pen.lineWidth)
        #expect(LiveDrawingFade.never.rawValue == 0)
        #expect(LiveDrawingFade(rawValue: 5) == .seconds5)
    }
}

struct RecordingLimitTests {
    private let megabyte = RecordingLimits.megabyte

    @Test func convertsSettingsIntoLimits() {
        let limits = RecordingLimits.make(maxMinutes: 2, maxMegabytes: 100, lowDiskMegabytes: 1024)
        #expect(limits.maxDuration == 120)
        #expect(limits.maxBytes == 100 * megabyte)
        #expect(limits.lowDiskBytes == 1024 * megabyte)
        #expect(limits.hasRecordingLimit)
        let none = RecordingLimits.make(maxMinutes: 0, maxMegabytes: 0, lowDiskMegabytes: 2048)
        #expect(none.maxDuration == nil)
        #expect(none.maxBytes == nil)
        #expect(!none.hasRecordingLimit)
        #expect(RecordingLimits(lowDiskBytes: 100).criticalDiskBytes == 100)
    }

    @Test func stopsAtTheTimeAndSizeLimits() {
        let limits = RecordingLimits(maxDuration: 60, maxBytes: 10 * megabyte)
        #expect(RecordingLimitPolicy.decision(elapsed: 30, bytesWritten: megabyte, freeBytes: 100_000 * megabyte, limits: limits, hasWarned: false) == .keepRecording)
        #expect(RecordingLimitPolicy.decision(elapsed: 60, bytesWritten: megabyte, freeBytes: nil, limits: limits, hasWarned: false) == .stop(.duration))
        #expect(RecordingLimitPolicy.decision(elapsed: 10, bytesWritten: 10 * megabyte, freeBytes: nil, limits: limits, hasWarned: false) == .stop(.size))
    }

    @Test func warnsOnceAndStopsWhenTheDiskIsCriticallyLow() {
        let limits = RecordingLimits(lowDiskBytes: 2048 * megabyte)
        #expect(RecordingLimitPolicy.decision(elapsed: 1, bytesWritten: 0, freeBytes: 1000 * megabyte, limits: limits, hasWarned: false) == .warnLowDisk)
        #expect(RecordingLimitPolicy.decision(elapsed: 1, bytesWritten: 0, freeBytes: 1000 * megabyte, limits: limits, hasWarned: true) == .keepRecording)
        #expect(RecordingLimitPolicy.decision(elapsed: 1, bytesWritten: 0, freeBytes: 100 * megabyte, limits: limits, hasWarned: true) == .stop(.diskSpace))
        #expect(!RecordingLimitPolicy.rearmsWarning(freeBytes: 2100 * megabyte, limits: limits))
        #expect(RecordingLimitPolicy.rearmsWarning(freeBytes: 3000 * megabyte, limits: limits))
        #expect(!RecordingLimitPolicy.rearmsWarning(freeBytes: nil, limits: limits))
    }

    @Test func estimatesTheRemainingTime() {
        let limits = RecordingLimits(maxDuration: 600, maxBytes: 100 * megabyte)
        #expect(RecordingLimitPolicy.remainingTime(elapsed: 1, bytesWritten: megabyte, limits: limits) == 599)
        let estimate = RecordingLimitPolicy.remainingTime(elapsed: 10, bytesWritten: 10 * megabyte, limits: limits)
        #expect(estimate == 90)
        #expect(RecordingLimitPolicy.remainingTime(elapsed: 10, bytesWritten: 0, limits: RecordingLimits()) == nil)
        #expect(RecordingLimitPolicy.remainingTime(elapsed: 700, bytesWritten: 0, limits: RecordingLimits(maxDuration: 600)) == 0)
    }

    @Test func readsTheFreeSpaceOfTheOutputVolume() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ishare-missing-\(UUID().uuidString).mov")
        let free = try #require(DiskSpace.availableBytes(near: url))
        #expect(free > 0)
    }
}

@MainActor
struct RecordingEffectsSettingsTests {
    @Test func exportsTheNewPreferences() {
        let names = SettingsTransfer.preferenceNames
        for key in ["autoZoomEnabled", "autoZoomLevel", "pointerSmoothing", "pointerScale", "clickRipples", "clickRippleColor", "hidesIdlePointer",
                    "liveDrawingFadeDelay", "liveDrawingTool", "recordingMaxMinutes", "recordingMaxMegabytes", "recordingLowDiskWarningMB"] {
            #expect(names.contains(key))
        }
    }

    @Test func findsTheNewSettingsBySearch() {
        for query in ["auto zoom", "click ripples", "pointer size", "highlighter", "stop after", "free space"] {
            #expect(SettingsSearchIndex.matches(for: query, localize: { $0 }).contains { $0.pane == .recording }, "\(query)")
        }
    }
}

struct RecordingEffectsCompositingTests {
    @Test func drawsTheSmoothedPointerAndZoomsIntoIt() async throws {
        let size = CGSize(width: 640, height: 480)
        let video = try await SyntheticVideo.make(size: size, seconds: 2, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }
        let tip = CGPoint(x: 320, y: 240)
        let samples = stride(from: 0.0, through: 2.0, by: 0.05).map { PointerSample(time: $0, point: tip) }
        let camera = CameraPath(frameSize: size, segments: [
            ZoomSegment(start: 0, peak: 0, release: 2, end: 2, zoom: 2, focus: [PointerSample(time: 0, point: tip)], motion: .pan, panDuration: 0.5),
        ])
        let asset = AVURLAsset(url: video)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let duration = try await asset.load(.duration)
        let timeline = OverlayTimeline(effects: RecordingEffectsPlan(pointer: PointerTrack(samples: samples), camera: camera))
        let layout = OverlayCompositionLayout(videoSize: size, pixelsPerPoint: 1, webcamFrame: nil)
        try await OverlayCompositor.composite(asset, screenTrack: track, duration: duration, timeline: timeline, layout: layout, replacing: video, hevc: false, progress: nil)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        let insideZoomedArrow = try #require(PixelProbe.rgb(in: frame, x: Int(tip.x) + 4, y: Int(tip.y) + 22))
        let background = try #require(PixelProbe.rgb(in: frame, x: 40, y: 40))
        #expect(background.red - insideZoomedArrow.red > 60)
    }

    @Test func buildsAPreviewCompositionForTheTrimWindow() async throws {
        let size = CGSize(width: 320, height: 240)
        let video = try await SyntheticVideo.make(size: size, seconds: 1, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }
        let camera = CameraPlanner.plan(activity: [ActivityEvent(time: 0.5, point: CGPoint(x: 100, y: 100), kind: .click)], pointer: [], duration: 1, frameSize: size, settings: AutoZoomSettings())
        let composition = try await OverlayCompositor.previewComposition(for: AVURLAsset(url: video), camera: camera)
        #expect(composition.renderSize == size)
        #expect(composition.instructions.count == 1)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
