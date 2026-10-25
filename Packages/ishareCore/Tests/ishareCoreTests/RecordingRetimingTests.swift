import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct RetimingPlanTests {
    let plan = RetimingPlan(segments: [
        RetimingSegment(start: 0, end: 2, action: .keep),
        RetimingSegment(start: 2, end: 6, action: .remove),
        RetimingSegment(start: 6, end: 8, action: .keep),
        RetimingSegment(start: 8, end: 12, action: .speed(4)),
        RetimingSegment(start: 12, end: 13, action: .keep),
    ])

    @Test func measuresSourceAndOutputDurations() {
        #expect(plan.sourceDuration == 13)
        #expect(plan.outputDuration == 2 + 2 + 1 + 1)
        #expect(!plan.isIdentity)
        #expect(plan.hasSpeedChanges)
        #expect(plan.changedSegments.count == 2)
    }

    @Test func mapsSourceTimesForward() {
        #expect(plan.outputTime(forSource: 1) == 1)
        #expect(plan.outputTime(forSource: 3) == nil)
        #expect(plan.outputTime(forSource: 7) == 3)
        #expect(plan.outputTime(forSource: 10) == 4.5)
        #expect(plan.outputTime(forSource: 12.5) == 5.5)
        #expect(plan.outputTime(forSource: 20) == 6)
    }

    @Test func mapsOutputTimesBack() {
        #expect(plan.sourceTime(forOutput: 1) == 1)
        #expect(plan.sourceTime(forOutput: 3) == 7)
        #expect(plan.sourceTime(forOutput: 4.5) == 10)
        #expect(plan.sourceTime(forOutput: 100) == 13)
    }

    @Test func roundTripsKeptTimes() {
        for source in stride(from: 0.1, through: 13, by: 0.25) {
            guard let output = plan.outputTime(forSource: source) else { continue }
            #expect(abs(plan.sourceTime(forOutput: output) - source) < 0.000_1)
        }
    }

    @Test func mergesAdjacentSegmentsWithTheSameAction() {
        let merged = RetimingPlan(segments: [
            RetimingSegment(start: 0, end: 1, action: .keep),
            RetimingSegment(start: 1, end: 2, action: .keep),
            RetimingSegment(start: 2, end: 2, action: .remove),
        ])
        #expect(merged.segments == [RetimingSegment(start: 0, end: 2, action: .keep)])
        #expect(merged.isIdentity)
    }

    @Test func restrictingToATrimRangeRemovesTheOutside() {
        let trimmed = RetimingPlan.identity(duration: 10).restricted(to: 2 ... 5)
        #expect(trimmed.outputDuration == 3)
        #expect(trimmed.outputTime(forSource: 1) == nil)
        #expect(trimmed.outputTime(forSource: 3) == 1)
        #expect(trimmed.outputTime(forSource: 6) == nil)
        let combined = plan.restricted(to: 1 ... 9)
        #expect(combined.outputDuration == 1 + 2 + 0.25)
        #expect(combined.outputTime(forSource: 7) == 2)
    }
}

struct SilencePlannerTests {
    private func series(_ values: [Double], step: Double = 0.25) -> LevelSeries {
        LevelSeries(step: step, values: values)
    }

    @Test func findsStretchesThatAreBothQuietAndStill() {
        let audio = series(Array(repeating: -20, count: 8) + Array(repeating: -80, count: 16) + Array(repeating: -20, count: 8))
        let motion = series(Array(repeating: 0, count: 32))
        let ranges = SilencePlanner.quietRanges(audio: audio, motion: motion, duration: 8, settings: SilenceDetectionSettings(minimumDuration: 2))
        #expect(ranges.count == 1)
        #expect(abs(ranges[0].lowerBound - 2) < 0.06)
        #expect(abs(ranges[0].upperBound - 6) < 0.06)
    }

    @Test func movementKeepsSilentStretches() {
        let audio = series(Array(repeating: -80, count: 32))
        let motion = series(Array(repeating: 0, count: 12) + [0.2] + Array(repeating: 0, count: 19))
        let ranges = SilencePlanner.quietRanges(audio: audio, motion: motion, duration: 8, settings: SilenceDetectionSettings(minimumDuration: 2.5))
        #expect(ranges.count == 2)
        #expect(abs(ranges[0].upperBound - 3) < 0.06)
        #expect(abs(ranges[1].lowerBound - 3.25) < 0.06)
    }

    @Test func ignoresShortPauses() {
        let audio = series(Array(repeating: -20, count: 4) + Array(repeating: -80, count: 4) + Array(repeating: -20, count: 4))
        let ranges = SilencePlanner.quietRanges(audio: audio, motion: nil, duration: 3, settings: SilenceDetectionSettings(minimumDuration: 2))
        #expect(ranges.isEmpty)
    }

    @Test func padsAroundKeptPartsButNotAtTheEdges() {
        let settings = SilenceDetectionSettings(padding: 0.5, speed: .remove)
        let plan = SilencePlanner.plan(quietRanges: [0 ... 3, 5 ... 9, 12 ... 14], duration: 14, settings: settings)
        #expect(
            plan.segments == [
                RetimingSegment(start: 0, end: 3 - 0.5, action: .remove),
                RetimingSegment(start: 2.5, end: 5.5, action: .keep),
                RetimingSegment(start: 5.5, end: 8.5, action: .remove),
                RetimingSegment(start: 8.5, end: 12.5, action: .keep),
                RetimingSegment(start: 12.5, end: 14, action: .remove),
            ])
    }

    @Test func speedsUpInsteadOfRemoving() {
        let plan = SilencePlanner.plan(quietRanges: [2 ... 6], duration: 8, settings: SilenceDetectionSettings(padding: 0, speed: .quadruple))
        #expect(plan.segments.map(\.action) == [.keep, .speed(4), .keep])
        #expect(plan.outputDuration == 5)
        #expect(!RetimingAction.speed(4).keepsAudio)
    }

    @Test func treatsMissingAudioAsSilence() {
        let motion = series(Array(repeating: 0, count: 40))
        let plan = SilencePlanner.plan(audio: nil, motion: motion, duration: 10, settings: SilenceDetectionSettings())
        #expect(plan.outputDuration == 0)
    }

    @Test func clampsSettings() {
        let settings = SilenceDetectionSettings(audioThreshold: -200, motionThreshold: 5, minimumDuration: 0, padding: -1)
        #expect(settings.audioThreshold == -70)
        #expect(settings.motionThreshold == 0.1)
        #expect(settings.minimumDuration == 0.5)
        #expect(settings.padding == 0)
    }

    @Test func combinesLevelSeriesByTakingTheLoudest() throws {
        let quiet = LevelSeries(step: 0.5, values: [-80, -80, -80, -80])
        let voice = LevelSeries(start: 1, step: 0.5, values: [-10, -10])
        let combined = try #require(LevelSeries.loudest([quiet, voice]))
        #expect(combined.value(at: 0.25) == -80)
        #expect(combined.value(at: 1.25) == -10)
        #expect(combined.value(at: 1.75) == -10)
    }
}

struct FrameMathTests {
    @Test func measuresFrameDifferences() {
        #expect(FrameDifference.meanAbsoluteDifference([0, 0], [0, 0]) == 0)
        #expect(FrameDifference.meanAbsoluteDifference([0, 255], [255, 255]) == 0.5)
        #expect(FrameDifference.decibels(rms: 1) == 0)
        #expect(abs(FrameDifference.decibels(rms: 0.1) + 20) < 0.000_1)
        #expect(FrameDifference.decibels(rms: 0) == -160)
    }

    @Test func mergesDuplicateFramesIntoLongerDelays() {
        let frames = AnimatedFrameDedupe.merged(delays: [0.1, 0.1, 0.1, 0.1, 0.1], isDuplicate: [false, true, true, false, true])
        #expect(frames.map(\.sourceIndex) == [0, 3])
        #expect(abs(frames[0].delay - 0.3) < 0.000_1)
        #expect(abs(frames[1].delay - 0.2) < 0.000_1)
        #expect(AnimatedFrameDedupe.merged(delays: [0.1], isDuplicate: [true]).count == 1)
    }
}

struct DuckingEnvelopeTests {
    let settings = DuckingSettings(speechThreshold: -40, reduction: 20, attack: 0.1, release: 0.5, hold: 0.2)

    @Test func convertsDecibelsToGain() {
        #expect(abs(DuckingEnvelope.linearGain(decibels: -20) - 0.1) < 0.000_1)
        #expect(abs(settings.duckedGain - 0.1) < 0.000_1)
    }

    @Test func holdsSpeechAcrossShortGaps() {
        let levels = LevelSeries(step: 0.1, values: [-80, -10, -10, -80, -10, -80, -80, -80, -80, -80])
        let ranges = DuckingEnvelope.speakingRanges(levels: levels, threshold: -40, hold: 0.2)
        #expect(ranges.count == 1)
        #expect(abs(ranges[0].lowerBound - 0.1) < 0.000_1)
        #expect(abs(ranges[0].upperBound - 0.7) < 0.000_1)
    }

    @Test func ducksWhileSpeakingWithRamps() {
        let levels = LevelSeries(step: 0.5, values: [-80, -80, -10, -10, -80, -80, -80, -80])
        let points = DuckingEnvelope.points(levels: levels, settings: settings, duration: 4)
        #expect(DuckingEnvelope.gain(at: 0.5, points: points) == 1)
        #expect(abs(DuckingEnvelope.gain(at: 0.95, points: points) - 0.55) < 0.000_1)
        #expect(abs(DuckingEnvelope.gain(at: 1.5, points: points) - 0.1) < 0.000_1)
        #expect(abs(DuckingEnvelope.gain(at: 2.2, points: points) - 0.1) < 0.000_1)
        #expect(abs(DuckingEnvelope.gain(at: 2.45, points: points) - 0.55) < 0.000_1)
        #expect(DuckingEnvelope.gain(at: 3.5, points: points) == 1)
        #expect(points.last?.time == 4)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.time <= $1.time })
    }

    @Test func mergesNearbyPhrasesIntoOneDip() {
        let levels = LevelSeries(step: 0.5, values: [-10, -80, -10, -80, -80, -80])
        let points = DuckingEnvelope.points(levels: levels, settings: settings, duration: 3)
        #expect(DuckingEnvelope.gain(at: 0.9, points: points) < 0.2)
        #expect(DuckingEnvelope.gain(at: 0, points: points) < 0.2)
    }

    @Test func staysAtFullGainWithoutSpeech() {
        let levels = LevelSeries(step: 0.5, values: [-80, -80])
        let points = DuckingEnvelope.points(levels: levels, settings: settings, duration: 1)
        #expect(points.allSatisfy { $0.gain == 1 })
    }
}

struct BlurRegionTests {
    let first = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let second = CGRect(x: 0.5, y: 0.3, width: 0.4, height: 0.2)

    @Test func interpolatesBetweenKeyframesAndHoldsAtTheEnds() throws {
        let track = RegionTrack(keyframes: [RegionKeyframe(time: 2, rect: second), RegionKeyframe(time: 0, rect: first)])
        #expect(track.rect(at: -1) == first)
        #expect(track.rect(at: 5) == second)
        let middle = try #require(track.rect(at: 1))
        #expect(abs(middle.minX - 0.3) < 0.000_1)
        #expect(abs(middle.minY - 0.2) < 0.000_1)
        #expect(abs(middle.width - 0.3) < 0.000_1)
    }

    @Test func addsOrReplacesManualKeyframes() {
        var track = RegionTrack(keyframes: [RegionKeyframe(time: 0, rect: first)])
        track.setKeyframe(second, at: 1)
        #expect(track.keyframes.count == 2)
        track.setKeyframe(first, at: 1.005)
        #expect(track.keyframes.count == 2)
        #expect(track.keyframes[1].rect == first)
        #expect(track.keyframes[1].isManual)
        track.removeKeyframe(near: 1)
        #expect(track.keyframes.count == 1)
    }

    @Test func clampsRectsIntoTheFrame() {
        let clamped = RegionGeometry.clampedToUnit(CGRect(x: 0.9, y: -0.2, width: 0.3, height: 0.3))
        #expect(abs(clamped.minX - 0.7) < 0.000_1)
        #expect(clamped.minY == 0)
        #expect(clamped.maxX <= 1)
    }

    @Test func trackingKeepsManualKeyframes() {
        var track = RegionTrack(keyframes: [RegionKeyframe(time: 1, rect: first, isManual: true), RegionKeyframe(time: 3, rect: first)])
        let tracked = stride(from: 0.0, through: 4, by: 0.5).map { RegionKeyframe(time: $0, rect: second) }
        track.replaceTracked(with: tracked)
        #expect(track.keyframes.filter(\.isManual).map(\.time) == [1])
        #expect(!track.keyframes.contains { $0.time == 1 && !$0.isManual })
        #expect(track.keyframes.count == tracked.count)
        #expect(track.rect(at: 1) == first)
    }

    @Test func limitsRegionsToTheirTimeRange() {
        let region = BlurRegion(start: 1, end: 2, track: RegionTrack(keyframes: [RegionKeyframe(time: 1.5, rect: first)]))
        #expect(region.rect(at: 0.5) == nil)
        #expect(region.rect(at: 1.5) == first)
        #expect(region.rect(at: 2.5) == nil)
        let retimed = region.retimed { $0 >= 1 ? $0 - 1 : nil }
        #expect(retimed?.start == 0)
        #expect(retimed?.track.keyframes.first?.time == 0.5)
    }

    @Test func smoothsJitterAndDropsRedundantKeyframes() {
        let jittery = (0 ..< 30).map { index -> RegionKeyframe in
            let wobble: CGFloat = index.isMultiple(of: 2) ? 0.01 : -0.01
            return RegionKeyframe(time: Double(index) / 10, rect: CGRect(x: 0.1 + CGFloat(index) * 0.01 + wobble, y: 0.2, width: 0.1, height: 0.1))
        }
        let smoothed = TrackSmoothing.smoothed(jittery, radius: 2)
        let rawJitter = zip(jittery, jittery.dropFirst()).map { abs($1.rect.minX - $0.rect.minX - 0.01) }.max() ?? 0
        let smoothJitter = zip(smoothed.dropFirst(2).dropLast(2), smoothed.dropFirst(3).dropLast(2)).map { abs($1.rect.minX - $0.rect.minX - 0.01) }.max() ?? 0
        #expect(smoothJitter < rawJitter / 2)

        let linear = (0 ..< 20).map { RegionKeyframe(time: Double($0), rect: CGRect(x: CGFloat($0) * 0.02, y: 0, width: 0.1, height: 0.1)) }
        let simplified = TrackSmoothing.simplified(linear, tolerance: 0.001)
        #expect(simplified.map(\.time) == [0, 19])

        let corner = linear.prefix(10) + (0 ..< 10).map { RegionKeyframe(time: Double(10 + $0), rect: CGRect(x: 0.18, y: CGFloat($0 + 1) * 0.05, width: 0.1, height: 0.1)) }
        #expect(TrackSmoothing.simplified(Array(corner), tolerance: 0.001).count == 3)
    }

    @Test func linksDetectionsAcrossSamplesIntoRegions() {
        let a = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
        let b = CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.05)
        let detections = [
            RegionDetection(time: 0, rects: [a]),
            RegionDetection(time: 1, rects: [a.offsetBy(dx: 0.01, dy: 0), b]),
            RegionDetection(time: 2, rects: [b]),
            RegionDetection(time: 5, rects: [a]),
        ]
        let chains = RegionLinker.link(detections, maximumGap: 1.5)
        #expect(chains.map(\.count) == [2, 2, 1])
        let regions = RegionLinker.regions(from: detections, interval: 1, duration: 6, style: .pixelate)
        #expect(regions.count == 3)
        #expect(regions[0].start == 0)
        #expect(regions[0].end == 1.5)
        #expect(regions[2].end == 5.5)
        #expect(regions.allSatisfy { $0.style == .pixelate })
        #expect(regions[0].track.keyframes[0].rect.width > a.width)
    }

    @Test func measuresOverlap() {
        #expect(abs(RegionGeometry.intersectionOverUnion(first, first) - 1) < 0.000_1)
        #expect(RegionGeometry.intersectionOverUnion(first, second) == 0)
        #expect(RegionGeometry.flippedVertically(CGRect(x: 0, y: 0, width: 0.5, height: 0.25)) == CGRect(x: 0, y: 0.75, width: 0.5, height: 0.25))
    }
}
