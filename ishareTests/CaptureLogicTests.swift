import CoreGraphics
import Foundation
import Testing
@testable import ishare

struct RecordingOptionsTests {
    @Test(arguments: [
        (RecordingResolution.native, CGSize(width: 3024, height: 1964), CGSize(width: 3024, height: 1964)),
        (RecordingResolution.p1080, CGSize(width: 3024, height: 1964), CGSize(width: 1662, height: 1080)),
        (RecordingResolution.p720, CGSize(width: 1000, height: 3000), CGSize(width: 720, height: 2160)),
        (RecordingResolution.p2160, CGSize(width: 1920, height: 1080), CGSize(width: 1920, height: 1080)),
        (RecordingResolution.half, CGSize(width: 1001, height: 601), CGSize(width: 500, height: 300)),
    ])
    func scalesRecordingsWithoutUpscaling(resolution: RecordingResolution, input: CGSize, expected: CGSize) {
        #expect(resolution.outputSize(for: input) == expected)
    }

    @Test func buildsGIFFrameTimes() {
        let times = GIFTiming.frameTimes(duration: 1.0, frameRate: 10)
        #expect(times.count == 10)
        #expect(times.last?.seconds == 0.9)
        #expect(GIFTiming.frameTimes(duration: 0, frameRate: 10).isEmpty)
        #expect(GIFTiming.delay(frameRate: 20) == 0.05)
    }

    @Test func decidesWhenToCompress() {
        #expect(VideoCompressor.needsCompression(fileSize: 26 * 1024 * 1024, thresholdMB: 25))
        #expect(!VideoCompressor.needsCompression(fileSize: 25 * 1024 * 1024, thresholdMB: 25))
    }

    @Test func mapsFrameRatesToIntervals() {
        #expect(RecordingFrameRate.fps30.minimumFrameInterval.seconds == 1.0 / 30.0)
    }
}

struct CaptureFileNameTests {
    @Test func buildsLowercasedSanitizedNames() {
        let name = CaptureFileName.make(prefix: "ishare", suffix: "Google Chrome: Beta/Dev", ext: "PNG", date: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(name == "ishare-1700000000-google chrome- beta-dev.png")
    }

    @Test func fallsBackToDefaultPrefix() {
        #expect(CaptureFileName.make(prefix: "", suffix: nil, ext: "mp4", date: Date(timeIntervalSince1970: 5)) == "ishare-5.mp4")
    }
}

struct MigrationTests {
    @Test func removesTheCaptureBinarySetting() throws {
        let suite = "dev.adrian.ishare.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/usr/sbin/screencapture", forKey: "captureBinary")
        Migrations.run(defaults: defaults)
        #expect(defaults.object(forKey: "captureBinary") == nil)
        #expect(defaults.integer(forKey: Migrations.versionKey) == Migrations.currentVersion)
        defaults.removePersistentDomain(forName: suite)
    }
}
