import AVFoundation
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ishare

struct KeystrokeFormatterTests {
    @Test func formatsShortcutsInSystemModifierOrder() {
        let keystroke = KeystrokeFormatter.keystroke(keyCode: kVK_ANSI_4, characters: "$", baseCharacters: "4", modifiers: [.command, .shift], shortcutsOnly: true)
        #expect(keystroke == Keystroke(text: "⇧⌘4", kind: .shortcut))
    }

    @Test func uppercasesLetterShortcuts() {
        let keystroke = KeystrokeFormatter.keystroke(keyCode: kVK_ANSI_C, characters: "c", baseCharacters: "c", modifiers: [.control, .option], shortcutsOnly: true)
        #expect(keystroke?.text == "⌃⌥C")
    }

    @Test func hidesPlainTypingWhenOnlyShortcutsAreShown() {
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_ANSI_A, characters: "A", baseCharacters: "a", modifiers: [.shift], shortcutsOnly: true) == nil)
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_Space, characters: " ", baseCharacters: " ", modifiers: [], shortcutsOnly: true) == nil)
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_Return, characters: "\r", baseCharacters: "\r", modifiers: [], shortcutsOnly: true) == nil)
    }

    @Test func showsTypedCharactersWhenAllKeysAreShown() {
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_ANSI_A, characters: "A", baseCharacters: "a", modifiers: [.shift], shortcutsOnly: false) == Keystroke(text: "A", kind: .typed))
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_Space, characters: " ", baseCharacters: " ", modifiers: [], shortcutsOnly: false) == Keystroke(text: " ", kind: .typed))
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_Return, characters: "\r", baseCharacters: "\r", modifiers: [], shortcutsOnly: false) == Keystroke(text: "↩", kind: .shortcut))
    }

    @Test func alwaysShowsEscapeAndFunctionKeys() {
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_Escape, characters: "\u{1B}", baseCharacters: "\u{1B}", modifiers: [], shortcutsOnly: true)?.text == "⎋")
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_F5, characters: "\u{F708}", baseCharacters: "\u{F708}", modifiers: [], shortcutsOnly: true)?.text == "F5")
        #expect(KeystrokeFormatter.keystroke(keyCode: kVK_Space, characters: " ", baseCharacters: " ", modifiers: [.command], shortcutsOnly: true)?.text == "⌘Space")
    }

    @Test func ignoresUnprintableKeysWithoutAName() {
        #expect(KeystrokeFormatter.keystroke(keyCode: 0x7F, characters: "\u{F746}", baseCharacters: "\u{F746}", modifiers: [.command], shortcutsOnly: false) == nil)
    }
}

struct KeystrokeTickerTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func joinsTypedCharactersTypedInQuickSuccession() {
        var ticker = KeystrokeTicker()
        for (offset, character) in "hey".enumerated() {
            ticker.register(Keystroke(text: String(character), kind: .typed), at: start.addingTimeInterval(Double(offset) * 0.2))
        }
        #expect(ticker.text == "hey")
        ticker.register(Keystroke(text: "!", kind: .typed), at: start.addingTimeInterval(5))
        #expect(ticker.text == "!")
    }

    @Test func countsRepeatedShortcuts() {
        var ticker = KeystrokeTicker()
        let undo = Keystroke(text: "⌘Z", kind: .shortcut)
        ticker.register(undo, at: start)
        ticker.register(undo, at: start.addingTimeInterval(0.3))
        ticker.register(undo, at: start.addingTimeInterval(0.6))
        #expect(ticker.text == "⌘Z ×3")
        ticker.register(Keystroke(text: "⌘S", kind: .shortcut), at: start.addingTimeInterval(0.9))
        #expect(ticker.text == "⌘S")
    }

    @Test func keepsOnlyTheTailOfLongTypedRuns() {
        var ticker = KeystrokeTicker()
        for index in 0 ..< 40 {
            ticker.register(Keystroke(text: "a", kind: .typed), at: start.addingTimeInterval(Double(index) * 0.05))
        }
        #expect(ticker.text.count == KeystrokeTicker.maximumTypedLength)
    }

    @Test func expiresAfterTheInterval() {
        var ticker = KeystrokeTicker()
        #expect(ticker.isExpired(at: start, after: 1))
        ticker.register(Keystroke(text: "⌘C", kind: .shortcut), at: start)
        #expect(!ticker.isExpired(at: start.addingTimeInterval(0.5), after: 1))
        #expect(ticker.isExpired(at: start.addingTimeInterval(1.5), after: 1))
    }
}

struct OverlayGeometryTests {
    @Test func convertsGlobalPointsIntoTopLeftWindowSpace() {
        let frame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(OverlayGeometry.localPoint(CGPoint(x: 1540, y: 1000), in: frame) == CGPoint(x: 100, y: 80))
        #expect(OverlayGeometry.localRect(CGRect(x: 1540, y: 100, width: 200, height: 300), in: frame) == CGRect(x: 100, y: 680, width: 200, height: 300))
    }
}

struct WebcamBubbleLayoutTests {
    private let area = CGRect(x: 100, y: 50, width: 1000, height: 800)

    @Test(arguments: [
        (WebcamCorner.bottomLeft, CGPoint(x: 124, y: 74)),
        (WebcamCorner.bottomRight, CGPoint(x: 896, y: 74)),
        (WebcamCorner.topLeft, CGPoint(x: 124, y: 646)),
        (WebcamCorner.topRight, CGPoint(x: 896, y: 646)),
    ])
    func placesTheBubbleInTheChosenCorner(corner: WebcamCorner, origin: CGPoint) {
        let frame = WebcamBubbleLayout.frame(diameter: 180, corner: corner, in: area)
        #expect(frame.origin == origin)
        #expect(frame.size == CGSize(width: 180, height: 180))
    }

    @Test func shrinksTheBubbleToFitSmallAreas() {
        let frame = WebcamBubbleLayout.frame(diameter: 260, corner: .bottomRight, in: CGRect(x: 0, y: 0, width: 400, height: 200))
        #expect(frame.width == 152)
        #expect(frame.maxX == 376)
        let tiny = WebcamBubbleLayout.frame(diameter: 260, corner: .topLeft, in: CGRect(x: 0, y: 0, width: 90, height: 90))
        #expect(tiny.width == 42)
    }

    @Test func sizesGrowFromSmallToLarge() {
        let diameters = WebcamBubbleSize.allCases.map(\.diameter)
        #expect(diameters == diameters.sorted())
    }
}

struct TrimSelectionTests {
    @Test func startsAtFullLength() {
        let selection = TrimSelection(duration: 12)
        #expect(selection.isFullLength)
        #expect(selection.length == 12)
    }

    @Test func clampsHandlesInsideTheDurationAndApart() {
        var selection = TrimSelection(duration: 10)
        selection.setStart(-3)
        #expect(selection.start == 0)
        selection.setEnd(42)
        #expect(selection.end == 10)
        selection.setStart(9.95)
        #expect(selection.start == 10 - TrimSelection.minimumLength)
        selection.setEnd(0)
        #expect(selection.end == selection.start + TrimSelection.minimumLength)
        #expect(!selection.isFullLength)
    }

    @Test func buildsTheExportRange() {
        var selection = TrimSelection(duration: 10)
        selection.setStart(2)
        selection.setEnd(6.5)
        #expect(abs(selection.timeRange.start.seconds - 2) < 0.002)
        #expect(abs(selection.timeRange.duration.seconds - 4.5) < 0.002)
        #expect(selection.clampedPlayhead(9) == 6.5)
        #expect(selection.fraction(of: 5) == 0.5)
        #expect(selection.time(atFraction: 1.4) == 10)
    }
}

struct GIFMathTests {
    @Test(arguments: [10, 15, 20, 30])
    func delaysAddUpToTheRealDuration(frameRate: Int) {
        let delays = GIFTiming.centisecondDelays(frameCount: frameRate * 3, frameRate: frameRate)
        #expect(delays.count == frameRate * 3)
        #expect(delays.reduce(0, +) == 300)
        let nominal = 100.0 / Double(frameRate)
        #expect(delays.allSatisfy { abs(Double($0) - nominal) < 1 })
    }

    @Test func offsetsFrameTimesByTheRangeStart() {
        let range = CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        let times = GIFTiming.frameTimes(in: range, frameRate: 15)
        #expect(times.count == 15)
        #expect(abs(times[0].seconds - 2) < 0.002)
        #expect(abs(times[14].seconds - (2 + 14.0 / 15)) < 0.002)
    }

    @Test(arguments: [
        (GIFMaxSize.original, CGSize(width: 3024, height: 1964), CGSize(width: 3024, height: 1964)),
        (GIFMaxSize.p1080, CGSize(width: 3024, height: 1964), CGSize(width: 1663, height: 1080)),
        (GIFMaxSize.p720, CGSize(width: 1080, height: 1920), CGSize(width: 720, height: 1280)),
        (GIFMaxSize.p480, CGSize(width: 640, height: 360), CGSize(width: 640, height: 360)),
    ])
    func scalesWithoutUpscaling(maxSize: GIFMaxSize, input: CGSize, expected: CGSize) {
        #expect(GIFGeometry.outputSize(for: input, maxSize: maxSize) == expected)
    }

    @Test func accountsForRotatedTracks() {
        let rotated = GIFGeometry.displaySize(naturalSize: CGSize(width: 1920, height: 1080), transform: CGAffineTransform(rotationAngle: .pi / 2))
        #expect(abs(rotated.width - 1080) < 0.001)
        #expect(abs(rotated.height - 1920) < 0.001)
    }

    @Test func picksAFreeDestinationNextToTheVideo() {
        let video = URL(fileURLWithPath: "/tmp/recordings/clip.mov")
        #expect(GIFConverter.destinationURL(for: video) { _ in false }.lastPathComponent == "clip.gif")
        let taken: Set<String> = ["clip.gif", "clip-2.gif"]
        #expect(GIFConverter.destinationURL(for: video) { taken.contains($0.lastPathComponent) }.lastPathComponent == "clip-3.gif")
    }
}

struct PowerMeterTests {
    @Test func reportsLouderSignalsHigher() throws {
        let quiet = try Self.meterLevel(amplitude: 0.05)
        let loud = try Self.meterLevel(amplitude: 0.8)
        #expect(quiet > 0)
        #expect(loud > quiet)
        #expect(loud <= 1)
        #expect(try Self.meterLevel(amplitude: 0) == 0)
    }

    private static func meterLevel(amplitude: Float) throws -> Float {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0 ..< Int(buffer.frameLength) {
            samples[index] = amplitude * sin(Float(index) * 2 * .pi * 440 / 48000)
        }
        let meter = PowerMeter()
        meter.process(buffer: buffer)
        return meter.levels.level
    }
}

@Suite(.serialized)
struct RecordingMediaTests {
    @Test func convertsAVideoIntoATimedGIF() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 960, height: 720), seconds: 2, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        let gif = try await RecordingConversions.convertToGIF(video, preset: GIFPreset(frameRate: .fps10, maxSize: .p480))
        #expect(FileManager.default.fileExists(atPath: video.path))
        #expect(gif.pathExtension == "gif")

        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 20)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 640)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 480)
        let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        #expect(abs((gifProperties[kCGImagePropertyGIFDelayTime] as? Double ?? 0) - 0.1) < 0.001)
    }

    @Test func convertsOnlyTheSelectedRange() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 320, height: 240), seconds: 2, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        let range = CMTimeRange(start: CMTime(seconds: 0.5, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        let gif = try await RecordingConversions.convertToGIF(video, range: range, preset: GIFPreset(frameRate: .fps20, maxSize: .original), deletingSource: true)
        #expect(!FileManager.default.fileExists(atPath: video.path))
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 20)
    }

    @Test func trimsAVideoInPlaceWithPassthrough() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 320, height: 240), seconds: 3, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        let range = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        let trimmed = try await VideoTrimmer.trimInPlace(video, range: range)
        #expect(trimmed == video)
        let duration = try await AVURLAsset(url: trimmed).load(.duration).seconds
        #expect(abs(duration - 1) < 0.15)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: video.deletingLastPathComponent().path)
        #expect(leftovers == [video.lastPathComponent])
    }
}

enum SyntheticVideo {
    static func make(size: CGSize, seconds: Int, frameRate: Int32) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-recording-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "clip.mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frameCount = seconds * Int(frameRate)
        for index in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let pool = try #require(adaptor.pixelBufferPool)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try #require(pixelBuffer)
            fill(buffer, shade: UInt8(index * 255 / max(1, frameCount - 1)))
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: frameRate))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: frameRate))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    private static func fill(_ buffer: CVPixelBuffer, shade: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
        memset(base, Int32(shade), bytes)
    }
}
