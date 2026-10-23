import AVFoundation
import CoreGraphics
import Foundation
import ishareCore
import Testing
struct PointerEffectPlanTests {
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
        let full = RecordingEffectsPlan.make(
            activity: activity, pointer: PointerEffectSettings(smoothing: true, scale: 2, ripples: true), autoZoom: AutoZoomSettings(), videoSize: size, duration: 2)
        #expect(full.pointer?.scale == 2)
        #expect(full.ripples.count == 1)
        #expect(full.camera?.segments.count == 1)
        #expect(full.withoutCamera().camera == nil)
    }
}

@testable import ishare

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

@MainActor
struct RecordingEffectsSettingsTests {
    @Test func exportsTheNewPreferences() {
        let names = SettingsTransfer.preferenceNames
        for key in [
            "autoZoomEnabled", "autoZoomLevel", "pointerSmoothing", "pointerScale", "clickRipples", "clickRippleColor", "hidesIdlePointer",
            "liveDrawingFadeDelay", "liveDrawingTool", "recordingMaxMinutes", "recordingMaxMegabytes", "recordingLowDiskWarningMB",
        ] {
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
        let camera = CameraPath(
            frameSize: size,
            segments: [
                ZoomSegment(start: 0, peak: 0, release: 2, end: 2, zoom: 2, focus: [PointerSample(time: 0, point: tip)], motion: .pan, panDuration: 0.5)
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
        let camera = CameraPlanner.plan(
            activity: [ActivityEvent(time: 0.5, point: CGPoint(x: 100, y: 100), kind: .click)], pointer: [], duration: 1, frameSize: size, settings: AutoZoomSettings())
        let composition = try await OverlayCompositor.previewComposition(for: AVURLAsset(url: video), camera: camera)
        #expect(composition.renderSize == size)
        #expect(composition.instructions.count == 1)
    }
}
