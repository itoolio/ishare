import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Testing
@testable import ishare

struct RecordingNotesLayoutTests {
    @Test func placesTheDefaultPanelInTheTopRightCorner() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = RecordingNotesLayout.defaultFrame(in: visible)
        #expect(frame.size == RecordingNotesLayout.defaultSize)
        #expect(frame.maxX == visible.maxX - RecordingNotesLayout.inset)
        #expect(frame.maxY == visible.maxY - RecordingNotesLayout.inset)
    }

    @Test func shrinksThePanelOnSmallScreensButKeepsTheMinimum() {
        let frame = RecordingNotesLayout.defaultFrame(in: CGRect(x: 0, y: 0, width: 200, height: 150))
        #expect(frame.size == RecordingNotesLayout.minimumSize)
    }

    @Test func clampsTheFontSize() {
        #expect(RecordingNotesLayout.steppedFontSize(18, by: 2) == 20)
        #expect(RecordingNotesLayout.steppedFontSize(11, by: -2) == RecordingNotesLayout.fontSizeRange.lowerBound)
        #expect(RecordingNotesLayout.steppedFontSize(71, by: 2) == RecordingNotesLayout.fontSizeRange.upperBound)
    }
}

struct TeleprompterScrollTests {
    @Test func scrollsAtTheChosenSpeed() {
        #expect(TeleprompterScroll.offset(elapsed: 2, speed: 30, contentHeight: 1000, viewportHeight: 200) == 60)
    }

    @Test func stopsAtTheEndOfTheText() {
        #expect(TeleprompterScroll.offset(elapsed: 100, speed: 30, contentHeight: 1000, viewportHeight: 200) == 800)
        #expect(TeleprompterScroll.hasReachedEnd(elapsed: 100, speed: 30, contentHeight: 1000, viewportHeight: 200))
        #expect(!TeleprompterScroll.hasReachedEnd(elapsed: 1, speed: 30, contentHeight: 1000, viewportHeight: 200))
    }

    @Test func staysStillWithoutSpeedOrWhenTheTextFits() {
        #expect(TeleprompterScroll.offset(elapsed: 10, speed: 0, contentHeight: 1000, viewportHeight: 200) == 0)
        #expect(TeleprompterScroll.offset(elapsed: 10, speed: 40, contentHeight: 100, viewportHeight: 200) == 0)
        #expect(TeleprompterScroll.offset(elapsed: -1, speed: 40, contentHeight: 1000, viewportHeight: 200) == 0)
    }
}

struct RecordingCaptureExclusionTests {
    @Test func neverAddsTheNotesWindowBackIntoTheCapture() {
        let ids = RecordingCaptureExclusion.capturedOverlayIDs(overlays: [10, 11, 42], privateWindows: [42])
        #expect(ids == [10, 11])
    }

    @Test func keepsAllOverlaysWhenTheNotesAreClosed() {
        #expect(RecordingCaptureExclusion.capturedOverlayIDs(overlays: [10, 11], privateWindows: [nil]) == [10, 11])
    }
}

private struct FakeApp: BundleIdentified, Equatable {
    var bundleIdentifier: String
}

struct RecordingAudioPlanTests {
    @Test func turningAudioOffWinsOverTheChosenSource() {
        #expect(RecordingAudioSource.resolved(recordAudio: false, source: .selectedApps) == .none)
        #expect(RecordingAudioSource.resolved(recordAudio: true, source: .selectedApps) == .selectedApps)
    }

    @Test func choosesThePlanForEachSource() {
        #expect(RecordingAudioPlan.make(source: .none, selectedBundleIDs: ["a"], style: .display) == .silent)
        #expect(RecordingAudioPlan.make(source: .allSystemAudio, selectedBundleIDs: [], style: .display) == .contentAudio)
        #expect(RecordingAudioPlan.make(source: .selectedApps, selectedBundleIDs: ["a", "b", ""], style: .display) == .applications(["a", "b"]))
        #expect(RecordingAudioPlan.make(source: .selectedApps, selectedBundleIDs: [], style: .display) == .silent)
    }

    @Test func singleAppRecordingsUseThatAppsAudio() {
        #expect(RecordingAudioPlan.make(source: .selectedApps, selectedBundleIDs: ["a"], style: .application) == .contentAudio)
        #expect(RecordingAudioPlan.make(source: .selectedApps, selectedBundleIDs: [], style: .window) == .contentAudio)
        #expect(RecordingAudioPlan.make(source: .none, selectedBundleIDs: [], style: .window) == .silent)
    }

    @Test func mapsContentStyles() {
        #expect(RecordingContentStyle(.window) == .window)
        #expect(RecordingContentStyle(.application) == .application)
        #expect(RecordingContentStyle(.display) == .display)
        #expect(RecordingContentStyle(.none) == .display)
    }
}

struct RecordingAudioFilterTests {
    @Test func includesOnlySelectedAppsAndNeverItself() {
        let apps = [FakeApp(bundleIdentifier: "com.music"), FakeApp(bundleIdentifier: "com.browser"), FakeApp(bundleIdentifier: "dev.adrian.ishare")]
        let included = RecordingAudioFilter.applications(apps, matching: ["com.music", "dev.adrian.ishare", "com.missing"], ownBundleID: "dev.adrian.ishare")
        #expect(included == [FakeApp(bundleIdentifier: "com.music")])
    }

    @Test func audioOnlyStreamCapturesSoundButAlmostNoVideo() {
        let configuration = RecordingAudioFilter.audioOnlyConfiguration()
        #expect(configuration.capturesAudio)
        #expect(configuration.excludesCurrentProcessAudio)
        #expect(configuration.width == 2 && configuration.height == 2)
        #expect(configuration.minimumFrameInterval == CMTime(value: 1, timescale: 1))
        #expect(!configuration.showsCursor)
    }

    @Test func mainStreamOnlyCapturesAudioForContentAudio() {
        let configuration = SCStreamConfiguration()
        RecordingAudioFilter.apply(.contentAudio, to: configuration)
        #expect(configuration.capturesAudio)
        #expect(configuration.excludesCurrentProcessAudio)
        RecordingAudioFilter.apply(.applications(["a"]), to: configuration)
        #expect(!configuration.capturesAudio)
        RecordingAudioFilter.apply(.silent, to: configuration)
        #expect(!configuration.capturesAudio)
    }
}

struct AppAudioPlacementTests {
    @Test func delaysAudioThatStartedAfterTheVideo() {
        let placement = AppAudioPlacement.make(audioStart: 100.5, recordingStart: 100, audioDuration: 3, videoDuration: 2)
        #expect(placement == AppAudioPlacement(sourceStart: 0, destinationStart: 0.5, length: 1.5))
    }

    @Test func skipsAudioThatStartedBeforeTheVideo() {
        let placement = AppAudioPlacement.make(audioStart: 99, recordingStart: 100, audioDuration: 4, videoDuration: 5)
        #expect(placement == AppAudioPlacement(sourceStart: 1, destinationStart: 0, length: 3))
    }

    @Test func ignoresAudioOutsideTheVideo() {
        #expect(AppAudioPlacement.make(audioStart: 110, recordingStart: 100, audioDuration: 2, videoDuration: 5) == nil)
    }
}

struct AudioAppChoiceTests {
    @Test func listsRunningAppsAndKeepsSelectedOnesThatAreClosed() {
        let choices = AudioAppChoice.choices(running: [(id: "b", name: "Browser"), (id: "a", name: "Audio")], selected: ["z.closed", "a"])
        #expect(choices.map(\.id) == ["a", "b", "z.closed"])
        #expect(choices.last?.isRunning == false)
    }

    @Test func togglesSelection() {
        #expect(AudioAppChoice.toggled("a", in: ["a", "b"]) == ["b"])
        #expect(AudioAppChoice.toggled("c", in: ["a"]) == ["a", "c"])
    }
}

struct ReplaySegmentRingTests {
    private func segment(_ start: Double, _ end: Double) -> ReplaySegment {
        ReplaySegment(url: URL(fileURLWithPath: "/tmp/segment-\(start).mov"), start: start, end: end)
    }

    @Test func keepsJustEnoughSegmentsToCoverTheCapacity() {
        var ring = ReplaySegmentRing(capacity: 10)
        var evicted: [ReplaySegment] = []
        for index in 0 ..< 5 {
            evicted += ring.append(segment(Double(index * 5), Double(index * 5 + 5)))
        }
        #expect(ring.segments.map(\.start) == [15, 20])
        #expect(evicted.map(\.start) == [0, 5, 10])
        #expect(ring.totalDuration == 10)
    }

    @Test func replayWindowTrimsTheOldestSegment() {
        var ring = ReplaySegmentRing(capacity: 10)
        ring.append(segment(0, 4))
        ring.append(segment(4, 8))
        ring.append(segment(8, 12))
        let window = ring.replayWindow()
        #expect(window.segments.count == 3)
        #expect(window.trimStart == 2)
    }

    @Test func shortBuffersAreSavedWhole() {
        var ring = ReplaySegmentRing(capacity: 30)
        ring.append(segment(0, 5))
        #expect(ring.replayWindow().trimStart == 0)
    }

    @Test func rejectsEmptySegmentsAndClears() {
        var ring = ReplaySegmentRing(capacity: 30)
        let rejected = ring.append(segment(3, 3))
        #expect(rejected.count == 1)
        #expect(ring.segments.isEmpty)
        ring.append(segment(0, 5))
        #expect(ring.removeAll().count == 1)
        #expect(ring.segments.isEmpty)
    }

    @Test func rotatesAfterTheSegmentLength() {
        #expect(!ReplaySegmentRing.shouldRotate(segmentStart: 10, now: 14.9, segmentLength: 5))
        #expect(ReplaySegmentRing.shouldRotate(segmentStart: 10, now: 15, segmentLength: 5))
    }

    @Test func durationsMatchTheSetting() {
        #expect(InstantReplayDuration.allCases.map(\.seconds) == [30, 60, 120])
    }
}

struct InstantReplayConditionsTests {
    @Test func pausesWhenLockedOrAsleep() {
        #expect(InstantReplayConditions(isScreenLocked: true).shouldPause)
        #expect(InstantReplayConditions(isAsleep: true).shouldPause)
        #expect(!InstantReplayConditions().shouldPause)
    }

    @Test func pausesOnLowBatteryOnly() {
        #expect(InstantReplayConditions(isOnBattery: true, batteryLevel: 0.19).shouldPause)
        #expect(!InstantReplayConditions(isOnBattery: true, batteryLevel: 0.2).shouldPause)
        #expect(!InstantReplayConditions(isOnBattery: false, batteryLevel: 0.05).shouldPause)
        #expect(!InstantReplayConditions(isOnBattery: true, batteryLevel: nil).shouldPause)
    }

    @Test func scalesTheBitRateWithinLimits() {
        #expect(InstantReplayEncoding.bitRate(for: CGSize(width: 2, height: 2), frameRate: 1) == 1_500_000)
        #expect(InstantReplayEncoding.bitRate(for: CGSize(width: 7680, height: 4320), frameRate: 60) == 40_000_000)
    }
}

struct WebcamPreviewAreaTests {
    @Test func convertsWindowBoundsToCocoaCoordinates() {
        let rect = WebcamBubblePreviewArea.cocoaRect(fromCGGlobal: CGRect(x: 100, y: 50, width: 800, height: 600), primaryScreenHeight: 1000)
        #expect(rect == CGRect(x: 100, y: 350, width: 800, height: 600))
    }
}

enum SyntheticAudio {
    static func make(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ishare-audio-\(UUID().uuidString).m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
            ])
        let frames = AVAudioFrameCount(seconds * 48000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0 ..< 2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for index in 0 ..< Int(frames) {
                samples[index] = sin(Float(index) * 2 * .pi * 440 / 48000) * 0.3
            }
        }
        try file.write(from: buffer)
        return url
    }
}

struct RecordingCompanionMediaTests {
    @Test func mergesSelectedAppsAudioAtTheRightOffset() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 64, height: 48), seconds: 2, frameRate: 10)
        let audio = try SyntheticAudio.make(seconds: 3)
        defer {
            try? FileManager.default.removeItem(at: video.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: audio)
        }
        try await AppAudioMuxer.merge(AppAudioClip(url: audio, startTime: 100.5), into: video, recordingStart: 100)

        let merged = AVURLAsset(url: video)
        #expect(try await merged.loadTracks(withMediaType: .video).count == 1)
        let audioTracks = try await merged.loadTracks(withMediaType: .audio)
        #expect(audioTracks.count == 1)
        let track = try #require(audioTracks.first)
        let segments = try await track.load(.segments)
        let leadingSilence = segments.first(where: \.isEmpty)?.timeMapping.target.duration.seconds ?? 0
        let range = try await track.load(.timeRange)
        #expect(abs(leadingSilence - 0.5) < 0.1)
        #expect(abs(range.end.seconds - 2) < 0.15)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: video.deletingLastPathComponent().path)
        #expect(leftovers == [video.lastPathComponent])
    }

    @Test func exportsTheLastSecondsOfTheRingBuffer() async throws {
        var segments: [ReplaySegment] = []
        for index in 0 ..< 3 {
            let url = try await SyntheticVideo.make(size: CGSize(width: 64, height: 48), seconds: 2, frameRate: 10)
            segments.append(ReplaySegment(url: url, start: Double(index * 2), end: Double(index * 2 + 2)))
        }
        let output = FileManager.default.temporaryDirectory.appending(path: "ishare-replay-\(UUID().uuidString).mov")
        defer {
            segments.forEach { try? FileManager.default.removeItem(at: $0.url.deletingLastPathComponent()) }
            try? FileManager.default.removeItem(at: output)
        }
        var ring = ReplaySegmentRing(capacity: 4)
        segments.forEach { ring.append($0) }
        let window = ring.replayWindow()
        #expect(window.segments.count == 2)

        try await InstantReplayExporter.export(window.segments, trimStart: window.trimStart, to: output)
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 4) < 0.2)
    }
}
