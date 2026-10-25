import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import ishareCore
import Testing
import UniformTypeIdentifiers
@testable import ishare

enum SyntheticClip {
    static func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-postprocess-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func video(in directory: URL, size: CGSize, seconds: Double, frameRate: Int32 = 30, draw: (Int, Double, CGContext) -> Void) async throws -> URL {
        let url = directory.appending(path: "video-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1, AVVideoAverageBitRateKey: 8_000_000],
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int(seconds * Double(frameRate))
        for index in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let pool = try #require(adaptor.pixelBufferPool)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try #require(pixelBuffer)
            render(buffer) { draw(index, Double(index) / Double(frameRate), $0) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: frameRate))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: frameRate))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    static func audio(in directory: URL, seconds: Double, frequency: Double = 440, amplitude: (Double) -> Double) throws -> URL {
        let url = directory.appending(path: "audio-\(UUID().uuidString).m4a")
        let sampleRate = 44100.0
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(
            forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000])
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0 ..< Int(frameCount) {
            let time = Double(index) / sampleRate
            samples[index] = Float(sin(2 * .pi * frequency * time) * amplitude(time))
        }
        try file.write(from: buffer)
        return url
    }

    static func combine(video: URL, audio: URL, in directory: URL) async throws -> URL {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let duration = try await videoAsset.load(.duration)
        let videoTrack = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
        let audioDuration = try await audioAsset.load(.duration)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, audioDuration)), of: audioTrack, at: .zero)
        let output = directory.appending(path: "clip.mov")
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: output, as: .mov)
        return output
    }

    static func fill(_ context: CGContext, gray: CGFloat, size: CGSize) {
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
    }

    static func checker(_ context: CGContext, in rect: CGRect, cell: CGFloat) {
        let columns = Int(rect.width / cell)
        let rows = Int(rect.height / cell)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let white = (row + column).isMultiple(of: 2)
                context.setFillColor(CGColor(red: white ? 1 : 0, green: white ? 1 : 0, blue: white ? 1 : 0, alpha: 1))
                context.fill(CGRect(x: rect.minX + CGFloat(column) * cell, y: rect.minY + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
    }

    private static func render(_ buffer: CVPixelBuffer, _ body: (CGContext) -> Void) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        context.translateBy(x: 0, y: CGFloat(CVPixelBufferGetHeight(buffer)))
        context.scaleBy(x: 1, y: -1)
        body(context)
    }
}

@Suite(.serialized)
struct AnimatedExportTests {
    private func source(_ url: URL) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    @Test func exportsAnAnimatedPNGWithDelaysAndLoopCount() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 320, height: 240), seconds: 2, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }

        let settings = RecordingExportSettings(format: .apng, size: .original, gifFrameRate: .fps10)
        let output = try await RecordingConversions.export(video, settings: settings, deletingSource: false)
        #expect(output.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: video.path))
        let image = try source(output)
        #expect(CGImageSourceGetType(image) as String? == UTType.png.identifier)
        #expect(CGImageSourceGetCount(image) == 20)
        let container = try #require(CGImageSourceCopyProperties(image, nil) as? [CFString: Any])
        let png = try #require(container[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        #expect(png[kCGImagePropertyAPNGLoopCount] as? Int == 0)
        let frame = try #require(CGImageSourceCopyPropertiesAtIndex(image, 3, nil) as? [CFString: Any])
        let framePNG = try #require(frame[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        #expect(abs((framePNG[kCGImagePropertyAPNGDelayTime] as? Double ?? 0) - 0.1) < 0.001)
        #expect(frame[kCGImagePropertyPixelWidth] as? Int == 320)
    }

    @Test(arguments: [AnimatedImageFormat.gif, .apng])
    func mergesRepeatedFramesIntoLongerDelays(format: AnimatedImageFormat) async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = CGSize(width: 160, height: 120)
        let video = try await SyntheticClip.video(in: directory, size: size, seconds: 2) { _, time, context in
            SyntheticClip.fill(context, gray: time < 1 ? 0.1 : 0.9, size: size)
        }
        let output = try await RecordingConversions.convertToAnimation(
            video, format: format, range: nil, preset: GIFPreset(frameRate: .fps10, maxSize: .original), deletingSource: true)
        #expect(!FileManager.default.fileExists(atPath: video.path))
        let image = try source(output)
        #expect(CGImageSourceGetCount(image) == 2)
        for index in 0 ..< 2 {
            let frame = try #require(CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any])
            let dictionary = try #require(frame[format.containerKey] as? [CFString: Any])
            let delayKey = format == .gif ? kCGImagePropertyGIFDelayTime : kCGImagePropertyAPNGDelayTime
            #expect(abs((dictionary[delayKey] as? Double ?? 0) - 1) < 0.02)
        }
    }

    @Test func exportsWebPOnlyWhenImageIOCanEncodeIt() async throws {
        let video = try await SyntheticVideo.make(size: CGSize(width: 160, height: 120), seconds: 1, frameRate: 30)
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }
        let settings = RecordingExportSettings(format: .webp, size: .original, gifFrameRate: .fps10)
        #expect(RecordingExportFormat.webp.isAvailable == AnimatedImageFormat.encodableTypeIdentifiers.contains("org.webmproject.webp"))
        guard AnimatedImageFormat.webp.isAvailable else {
            await #expect(throws: AnimatedImageError.self) {
                _ = try await RecordingConversions.export(video, settings: settings, deletingSource: false)
            }
            #expect(!AnimatedImageFormat.unavailableMessage.isEmpty)
            return
        }
        let output = try await RecordingConversions.export(video, settings: settings, deletingSource: false)
        let image = try source(output)
        #expect(CGImageSourceGetCount(image) == 10)
        let container = try #require(CGImageSourceCopyProperties(image, nil) as? [CFString: Any])
        let webp = try #require(container[kCGImagePropertyWebPDictionary] as? [CFString: Any])
        #expect(webp[kCGImagePropertyWebPLoopCount] as? Int == 0)
    }

    @Test func describesTheAnimatedFormats() {
        #expect(AnimatedImageFormat.gif.isAvailable)
        #expect(AnimatedImageFormat.apng.isAvailable)
        #expect(AnimatedImageFormat.allCases.map(\.fileExtension) == ["gif", "png", "webp"])
        #expect(RecordingExportFormat.apng.animatedFormat == .apng)
        #expect(RecordingExportFormat(animated: .webp) == .webp)
        #expect(!RecordingExportFormat.apng.supportsAudio)
        #expect(RecordingExportFormat.apng.hasVideo)
        #expect(RecordingConversion.none.animatedFormat == nil)
        #expect(RecordingConversion.apng.animatedFormat == .apng)
        #expect(AnimatedImageFormat.apng.frameDelays(frameCount: 3, frameRate: 20) == [0.05, 0.05, 0.05])
    }
}

@Suite(.serialized)
struct SilenceCuttingTests {
    private static let size = CGSize(width: 160, height: 120)

    private func makeClip(in directory: URL) async throws -> URL {
        let video = try await SyntheticClip.video(in: directory, size: Self.size, seconds: 6) { index, time, context in
            let moving = time < 2 || time >= 5
            SyntheticClip.fill(context, gray: moving ? CGFloat(index % 10) / 10 : 0.5, size: Self.size)
        }
        let audio = try SyntheticClip.audio(in: directory, seconds: 6) { time in time < 2 || time >= 5 ? 0.3 : 0 }
        return try await SyntheticClip.combine(video: video, audio: audio, in: directory)
    }

    @Test func findsTheQuietStillStretch() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(in: directory)

        let analysis = try await SilenceCutter.analyze(clip)
        let audio = try #require(analysis.audio)
        #expect(try #require(audio.value(at: 1)) > -20)
        #expect(try #require(audio.value(at: 3.5)) < -60)
        let motion = try #require(analysis.motion)
        #expect(try #require(motion.value(at: 3.5)) < 0.002)
        #expect(try #require(motion.value(at: 1)) > 0.01)

        let plan = analysis.plan(settings: SilenceDetectionSettings(minimumDuration: 1.5, padding: 0.25, speed: .remove))
        let removed = plan.changedSegments
        #expect(removed.count == 1)
        #expect(abs((removed.first?.start ?? 0) - 2.25) < 0.3)
        #expect(abs((removed.first?.end ?? 0) - 4.75) < 0.3)
    }

    @Test func removesTheSilenceAndRetimesMarkers() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(in: directory)
        let plan = RetimingPlan(segments: [
            RetimingSegment(start: 0, end: 2.25, action: .keep),
            RetimingSegment(start: 2.25, end: 4.75, action: .remove),
            RetimingSegment(start: 4.75, end: 6, action: .keep),
        ])
        let output = try await RecordingEditor.renderInPlace(clip, edit: RecordingEdit(plan: plan), hevc: false, progress: nil)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 3.5) < 0.15)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let markers = RecordingChapters.retimed(
            [RecordingMarker(time: 1, title: "A"), RecordingMarker(time: 3, title: "B"), RecordingMarker(time: 5.5, title: "C")], through: plan)
        #expect(markers.map(\.title) == ["A", "C"])
        #expect(abs(markers[1].time - 3) < 0.001)
    }

    @Test func speedsUpTheSilenceWithoutItsAudio() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(in: directory)
        let plan = RetimingPlan(segments: [
            RetimingSegment(start: 0, end: 2, action: .keep),
            RetimingSegment(start: 2, end: 5, action: .speed(4)),
            RetimingSegment(start: 5, end: 6, action: .keep),
        ])
        let output = try await RecordingEditor.renderInPlace(clip, edit: RecordingEdit(plan: plan), hevc: false, progress: nil)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 3.75) < 0.15)
        let levels = try #require(try await MediaLevelAnalyzer.audioLevels(of: asset))
        #expect(try #require(levels.value(at: 1)) > -20)
        #expect(try #require(levels.value(at: 2.4)) < -50)
        #expect(try #require(levels.value(at: 3.4)) > -20)
    }

    @Test func trimsAndCutsInOnePass() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(in: directory)
        let plan = RetimingPlan(segments: [
            RetimingSegment(start: 0, end: 2, action: .keep),
            RetimingSegment(start: 2, end: 5, action: .remove),
            RetimingSegment(start: 5, end: 6, action: .keep),
        ]).restricted(to: 1 ... 5.5)
        let output = try await RecordingEditor.renderInPlace(clip, edit: RecordingEdit(plan: plan), hevc: false, progress: nil)
        #expect(abs(try await AVURLAsset(url: output).load(.duration).seconds - 1.5) < 0.15)
    }

    @Test func refusesToCutEverything() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clip = try await makeClip(in: directory)
        let plan = RetimingPlan(segments: [RetimingSegment(start: 0, end: 6, action: .remove)])
        await #expect(throws: RecordingEditError.self) {
            _ = try await RecordingEditor.renderInPlace(clip, edit: RecordingEdit(plan: plan), hevc: false, progress: nil)
        }
        #expect(FileManager.default.fileExists(atPath: clip.path))
    }
}

@Suite(.serialized)
struct VoiceOverMixingTests {
    private static let size = CGSize(width: 160, height: 120)

    private func makeClip(in directory: URL) async throws -> (video: URL, voice: VoiceOverClip) {
        let video = try await SyntheticClip.video(in: directory, size: Self.size, seconds: 3) { _, _, context in
            SyntheticClip.fill(context, gray: 0.5, size: Self.size)
        }
        let original = try SyntheticClip.audio(in: directory, seconds: 3) { _ in 0.3 }
        let clip = try await SyntheticClip.combine(video: video, audio: original, in: directory)
        let voiceURL = try SyntheticClip.audio(in: directory, seconds: 1, frequency: 1000) { _ in 0.3 }
        return (clip, VoiceOverClip(url: voiceURL, videoTime: 1, duration: 1))
    }

    private func levels(after mode: VoiceOverMode, reduction: Double = 20) async throws -> LevelSeries {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (video, voice) = try await makeClip(in: directory)
        let voiceLevels = await VoiceOverRecorder.levels(for: [voice])
        let mix = VoiceOverMix(clips: [voice], mode: mode, ducking: DuckingSettings(reduction: reduction), voiceLevels: voiceLevels)
        let output = try await RecordingEditor.renderInPlace(video, edit: RecordingEdit(plan: .identity(duration: 3), voiceOver: mix), hevc: false, progress: nil)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 3) < 0.15)
        return try #require(try await MediaLevelAnalyzer.audioLevels(of: asset))
    }

    @Test func voiceLevelsLineUpWithTheVideo() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let voice = VoiceOverClip(url: try SyntheticClip.audio(in: directory, seconds: 1) { _ in 0.3 }, videoTime: 1.5, duration: 1)
        let levels = try #require(await VoiceOverRecorder.levels(for: [voice]))
        #expect(levels.start == 1.5)
        #expect(try #require(levels.value(at: 2)) > -20)
    }

    @Test func replacesTheOriginalAudio() async throws {
        let levels = try await levels(after: .replace)
        #expect(try #require(levels.value(at: 0.5)) < -50)
        #expect(try #require(levels.value(at: 1.5)) > -16)
        #expect(try #require(levels.value(at: 2.6)) < -50)
    }

    @Test func ducksTheOriginalWhileSpeaking() async throws {
        let mixed = try await levels(after: .mix)
        let ducked = try await levels(after: .duck)
        let mixedBefore = try #require(mixed.value(at: 0.4))
        let duckedBefore = try #require(ducked.value(at: 0.4))
        #expect(abs(mixedBefore - duckedBefore) < 1.5)
        let mixedDuring = try #require(mixed.value(at: 1.5))
        let duckedDuring = try #require(ducked.value(at: 1.5))
        #expect(mixedDuring - duckedDuring > 1.5)
        #expect(duckedDuring > -16)
        let duckedAfter = try #require(ducked.value(at: 2.8))
        #expect(abs(duckedAfter - duckedBefore) < 1.5)
    }

    @Test func buildsGainPointsForEachMode() {
        let levels = LevelSeries(step: 0.5, values: [-80, -10, -80, -80])
        let ducking = DuckingSettings(reduction: 20)
        #expect(VoiceOverMix(clips: [], mode: .mix, ducking: ducking, voiceLevels: levels).originalGainPoints(duration: 2).isEmpty)
        #expect(VoiceOverMix(clips: [], mode: .replace, ducking: ducking, voiceLevels: levels).originalGainPoints(duration: 2) == [GainPoint(time: 0, gain: 0)])
        let points = VoiceOverMix(clips: [], mode: .duck, ducking: ducking, voiceLevels: levels).originalGainPoints(duration: 2)
        #expect(abs(DuckingEnvelope.gain(at: 0.75, points: points) - 0.1) < 0.001)
        #expect(VoiceOverRecorder.normalized(decibels: -60) == 0)
        #expect(VoiceOverRecorder.normalized(decibels: 0) == 1)
    }
}

@Suite(.serialized)
struct TrackedBlurTests {
    private static let size = CGSize(width: 320, height: 240)
    private static let square: CGFloat = 48

    private static func squareOrigin(at time: Double) -> CGPoint {
        CGPoint(x: 40 + CGFloat(time / 2) * 200, y: 96)
    }

    private func makeMovingSquare(in directory: URL) async throws -> URL {
        try await SyntheticClip.video(in: directory, size: Self.size, seconds: 2) { _, time, context in
            SyntheticClip.fill(context, gray: 0.5, size: Self.size)
            let origin = Self.squareOrigin(at: time)
            SyntheticClip.checker(context, in: CGRect(origin: origin, size: CGSize(width: Self.square, height: Self.square)), cell: 6)
        }
    }

    private func normalizedSquare(at time: Double) -> CGRect {
        let origin = Self.squareOrigin(at: time)
        return CGRect(
            x: (origin.x - 4) / Self.size.width, y: (origin.y - 4) / Self.size.height, width: (Self.square + 8) / Self.size.width,
            height: (Self.square + 8) / Self.size.height)
    }

    private func frame(_ url: URL, at time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private func contrast(in image: CGImage, at time: Double) throws -> Int {
        let origin = Self.squareOrigin(at: time)
        let x = Int(origin.x) + 15
        let y = Int(origin.y) + 15
        let first = try #require(PixelProbe.rgb(in: image, x: x, y: y))
        let second = try #require(PixelProbe.rgb(in: image, x: x + 6, y: y))
        return abs(first.red - second.red)
    }

    @Test(arguments: [BlurRegionStyle.blur, .pixelate])
    func blursAKeyframedRegionThatFollowsAMovingSquare(style: BlurRegionStyle) async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = try await makeMovingSquare(in: directory)
        let before = try await frame(video, at: 1)
        #expect(try contrast(in: before, at: 1) > 150)

        let region = BlurRegion(
            style: style, start: 0, end: 2,
            track: RegionTrack(keyframes: [RegionKeyframe(time: 0, rect: normalizedSquare(at: 0)), RegionKeyframe(time: 2, rect: normalizedSquare(at: 2))]))
        try await OverlayCompositor.applyEdits(camera: nil, blurRegions: [region], to: video, hevc: false, progress: nil)

        let after = try await frame(video, at: 1)
        #expect(try contrast(in: after, at: 1) < 70)
        let backgroundBefore = try #require(PixelProbe.rgb(in: before, x: 10, y: 10))
        let backgroundAfter = try #require(PixelProbe.rgb(in: after, x: 10, y: 10))
        #expect(abs(backgroundAfter.red - backgroundBefore.red) < 12)
        #expect(abs(try await AVURLAsset(url: video).load(.duration).seconds - 2) < 0.15)
    }

    @Test func rendersRegionsOnlyInsideTheirTimeRange() {
        let image = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: Self.size))
        let region = BlurRegion(start: 1, end: 2, track: RegionTrack(keyframes: [RegionKeyframe(time: 1, rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))]))
        let untouched = BlurRegionRenderer.apply([region], to: image, time: 0.5, videoSize: Self.size)
        #expect(untouched === image)
        #expect(BlurRegionRenderer.pixelRect(for: CGRect(x: 0, y: 0, width: 0.5, height: 0.25), videoSize: Self.size) == CGRect(x: 0, y: 180, width: 160, height: 60))
    }

    @Test func tracksTheSquareForwardAndBackward() async throws {
        let directory = try SyntheticClip.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = try await makeMovingSquare(in: directory)
        let keyframes = try await RegionTracker.track(video, rect: normalizedSquare(at: 1), at: 1, within: 0 ... 2)
        let track = RegionTrack(keyframes: keyframes)
        #expect((keyframes.first?.time ?? 1) < 0.3)
        #expect((keyframes.last?.time ?? 1) > 1.7)
        for time in [0.25, 1.5, 1.8] {
            let rect = try #require(track.rect(at: time))
            let expected = normalizedSquare(at: time)
            #expect(abs(rect.midX - expected.midX) < 0.06, "\(time)")
            #expect(abs(rect.midY - expected.midY) < 0.06, "\(time)")
        }
    }
}

struct RecordingPostProcessingSettingsTests {
    @MainActor @Test func findsTheNewSettingsBySearch() {
        for query in ["cut silence", "voice-over", "apng", "pixelate", "upload recordings as"] {
            #expect(SettingsSearchIndex.matches(for: query, localize: { $0 }).contains { $0.pane == .recording }, "\(query)")
        }
    }

    @MainActor @Test func exportsTheNewPreferences() {
        for name in [
            "cutSilenceEnabled", "cutSilenceSpeed", "cutSilenceAudioThreshold", "cutSilenceMotionThreshold", "cutSilenceMinimumDuration", "cutSilencePadding",
            "recordingConvertTo", "recordingUploadFormat", "voiceOverMode", "voiceOverDuckAmount", "blurRegionStyle", "blurDetectionInterval",
        ] {
            #expect(SettingsTransfer.preferenceNames.contains(name), "\(name)")
        }
    }
}
