import CoreGraphics
import Foundation
import ishareCore
import Testing
@testable import ishare

@MainActor
struct RecordingPauseControlTests {
    private func command(_ string: String) -> URLSchemeCommand? {
        guard let url = URL(string: string), case let .success(request) = URLSchemeParser.parse(url) else { return nil }
        return request.command
    }

    @Test func parsesPauseAndResumeURLs() {
        #expect(command("ishare://record/pause") == .record(.pause, gif: false, region: false))
        #expect(command("ishare://record/resume") == .record(.resume, gif: false, region: false))
    }

    @Test func parsesPauseAndResumeCommands() throws {
        guard case let .run(pause) = try CLIArguments.parse(["record", "pause"]), case let .run(resume) = try CLIArguments.parse(["record", "resume"]) else {
            Issue.record("Expected runnable commands")
            return
        }
        #expect(pause.command == .record(.pause))
        #expect(resume.command == .record(.resume))
    }

    @Test func formatsTheRemainingTime() {
        #expect(RecordingStatusText.remaining(61.2) == "−1:02")
        #expect(RecordingStatusText.clock(0) == "0:00")
        #expect(RecordingStatusText.toolTip(isRecording: false, isPaused: false, remaining: 10) == nil)
        #expect(RecordingStatusText.toolTip(isRecording: true, isPaused: false, remaining: nil) != nil)
        #expect(RecordingStatusText.toolTip(isRecording: true, isPaused: true, remaining: 30)?.contains("0:30") == true)
    }

    @Test func shiftsOverlayEventsAcrossPauses() {
        var log = OverlayEventLog()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        log.recordClick(at: CGPoint(x: 10, y: 10), sourceRect: rect, time: 102)
        log.recordClick(at: CGPoint(x: 10, y: 10), sourceRect: rect, time: 106)
        log.recordClick(at: CGPoint(x: 10, y: 10), sourceRect: rect, time: 110)
        let pauses = RecordingPauseTimeline(pauses: [105 ..< 108])
        let timeline = log.timeline(recordingStart: 100, videoSize: CGSize(width: 100, height: 100), pauses: pauses)
        #expect(timeline.clicks.map(\.time) == [2, 7])
    }

    @Test func shiftsPointerActivityAcrossPauses() {
        var log = PointerActivityLog()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for time in stride(from: 100.0, through: 110, by: 1) {
            log.recordSample(at: CGPoint(x: 50, y: 50), sourceRect: rect, time: time)
        }
        log.recordKey(time: 104)
        log.recordKey(time: 109)
        let activity = log.activity(recordingStart: 100, videoSize: CGSize(width: 100, height: 100), pauses: RecordingPauseTimeline(pauses: [103.5 ..< 106.5]))
        #expect(activity.pointer.map(\.time) == [0, 1, 2, 3, 4, 5, 6, 7])
        #expect(activity.keyTimes == [6])
    }

    @Test func placesWebcamFootageAroundPauses() {
        let clip = OverlayWebcamClip(
            url: URL(fileURLWithPath: "/tmp/cam.mov"), offset: 0, startTime: 100, recordingStart: 100, pauses: RecordingPauseTimeline(pauses: [102 ..< 104]))
        let segments = clip.segments(clipDuration: 10, outputDuration: 8)
        #expect(segments.map(\.outputStart) == [0, 2])
        #expect(segments.map(\.sourceStart) == [0, 4])
    }
}

struct PointerShapeRenderingTests {
    private func image() -> CGImage {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    @Test func looksUpTheRecordedImageForAShape() {
        var track = PointerShapeTrack()
        track.record(PointerShape(fingerprint: 1, hotSpot: .zero, size: CGSize(width: 2, height: 2)), at: 0)
        track.record(PointerShape(fingerprint: 2, hotSpot: CGPoint(x: 1, y: 1), size: CGSize(width: 2, height: 2)), at: 1)
        let set = PointerShapeSet(track: track, images: [image(), image()])
        #expect(set.image(at: 0.5)?.index == 0)
        #expect(set.image(at: 2)?.shape.fingerprint == 2)
        #expect(PointerShapeSet(track: track, images: [image()]).image(at: 2) == nil)
    }

    @Test func keepsShapesOnlyWhenIshareDrawsThePointer() {
        var track = PointerShapeTrack()
        track.record(PointerShape(fingerprint: 1, hotSpot: .zero, size: CGSize(width: 2, height: 2)), at: 0)
        let set = PointerShapeSet(track: track, images: [image()])
        let activity = PointerActivity(pointer: [PointerSample(time: 0, point: .zero), PointerSample(time: 1, point: CGPoint(x: 5, y: 5))])
        let size = CGSize(width: 100, height: 100)
        let drawn = RecordingEffectsPlan.make(activity: activity, pointer: PointerEffectSettings(smoothing: true), autoZoom: nil, videoSize: size, duration: 1, shapes: set)
        let native = RecordingEffectsPlan.make(activity: activity, pointer: PointerEffectSettings(), autoZoom: nil, videoSize: size, duration: 1, shapes: set)
        #expect(drawn.pointerShapes == set)
        #expect(native.pointerShapes == nil)
    }
}
