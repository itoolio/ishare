import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ishare

struct RecordingChapterTests {
    @Test func namesMarkersInTimeOrder() {
        var log = RecordingMarkerLog()
        log.add(at: 5)
        log.add(at: 2)
        let late = log.add(at: 9)
        #expect(late.title == "Marker 3")
        #expect(log.markers == [
            RecordingMarker(time: 2, title: "Marker 1"),
            RecordingMarker(time: 5, title: "Marker 2"),
            RecordingMarker(time: 9, title: "Marker 3"),
        ])
    }

    @Test func clampsNegativeMarkerTimes() {
        var log = RecordingMarkerLog()
        #expect(log.add(at: -0.4).time == 0)
    }

    @Test func buildsChaptersThatCoverTheWholeRecording() {
        let markers = RecordingChapters.markers(at: [3, 7.5])
        let chapters = RecordingChapters.chapters(for: markers, duration: 12)
        #expect(chapters == [
            RecordingChapter(title: "Start", start: 0, end: 3),
            RecordingChapter(title: "Marker 1", start: 3, end: 7.5),
            RecordingChapter(title: "Marker 2", start: 7.5, end: 12),
        ])
    }

    @Test func aMarkerAtTheBeginningReplacesTheOpeningChapter() {
        let chapters = RecordingChapters.chapters(for: RecordingChapters.markers(at: [0.04, 4]), duration: 6)
        #expect(chapters.map(\.title) == ["Marker 1", "Marker 2"])
        #expect(chapters.first?.start == 0)
        #expect(chapters.last?.end == 6)
    }

    @Test func dropsMarkersAtTheEndAndMergesMarkersTooCloseTogether() {
        let markers = RecordingChapters.markers(at: [2, 2.05, 9.97])
        let chapters = RecordingChapters.chapters(for: markers, duration: 10)
        #expect(chapters == [
            RecordingChapter(title: "Start", start: 0, end: 2),
            RecordingChapter(title: "Marker 2", start: 2, end: 10),
        ])
        #expect(RecordingChapters.chapters(for: [], duration: 10).isEmpty)
        #expect(RecordingChapters.chapters(for: markers, duration: 0).isEmpty)
    }

    @Test func rebasesMarkersOntoATrimmedRange() {
        let markers = RecordingChapters.markers(at: [1, 4, 8])
        let rebased = RecordingChapters.rebased(markers, to: 3 ... 6)
        #expect(rebased == [RecordingMarker(time: 1, title: "Marker 2")])
    }

    @Test func encodesChapterTitlesAsTextSamples() throws {
        let payload = ChapterTextSample.payload(for: "Intro")
        #expect(Array(payload.prefix(2)) == [0, 5])
        #expect(String(data: payload.subdata(in: 2 ..< 7), encoding: .utf8) == "Intro")
        #expect(Array(payload.suffix(12)) == [0, 0, 0, 12, 0x65, 0x6E, 0x63, 0x64, 0, 0, 1, 0])
        let format = try #require(ChapterTextSample.formatDescription())
        #expect(format.mediaType == .text)
    }
}

struct CaptionLayoutTests {
    @Test func formatsSRTTimestamps() {
        #expect(SRTFormatter.timestamp(0) == "00:00:00,000")
        #expect(SRTFormatter.timestamp(61.5) == "00:01:01,500")
        #expect(SRTFormatter.timestamp(3723.0456) == "01:02:03,046")
        #expect(SRTFormatter.timestamp(-1) == "00:00:00,000")
    }

    @Test func writesNumberedSRTCues() {
        let cues = [
            CaptionCue(start: 0.5, end: 2, lines: ["Hello there"]),
            CaptionCue(start: 2.25, end: 4, lines: ["Second line", "wraps here"]),
        ]
        #expect(SRTFormatter.string(for: cues) == "1\n00:00:00,500 --> 00:00:02,000\nHello there\n\n2\n00:00:02,250 --> 00:00:04,000\nSecond line\nwraps here\n")
        #expect(SRTFormatter.subtitleURL(for: URL(fileURLWithPath: "/tmp/clip.mov")).path == "/tmp/clip.srt")
    }

    @Test func wrapsWordsAtFortyTwoCharacters() {
        let words = "The quick brown fox jumps over the lazy dog and keeps running far away".split(separator: " ").map(String.init)
        let lines = CaptionLayout.wrap(words)
        #expect(lines.allSatisfy { $0.count <= 42 })
        #expect(lines.joined(separator: " ") == words.joined(separator: " "))
        #expect(lines.count == 2)
    }

    @Test func splitsLongTranscriptsIntoTwoLineCues() {
        let text = (1 ... 40).map { "word\($0)" }.joined(separator: " ")
        let cues = CaptionLayout.cues(from: [TranscriptSegment(text: text, start: 0, end: 20)])
        #expect(cues.count > 1)
        for cue in cues {
            #expect(cue.lines.count <= 2)
            #expect(cue.lines.allSatisfy { $0.count <= 42 })
            #expect(cue.end > cue.start)
            #expect(cue.end - cue.start <= CaptionLayout.maxCueDuration + 0.001)
        }
        #expect(cues.flatMap(\.lines).joined(separator: " ") == text)
        #expect(cues.first?.start == 0)
        #expect(abs((cues.last?.end ?? 0) - 20) < 0.001)
        for (current, next) in zip(cues, cues.dropFirst()) {
            #expect(current.end <= next.start)
        }
    }

    @Test func startsANewCueAfterAPauseOrASentence() {
        let segments = [
            TranscriptSegment(text: "Hello", start: 0, end: 0.4),
            TranscriptSegment(text: "world.", start: 0.45, end: 0.9),
            TranscriptSegment(text: "Next", start: 1, end: 1.3),
            TranscriptSegment(text: "thing", start: 1.35, end: 1.6),
            TranscriptSegment(text: "later", start: 4, end: 4.5),
        ]
        let cues = CaptionLayout.cues(from: segments)
        #expect(cues.map(\.text) == ["Hello world.", "Next thing", "later"])
        #expect(abs(cues[0].end - 0.9) < 0.0001)
        #expect(abs(cues[1].end - 1.8) < 0.0001)
        #expect(cues[2].start == 4)
    }

    @Test func breaksWordsLongerThanALine() {
        let longWord = String(repeating: "a", count: 100)
        let cues = CaptionLayout.cues(from: [TranscriptSegment(text: longWord, start: 0, end: 3)])
        #expect(cues.flatMap(\.lines).allSatisfy { $0.count <= 42 })
        #expect(cues.flatMap(\.lines).joined() == longWord)
        #expect(cues.allSatisfy { $0.lines.count <= 2 })
    }
}

struct RecordingExportSettingsTests {
    @Test func mapsFormatsToContainersAndCodecs() {
        #expect(RecordingExportFormat.mp4H264.fileType == .mp4)
        #expect(RecordingExportFormat.mp4H264.videoCodec == .h264)
        #expect(RecordingExportFormat.mp4HEVC.videoCodec == .hevc)
        #expect(RecordingExportFormat.mov.fileType == .mov)
        #expect(RecordingExportFormat.m4a.fileType == .m4a)
        #expect(RecordingExportFormat.m4a.videoCodec == nil)
        #expect(RecordingExportFormat.gif.fileType == nil)
        #expect(RecordingExportFormat.allCases.map(\.fileExtension) == ["mp4", "mp4", "mov", "gif", "m4a"])
    }

    @Test(arguments: [
        (RecordingExportSize.original, CGSize(width: 2880, height: 1800), CGSize(width: 2880, height: 1800)),
        (.p1080, CGSize(width: 2880, height: 1800), CGSize(width: 1728, height: 1080)),
        (.p720, CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 720)),
        (.p480, CGSize(width: 1080, height: 1920), CGSize(width: 480, height: 854)),
        (.p1080, CGSize(width: 1280, height: 720), CGSize(width: 1280, height: 720)),
    ])
    func scalesTheShortSideWithoutUpscaling(size: RecordingExportSize, source: CGSize, expected: CGSize) {
        #expect(size.outputSize(for: source) == expected)
    }

    @Test func buildsVideoSettingsForTheChosenSizeAndQuality() throws {
        let settings = RecordingExportSettings(format: .mp4H264, size: .p720, quality: .medium)
        let video = try #require(settings.videoOutputSettings(sourceSize: CGSize(width: 1920, height: 1080), frameRate: 30))
        #expect(video[AVVideoCodecKey] as? AVVideoCodecType == .h264)
        #expect(video[AVVideoWidthKey] as? Int == 1280)
        #expect(video[AVVideoHeightKey] as? Int == 720)
        let compression = try #require(video[AVVideoCompressionPropertiesKey] as? [String: Any])
        #expect(compression[AVVideoAverageBitRateKey] as? Int == Int(1280 * 720 * 30 * 0.1))
        #expect(RecordingExportSettings(format: .m4a).videoOutputSettings(sourceSize: CGSize(width: 100, height: 100), frameRate: 30) == nil)
    }

    @Test func smallerQualityAndHEVCUseLessBitrate() {
        let size = CGSize(width: 1920, height: 1080)
        let bitRates = RecordingExportQuality.allCases.map { RecordingExportSettings(quality: $0).videoBitRate(for: size, frameRate: 60, codec: .h264) }
        #expect(bitRates == bitRates.sorted(by: >))
        let hevc = RecordingExportSettings().videoBitRate(for: size, frameRate: 60, codec: .hevc)
        #expect(hevc < bitRates[0])
        #expect(RecordingExportSettings(quality: .small).videoBitRate(for: CGSize(width: 10, height: 10), frameRate: 1, codec: .h264) == 250_000)
    }

    @Test func removingAudioDropsTheAudioSettingsExceptForAudioOnlyExports() {
        #expect(RecordingExportSettings(format: .mp4H264, removesAudio: true).audioOutputSettings(channelCount: 2, sampleRate: 48000) == nil)
        #expect(RecordingExportSettings(format: .gif).includesAudio == false)
        let m4a = RecordingExportSettings(format: .m4a, quality: .small, removesAudio: true)
        let audio = m4a.audioOutputSettings(channelCount: 6, sampleRate: 96000)
        #expect(audio?[AVNumberOfChannelsKey] as? Int == 2)
        #expect(audio?[AVSampleRateKey] as? Double == 48000)
        #expect(audio?[AVEncoderBitRateKey] as? Int == 96000)
    }

    @Test func mapsSizesOntoGIFPresets() {
        #expect(RecordingExportSettings(format: .gif, size: .p480, gifFrameRate: .fps10).gifPreset == GIFPreset(frameRate: .fps10, maxSize: .p480))
    }
}

struct OverlayMappingTests {
    @Test func mapsGlobalPointsIntoTheRecordedWindow() {
        let window = CGRect(x: 200, y: 100, width: 800, height: 600)
        let videoSize = CGSize(width: 1600, height: 1200)
        #expect(OverlayCoordinateMapper.videoPoint(CGPoint(x: 300, y: 150), sourceRect: window, videoSize: videoSize) == CGPoint(x: 200, y: 100))
        #expect(OverlayCoordinateMapper.videoPoint(CGPoint(x: 1000, y: 700), sourceRect: window, videoSize: videoSize) == nil)
        #expect(OverlayCoordinateMapper.videoPoint(CGPoint(x: 100, y: 150), sourceRect: window, videoSize: videoSize) == nil)
        #expect(OverlayCoordinateMapper.pixelsPerPoint(sourceSize: window.size, videoSize: videoSize) == 2)
    }

    @Test func accountsForLetterboxingWhenTheWindowAspectDiffers() {
        let window = CGRect(x: 0, y: 0, width: 400, height: 400)
        let videoSize = CGSize(width: 1600, height: 800)
        #expect(OverlayCoordinateMapper.contentFrame(sourceSize: window.size, videoSize: videoSize) == CGRect(x: 400, y: 0, width: 800, height: 800))
        #expect(OverlayCoordinateMapper.videoPoint(CGPoint(x: 100, y: 200), sourceRect: window, videoSize: videoSize) == CGPoint(x: 600, y: 400))
    }

    @Test func convertsCocoaPointsToTopLeftGlobalCoordinates() {
        #expect(OverlayCoordinateMapper.cgGlobalPoint(fromCocoa: CGPoint(x: 50, y: 900), primaryScreenHeight: 1000) == CGPoint(x: 50, y: 100))
        #expect(OverlayCoordinateMapper.flipped(CGPoint(x: 10, y: 30), videoHeight: 100) == CGPoint(x: 10, y: 70))
    }

    @Test func placesTheWebcamInTheChosenCornerOfTheVideo() throws {
        let layout = OverlayCompositionLayout.make(videoSize: CGSize(width: 2000, height: 1200), sourceSize: CGSize(width: 1000, height: 600), webcamDiameter: 180, corner: .bottomRight)
        let frame = try #require(layout.webcamFrame)
        #expect(layout.pixelsPerPoint == 2)
        #expect(frame == CGRect(x: 2000 - 48 - 360, y: 48, width: 360, height: 360))
        let topLeft = try #require(OverlayCompositionLayout.make(videoSize: CGSize(width: 2000, height: 1200), sourceSize: CGSize(width: 1000, height: 600), webcamDiameter: 180, corner: .topLeft).webcamFrame)
        #expect(topLeft.origin == CGPoint(x: 48, y: 1200 - 48 - 360))
        #expect(OverlayCompositionLayout.make(videoSize: CGSize(width: 100, height: 100), sourceSize: CGSize(width: 100, height: 100), webcamDiameter: nil, corner: .topLeft).webcamFrame == nil)
        #expect(layout.keystrokeCenter() == CGPoint(x: 1000, y: 128))
    }
}

struct OverlayTimelineTests {
    @Test func timesClicksRelativeToTheRecordingStart() {
        var log = OverlayEventLog()
        let window = CGRect(x: 0, y: 0, width: 500, height: 500)
        log.recordClick(at: CGPoint(x: 10, y: 20), sourceRect: window, time: 99)
        log.recordClick(at: CGPoint(x: 100, y: 50), sourceRect: window, time: 102.5)
        log.recordClick(at: CGPoint(x: 900, y: 50), sourceRect: window, time: 103)
        log.recordClick(at: CGPoint(x: 100, y: 60), sourceRect: window, time: 200)
        let timeline = log.timeline(recordingStart: 100, videoSize: CGSize(width: 1000, height: 1000), duration: 10)
        #expect(timeline.clicks == [OverlayClick(time: 2.5, point: CGPoint(x: 200, y: 100))])
        #expect(timeline.ripples(at: 2.4).isEmpty)
        #expect(abs((timeline.ripples(at: 2.8).first?.progress ?? 0) - 0.5) < 0.0001)
        #expect(timeline.ripples(at: 3.15).first?.progress == 1)
        #expect(timeline.ripples(at: 3.25).isEmpty)
    }

    @Test func buildsKeystrokeSpansLikeTheLiveOverlay() {
        let typed = { (text: String) in Keystroke(text: text, kind: .typed) }
        let undo = Keystroke(text: "⌘Z", kind: .shortcut)
        let spans = OverlayTimeline.keystrokeSpans(for: [
            (1, typed("h")),
            (1.2, typed("i")),
            (5, undo),
            (5.3, undo),
        ])
        #expect(spans.map(\.text) == ["h", "hi", "⌘Z", "⌘Z ×2"])
        #expect(spans.map(\.start) == [1, 1.2, 5, 5.3])
        let expectedEnds = [1.2, 2.8, 5.3, 6.9]
        #expect(zip(spans.map(\.end), expectedEnds).allSatisfy { abs($0 - $1) < 0.0001 })
        let timeline = OverlayTimeline(keystrokes: spans)
        #expect(timeline.keystroke(at: 2) == "hi")
        #expect(timeline.keystroke(at: 3) == nil)
        #expect(timeline.keystroke(at: 6) == "⌘Z ×2")
    }

    @Test func clipsSpansToTheRecording() {
        let key = Keystroke(text: "⌘S", kind: .shortcut)
        let spans = OverlayTimeline.keystrokeSpans(for: [(-1, key), (9.5, key), (12, key)], duration: 10)
        #expect(spans == [OverlayKeystrokeSpan(start: 9.5, end: 10, text: "⌘S")])
    }
}

@Suite(.serialized)
struct RecordingPipelineMediaTests {
    @Test func writesChaptersThatPlayersCanRead() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 320, height: 240), seconds: 3, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        try await RecordingChapters.write(RecordingChapters.markers(at: [1, 2]), into: video)
        let chapters = try await RecordingChapters.read(from: video)
        #expect(chapters.map(\.title) == ["Start", "Marker 1", "Marker 2"])
        #expect(chapters.map { ($0.start * 10).rounded() / 10 } == [0, 1, 2])
        let asset = AVURLAsset(url: video)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 3) < 0.1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: video.deletingLastPathComponent().path)
        #expect(leftovers == [video.lastPathComponent])
    }

    @Test func exportsAResizedMP4WithoutAudio() async throws {
        let video = try await SyntheticVideo.makeWithAudio(size: CGSize(width: 960, height: 540), seconds: 2)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }
        #expect(try await AVURLAsset(url: video).loadTracks(withMediaType: .audio).count == 1)

        let settings = RecordingExportSettings(format: .mp4H264, size: .p480, quality: .small, removesAudio: true)
        let output = try await RecordingConversions.export(video, settings: settings, deletingSource: false)
        #expect(output.pathExtension == "mp4")
        #expect(FileManager.default.fileExists(atPath: video.path))
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 854, height: 480))
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.15)
    }

    @Test func exportsARangeAsMOVWithAudio() async throws {
        let video = try await SyntheticVideo.makeWithAudio(size: CGSize(width: 640, height: 480), seconds: 3)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        let range = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        let output = try await RecordingConversions.export(video, settings: RecordingExportSettings(format: .mov, size: .original), range: range, deletingSource: true)
        #expect(output == video)
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 640, height: 480))
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.15)
    }

    @Test func exportsAudioOnly() async throws {
        let video = try await SyntheticVideo.makeWithAudio(size: CGSize(width: 320, height: 240), seconds: 2)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        let output = try await RecordingConversions.export(video, settings: RecordingExportSettings(format: .m4a), deletingSource: true)
        #expect(output.pathExtension == "m4a")
        #expect(!FileManager.default.fileExists(atPath: video.path))
        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    @Test func compositesClicksKeystrokesAndWebcamOntoTheVideo() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 640, height: 480), seconds: 2, frameRate: 30)
        let webcam = try await SyntheticVideo.make(size: CGSize(width: 320, height: 240), seconds: 3, frameRate: 15)
        defer {
            try? FileManager.default.removeItem(at: video.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: webcam.deletingLastPathComponent())
        }
        let asset = AVURLAsset(url: video)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let duration = try await asset.load(.duration)
        let timeline = OverlayTimeline(
            clicks: [OverlayClick(time: 0.5, point: CGPoint(x: 120, y: 100))],
            keystrokes: [OverlayKeystrokeSpan(start: 0, end: 2, text: "⌘K")],
            webcam: OverlayWebcamClip(url: webcam, offset: -0.5)
        )
        let layout = OverlayCompositionLayout.make(videoSize: CGSize(width: 640, height: 480), sourceSize: CGSize(width: 640, height: 480), webcamDiameter: 120, corner: .bottomRight)
        try await OverlayCompositor.composite(asset, screenTrack: track, duration: duration, timeline: timeline, layout: layout, replacing: video, hevc: false, progress: nil)

        let result = AVURLAsset(url: video)
        let resultTrack = try #require(try await result.loadTracks(withMediaType: .video).first)
        #expect(try await resultTrack.load(.naturalSize) == CGSize(width: 640, height: 480))
        #expect(abs(try await result.load(.duration).seconds - 2) < 0.15)

        let generator = AVAssetImageGenerator(asset: result)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 0.55, preferredTimescale: 600)).image
        let ripple = try #require(PixelProbe.rgb(in: frame, x: 120 + 10, y: 100))
        let mirrored = try #require(PixelProbe.rgb(in: frame, x: 120 + 10, y: 480 - 100))
        #expect(ripple.red - ripple.blue > 25)
        #expect(abs(mirrored.red - mirrored.blue) < 12)
    }

    @Test func burnsCaptionsIntoTheVideo() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 640, height: 360), seconds: 2, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        try await CaptionBurner.burn([CaptionCue(start: 0, end: 2, lines: ["Hello captions"])], into: video, hevc: false)
        let asset = AVURLAsset(url: video)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 640, height: 360))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 1.9, preferredTimescale: 600)).image
        let boxBottom = Int(CaptionStyle.bottomMargin(forRenderHeight: 360))
        let inside = try #require(PixelProbe.rgb(in: frame, x: 320 - 55, y: 360 - boxBottom - 2))
        let above = try #require(PixelProbe.rgb(in: frame, x: 320 - 55, y: 40))
        #expect(above.red - inside.red > 100)
    }
}

enum PixelProbe {
    static func rgb(in image: CGImage, x: Int, y: Int) -> (red: Int, green: Int, blue: Int)? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }
}

extension SyntheticVideo {
    static func makeWithAudio(size: CGSize, seconds: Int) async throws -> URL {
        let silent = try await make(size: size, seconds: seconds, frameRate: 30)
        let directory = silent.deletingLastPathComponent()
        let audioURL = directory.appending(path: "tone.m4a")
        try writeTone(to: audioURL, seconds: Double(seconds))

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent)
        let audioAsset = AVURLAsset(url: audioURL)
        let duration = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        let videoTrack = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
        let audioDuration = try await audioAsset.load(.duration)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(range, of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, audioDuration)), of: audioTrack, at: .zero)

        let output = directory.appending(path: "clip-audio.mov")
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: output, as: .mov)
        try FileManager.default.removeItem(at: silent)
        try FileManager.default.removeItem(at: audioURL)
        return output
    }

    private static func writeTone(to url: URL, seconds: Double) throws {
        let sampleRate = 44100.0
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0 ..< Int(frameCount) {
            samples[index] = Float(sin(2 * .pi * 440 * Double(index) / sampleRate) * 0.3)
        }
        try file.write(from: buffer)
    }
}
