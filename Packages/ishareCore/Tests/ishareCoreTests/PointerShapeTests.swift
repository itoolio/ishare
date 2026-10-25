import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct PointerShapeTrackTests {
    let arrow = PointerShape(fingerprint: 1, hotSpot: CGPoint(x: 4, y: 4), size: CGSize(width: 24, height: 24))
    let beam = PointerShape(fingerprint: 2, hotSpot: CGPoint(x: 12, y: 12), size: CGSize(width: 24, height: 24))
    let hand = PointerShape(fingerprint: 3, hotSpot: CGPoint(x: 9, y: 2), size: CGSize(width: 32, height: 32))

    @Test func storesEachDistinctShapeOnce() {
        var track = PointerShapeTrack()
        let first = track.record(arrow, at: 0)
        let repeated = track.record(arrow, at: 0.1)
        let beamFirst = track.record(beam, at: 0.2)
        let arrowAgain = track.record(arrow, at: 0.3)
        let beamAgain = track.record(beam, at: 0.4)
        #expect(first.isNew && !repeated.isNew && beamFirst.isNew && !arrowAgain.isNew && !beamAgain.isNew)
        #expect(track.shapes == [arrow, beam])
        #expect(track.changes.map(\.shape) == [0, 1, 0, 1])
        #expect(track.changes.map(\.time) == [0, 0.2, 0.3, 0.4])
    }

    @Test func treatsADifferentHotSpotAsANewShape() {
        var track = PointerShapeTrack()
        track.record(arrow, at: 0)
        var moved = arrow
        moved.hotSpot = CGPoint(x: 5, y: 5)
        #expect(track.record(moved, at: 1).isNew)
    }

    @Test func looksUpTheShapeInEffectAtATime() {
        var track = PointerShapeTrack()
        track.record(arrow, at: 1)
        track.record(beam, at: 2)
        track.record(hand, at: 5)
        #expect(track.shape(at: 0) == arrow)
        #expect(track.shape(at: 1) == arrow)
        #expect(track.shape(at: 1.99) == arrow)
        #expect(track.shape(at: 2) == beam)
        #expect(track.shape(at: 4.9) == beam)
        #expect(track.shape(at: 100) == hand)
        #expect(PointerShapeTrack().shape(at: 1) == nil)
    }

    @Test func retimesChangesAndKeepsTheLatestShapeAtACollision() {
        var track = PointerShapeTrack()
        track.record(arrow, at: 98)
        track.record(beam, at: 99)
        track.record(hand, at: 105)
        track.record(arrow, at: 106)
        track.record(beam, at: 110)
        let pauses = RecordingPauseTimeline(pauses: [104 ..< 108])
        let retimed = track.retimed { pauses.recordedDuration(from: 100, to: $0) }
        #expect(retimed.changes == [PointerShapeChange(time: 0, shape: 1), PointerShapeChange(time: 4, shape: 0), PointerShapeChange(time: 6, shape: 1)])
        #expect(retimed.shape(at: 3) == beam)
        #expect(retimed.shape(at: 5) == arrow)
    }

    @Test func placesTheHotSpotOnTheTip() {
        let origin = hand.origin(forTip: CGPoint(x: 100, y: 100), scale: 2)
        #expect(origin == CGPoint(x: 82, y: 40))
    }
}
