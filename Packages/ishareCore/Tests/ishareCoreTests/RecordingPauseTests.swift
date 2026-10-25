import Foundation
import Testing
@testable import ishareCore

struct RecordingPauseTimelineTests {
    private func timeline(_ pauses: [Range<Double>], pausedSince: Double? = nil) -> RecordingPauseTimeline {
        RecordingPauseTimeline(pauses: pauses, pausedSince: pausedSince)
    }

    @Test func pausesAndResumesOnce() {
        var pauses = RecordingPauseTimeline()
        let paused = pauses.pause(at: 10)
        let pausedAgain = pauses.pause(at: 11)
        #expect(paused && !pausedAgain)
        #expect(pauses.isPaused)
        let resumed = pauses.resume(at: 14)
        let resumedAgain = pauses.resume(at: 15)
        #expect(resumed && !resumedAgain)
        #expect(pauses.pauses == [10 ..< 14])
        #expect(!pauses.isPaused)
    }

    @Test func ignoresEmptyPauses() {
        var pauses = RecordingPauseTimeline()
        pauses.pause(at: 5)
        pauses.resume(at: 5)
        #expect(pauses.pauses.isEmpty)
        #expect(pauses.isEmpty)
    }

    @Test func neverOverlapsAnEarlierPause() {
        var pauses = timeline([2 ..< 6])
        pauses.pause(at: 4)
        pauses.resume(at: 8)
        #expect(pauses.pauses == [2 ..< 6, 6 ..< 8])
    }

    @Test func recordedDurationSkipsPauses() {
        let pauses = timeline([10 ..< 14, 20 ..< 21])
        #expect(pauses.recordedDuration(from: 0, to: 30) == 25)
        #expect(pauses.recordedDuration(from: 0, to: 12) == 10)
        #expect(pauses.recordedDuration(from: 0, to: 5) == 5)
        #expect(pauses.recordedDuration(from: 12, to: 30) == 15)
    }

    @Test func recordedDurationFreezesWhilePaused() {
        let pauses = timeline([], pausedSince: 8)
        #expect(pauses.recordedDuration(from: 0, to: 8) == 8)
        #expect(pauses.recordedDuration(from: 0, to: 20) == 8)
        #expect(pauses.closed(at: 12).recordedDuration(from: 0, to: 20) == 16)
    }

    @Test func mapsEventTimesAcrossPauses() {
        let pauses = timeline([10 ..< 14])
        #expect(pauses.outputTime(of: 105, recordingStart: 100) == 5)
        #expect(pauses.outputTime(of: 112, recordingStart: 100) == 12)
        #expect(pauses.outputTime(of: 109, recordingStart: 100) == 9)
        let absolute = timeline([110 ..< 114])
        #expect(absolute.outputTime(of: 112, recordingStart: 100) == nil)
        #expect(absolute.outputTime(of: 114, recordingStart: 100) == 10)
        #expect(absolute.outputTime(of: 120, recordingStart: 100) == 16)
        #expect(absolute.outputTime(of: 99, recordingStart: 100) == -1)
    }

    @Test func dropsEventsDuringAnOpenPause() {
        let pauses = timeline([], pausedSince: 105)
        #expect(pauses.outputTime(of: 104, recordingStart: 100) == 4)
        #expect(pauses.outputTime(of: 130, recordingStart: 100) == nil)
    }

    @Test func segmentsMatchTheUnpausedPlacement() {
        let pauses = RecordingPauseTimeline()
        #expect(
            pauses.segments(sourceStart: 100.5, sourceDuration: 3, recordingStart: 100, outputDuration: 2)
                == [RecordingMediaSegment(sourceStart: 0, outputStart: 0.5, duration: 1.5)])
        #expect(
            pauses.segments(sourceStart: 99, sourceDuration: 4, recordingStart: 100, outputDuration: 5)
                == [RecordingMediaSegment(sourceStart: 1, outputStart: 0, duration: 3)])
        #expect(pauses.segments(sourceStart: 110, sourceDuration: 2, recordingStart: 100, outputDuration: 5).isEmpty)
    }

    @Test func segmentsSkipThePausedPartOfAClip() {
        let pauses = timeline([105 ..< 108])
        let segments = pauses.segments(sourceStart: 100, sourceDuration: 20, recordingStart: 100, outputDuration: 12)
        #expect(
            segments == [
                RecordingMediaSegment(sourceStart: 0, outputStart: 0, duration: 5),
                RecordingMediaSegment(sourceStart: 8, outputStart: 5, duration: 7),
            ])
    }

    @Test func segmentsHandleAClipThatStartsDuringAPause() {
        let pauses = timeline([105 ..< 108])
        let segments = pauses.segments(sourceStart: 106, sourceDuration: 10, recordingStart: 100, outputDuration: 20)
        #expect(segments == [RecordingMediaSegment(sourceStart: 2, outputStart: 5, duration: 8)])
    }

    @Test func segmentsStopAtAnOpenPause() {
        let pauses = timeline([], pausedSince: 104)
        let segments = pauses.segments(sourceStart: 100, sourceDuration: 30, recordingStart: 100, outputDuration: 4)
        #expect(segments == [RecordingMediaSegment(sourceStart: 0, outputStart: 0, duration: 4)])
    }

    @Test func recordedSpansCoverEverythingButPauses() {
        let spans = timeline([5 ..< 7, 9 ..< 10]).recordedSpans(from: 0)
        #expect(spans.count == 3)
        #expect(spans[0].start == 0 && spans[0].end == 5)
        #expect(spans[1].start == 7 && spans[1].end == 9)
        #expect(spans[2].start == 10)
        #expect(spans[2].end == .infinity)
    }
}
