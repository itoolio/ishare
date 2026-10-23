import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

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

struct SelectionMeasurementTests {
    @Test func measuresLengthInPointsAndPixels() {
        let measurement = SelectionMeasurement(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 40, y: 50))
        #expect(measurement.length == 50)
        #expect(measurement.pixelLength(scale: 2) == 100)
        #expect(measurement.delta == CGVector(dx: 30, dy: 40))
        #expect(measurement.label(scale: 2) == "50 pt · 100 px   Δx 30  Δy 40")
    }

    @Test func locksToTheDominantAxis() {
        let horizontal = SelectionMeasurement(start: .zero, end: CGPoint(x: 80, y: 12)).lockedToAxis()
        #expect(horizontal.end == CGPoint(x: 80, y: 0))
        let vertical = SelectionMeasurement(start: .zero, end: CGPoint(x: -5, y: -60)).lockedToAxis()
        #expect(vertical.end == CGPoint(x: 0, y: -60))
    }

    @Test func formatsFractionalValuesWithOneDecimal() {
        #expect(SelectionMeasurement.format(12) == "12")
        #expect(SelectionMeasurement.format(12.34) == "12.3")
        #expect(SelectionMeasurement.format(1.999) == "2")
    }

    @Test func convertsViewLocationsToTopLeftDisplayCoordinates() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(DisplayCoordinates.topLeftPoint(for: CGPoint(x: 100.7, y: 800.2), in: bounds) == CGPoint(x: 100, y: 99))
        #expect(DisplayCoordinates.pixel(for: CGPoint(x: 100, y: 800), in: bounds, scale: 2) == CGPoint(x: 200, y: 200))
        #expect(DisplayCoordinates.label(for: CGPoint(x: 0, y: 900), in: bounds) == "0, 0")
    }
}

struct MagnifierLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func sitsBelowAndRightOfTheCursorByDefault() {
        let frame = MagnifierLayout.cardFrame(for: CGPoint(x: 400, y: 500), in: bounds)
        #expect(frame.minX == 400 + MagnifierLayout.cursorOffset)
        #expect(frame.maxY == 500 - MagnifierLayout.cursorOffset)
        #expect(frame.size == MagnifierLayout.cardSize)
    }

    @Test func flipsAwayFromTheRightAndBottomEdges() {
        let frame = MagnifierLayout.cardFrame(for: CGPoint(x: 1430, y: 20), in: bounds)
        #expect(frame.maxX == 1430 - MagnifierLayout.cursorOffset)
        #expect(frame.minY == 20 + MagnifierLayout.cursorOffset)
    }

    @Test(arguments: [CGPoint(x: 0, y: 0), CGPoint(x: 1440, y: 900), CGPoint(x: 0, y: 900), CGPoint(x: 1440, y: 0), CGPoint(x: 720, y: 450), CGPoint(x: 5, y: 120)])
    func alwaysStaysOnScreen(location: CGPoint) {
        let frame = MagnifierLayout.cardFrame(for: location, in: bounds)
        #expect(bounds.contains(frame))
    }

    @Test func staysOnScreenOnTinyDisplays() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 240)
        let frame = MagnifierLayout.cardFrame(for: CGPoint(x: 150, y: 120), in: small)
        #expect(small.contains(frame))
    }
}

struct DeviceFrameTests {
    @Test func letterboxScreenContainsTheWholeImage() {
        let size = DeviceFrameLayout.screenSize(for: CGSize(width: 1000, height: 1000), aspect: 16.0 / 9.0, fit: .letterbox)
        #expect(size == CGSize(width: 1778, height: 1000))
        let tall = DeviceFrameLayout.screenSize(for: CGSize(width: 1600, height: 400), aspect: 2, fit: .letterbox)
        #expect(tall == CGSize(width: 1600, height: 800))
    }

    @Test func cropScreenFitsInsideTheImage() {
        let size = DeviceFrameLayout.screenSize(for: CGSize(width: 1000, height: 1000), aspect: 16.0 / 9.0, fit: .crop)
        #expect(size == CGSize(width: 1000, height: 563))
        #expect(DeviceFrameLayout.screenSize(for: CGSize(width: 300, height: 200), aspect: nil, fit: .crop) == CGSize(width: 300, height: 200))
    }

    @Test func placementPreservesAspectRatio() {
        let screen = CGRect(x: 10, y: 20, width: 200, height: 100)
        let fit = DeviceFrameLayout.placement(of: CGSize(width: 100, height: 100), in: screen, fit: .letterbox)
        #expect(fit == CGRect(x: 60, y: 20, width: 100, height: 100))
        let fill = DeviceFrameLayout.placement(of: CGSize(width: 100, height: 100), in: screen, fit: .crop)
        #expect(fill == CGRect(x: 10, y: -30, width: 200, height: 200))
    }

    @Test(arguments: [DeviceFrame.laptop, .display, .phone, .browser])
    func layoutKeepsTheScreenInsideTheCanvas(kind: DeviceFrame) throws {
        let imageSize = CGSize(width: 1200, height: 800)
        let layout = try #require(DeviceFrameLayout.make(for: imageSize, style: DeviceFrameStyle(kind: kind)))
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        #expect(canvas.contains(layout.bodyRect))
        #expect(layout.bodyRect.contains(layout.screenRect))
        #expect(layout.screenRect.contains(layout.imageRect.insetBy(dx: 0.5, dy: 0.5)))
        if let aspect = kind.screenAspect(for: imageSize) {
            #expect(abs(layout.screenRect.width / layout.screenRect.height - aspect) < 0.01)
        } else {
            #expect(layout.screenRect.size == imageSize)
        }
    }

    @Test func phoneTurnsLandscapeForWideCaptures() throws {
        let landscape = try #require(DeviceFrameLayout.make(for: CGSize(width: 1950, height: 900), style: DeviceFrameStyle(kind: .phone)))
        #expect(landscape.screenRect.width > landscape.screenRect.height)
        let portrait = try #require(DeviceFrameLayout.make(for: CGSize(width: 900, height: 1950), style: DeviceFrameStyle(kind: .phone)))
        #expect(portrait.screenRect.height > portrait.screenRect.width)
        #expect(portrait.islandRect.map(portrait.screenRect.contains) == true)
        #expect(portrait.buttons.count == 4)
        #expect(portrait.buttons.allSatisfy { !$0.intersects(portrait.bodyRect) })
    }

    @Test func browserReservesAToolbarAboveTheCapture() throws {
        let layout = try #require(DeviceFrameLayout.make(for: CGSize(width: 1000, height: 600), style: DeviceFrameStyle(kind: .browser)))
        let toolbar = try #require(layout.toolbarRect)
        #expect(toolbar.height == 45)
        #expect(layout.screenRect.minY == toolbar.maxY)
        #expect(layout.canvasSize == CGSize(width: 1000, height: 645))
        #expect(layout.trafficLights.count == 3)
        #expect(layout.addressRect.map(toolbar.contains) == true)
    }
}
