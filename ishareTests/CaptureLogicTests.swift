import CoreGraphics
import Foundation
import Testing
@testable import ishare

struct ScreenGeometryTests {
    @Test func normalizesDragRectsInAnyDirection() {
        #expect(ScreenGeometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test func constrainsToSquares() {
        #expect(ScreenGeometry.squareRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 40, y: 130)) == CGRect(x: 40, y: 100, width: 60, height: 60))
    }

    @Test func flipsBetweenCocoaAndQuartz() {
        let cocoa = CGRect(x: 10, y: 700, width: 100, height: 200)
        let quartz = ScreenGeometry.cocoaToQuartz(cocoa, primaryScreenHeight: 1000)
        #expect(quartz == CGRect(x: 10, y: 100, width: 100, height: 200))
        #expect(ScreenGeometry.quartzToCocoa(quartz, primaryScreenHeight: 1000) == cocoa)
        #expect(ScreenGeometry.cocoaPointToQuartz(CGPoint(x: 5, y: 900), primaryScreenHeight: 1000) == CGPoint(x: 5, y: 100))
    }

    @Test func movesSelectionsWithinBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let moved = ScreenGeometry.moved(CGRect(x: 80, y: 10, width: 20, height: 20), by: CGVector(dx: 30, dy: -30), within: bounds)
        #expect(moved == CGRect(x: 80, y: 0, width: 20, height: 20))
    }

    @Test func convertsPointsToPixels() {
        #expect(ScreenGeometry.pixelRect(for: CGRect(x: 10.4, y: 5.6, width: 100.2, height: 50.3), scale: 2) == CGRect(x: 20, y: 11, width: 200, height: 101))
    }

    @Test func roundsToEvenPixelSizes() {
        #expect(ScreenGeometry.evenPixelSize(CGSize(width: 1919, height: 1081)) == CGSize(width: 1920, height: 1082))
        #expect(ScreenGeometry.evenPixelSize(CGSize(width: 0.4, height: 1)) == CGSize(width: 2, height: 2))
    }

    @Test func picksTheFrontmostWindowContainingThePoint() {
        let frames = [CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 0, y: 0, width: 200, height: 200)]
        #expect(ScreenGeometry.topmostWindowIndex(at: CGPoint(x: 10, y: 10), frames: frames) == 0)
        #expect(ScreenGeometry.topmostWindowIndex(at: CGPoint(x: 100, y: 100), frames: frames) == 1)
        #expect(ScreenGeometry.topmostWindowIndex(at: CGPoint(x: 300, y: 300), frames: frames) == nil)
    }
}

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

struct ScrollStitcherTests {
    func makePage(height: Int, width: Int = 120, seed: UInt64 = 7) -> GrayFrame {
        var generator = seed
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0 ..< height {
            generator = generator &* 6364136223846793005 &+ 1442695040888963407
            let rowValue = UInt8(truncatingIfNeeded: generator >> 33)
            for column in 0 ..< width {
                pixels[row * width + column] = rowValue &+ UInt8(truncatingIfNeeded: column * 3)
            }
        }
        return GrayFrame(width: width, height: height, pixels: pixels)
    }

    func viewport(of page: GrayFrame, top: Int, height: Int) -> GrayFrame {
        let start = top * page.width
        return GrayFrame(width: page.width, height: height, pixels: Array(page.pixels[start ..< start + height * page.width]))
    }

    @Test(arguments: [37, 120, 211])
    func findsTheScrollOffset(offset: Int) {
        let page = makePage(height: 900)
        let first = viewport(of: page, top: 0, height: 300)
        let second = viewport(of: page, top: offset, height: 300)
        #expect(ScrollStitcher.verticalOffset(previous: first, next: second)?.offset == offset)
    }

    @Test func reportsNoMovementForIdenticalFrames() {
        let page = makePage(height: 400)
        let frame = viewport(of: page, top: 10, height: 300)
        #expect(ScrollStitcher.verticalOffset(previous: frame, next: frame)?.offset == 0)
    }

    @Test func rejectsUnrelatedFrames() {
        let first = viewport(of: makePage(height: 400, seed: 1), top: 0, height: 300)
        let second = viewport(of: makePage(height: 400, seed: 99), top: 0, height: 300)
        #expect(ScrollStitcher.verticalOffset(previous: first, next: second) == nil)
    }

    @Test func toleratesStickyHeaders() {
        let page = makePage(height: 900)
        var first = viewport(of: page, top: 0, height: 300)
        var second = viewport(of: page, top: 90, height: 300)
        let header = [UInt8](repeating: 200, count: 30 * page.width)
        first = GrayFrame(width: first.width, height: first.height, pixels: header + first.pixels.dropFirst(header.count))
        second = GrayFrame(width: second.width, height: second.height, pixels: header + second.pixels.dropFirst(header.count))
        #expect(ScrollStitcher.verticalOffset(previous: first, next: second)?.offset == 90)
    }

    @Test func stitchesFramesIntoOneImage() throws {
        func solid(_ gray: CGFloat, height: Int) -> CGImage {
            let context = CGContext(data: nil, width: 10, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 10, height: height))
            return context.makeImage()!
        }
        let stitched = try #require(ScrollStitcher.stitch(frames: [solid(0, height: 100), solid(1, height: 100), solid(0.5, height: 100)], offsets: [40, 25]))
        #expect(stitched.width == 10)
        #expect(stitched.height == 165)
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
