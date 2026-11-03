import Testing
@testable import ishareCore

struct SelectionOrderTests {
    @Test func acceptsFreezeFramesCapturedBeforeTheSelectorAppears() {
        var log = SelectionOrderLog(expectsFreezeFrames: true)
        log.record(.freezeFramesReady(at: 1.0))
        log.record(.selectorShown(at: 1.05))
        #expect(log.violation == nil)
    }

    @Test func flagsASelectorShownBeforeItsFreezeFrames() {
        var log = SelectionOrderLog(expectsFreezeFrames: true)
        log.record(.selectorShown(at: 1.0))
        log.record(.freezeFramesReady(at: 1.2))
        #expect(log.violation?.contains("200 ms") == true)
        var missing = SelectionOrderLog(expectsFreezeFrames: true)
        missing.record(.selectorShown(at: 1.0))
        #expect(missing.violation != nil)
    }

    @Test func ignoresLiveSelectionWithoutFreezeFrames() {
        var log = SelectionOrderLog(expectsFreezeFrames: false)
        log.record(.selectorShown(at: 1.0))
        #expect(log.violation == nil)
    }

    @Test func reusesOnlyFreshPrefetches() {
        #expect(SelectionPrefetchPolicy.isUsable(startedAt: 10, now: 10.5))
        #expect(!SelectionPrefetchPolicy.isUsable(startedAt: 10, now: 11))
        #expect(!SelectionPrefetchPolicy.isUsable(startedAt: nil, now: 10))
        #expect(!SelectionPrefetchPolicy.isUsable(startedAt: 10, now: 9))
    }
}
