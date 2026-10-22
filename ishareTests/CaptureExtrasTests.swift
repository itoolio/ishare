import CoreGraphics
import Foundation
import Testing
@testable import ishare

enum TestImages {
    static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        return context.makeImage()!
    }

    static func solid(width: Int, height: Int, color: CaptureColor) -> CGImage {
        make(width: width, height: height) { context in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func checkerboard(width: Int, height: Int) -> CGImage {
        make(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            for y in 0 ..< height {
                for x in 0 ..< width where (x + y).isMultiple(of: 2) {
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    static func color(_ image: CGImage, _ x: Int, _ y: Int) -> CaptureColor {
        ImageProcessing.pixelColor(of: image, at: CGPoint(x: x, y: y))!
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

struct PixelColorTests {
    @Test func readsTheColorUnderAPixel() {
        let image = TestImages.make(width: 4, height: 4) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 2, width: 4, height: 2))
        }
        #expect(TestImages.color(image, 0, 0).hex == "#0000FF")
        #expect(TestImages.color(image, 3, 3).hex == "#FF0000")
        #expect(ImageProcessing.pixelColor(of: image, at: CGPoint(x: 4, y: 0)) == nil)
        #expect(ImageProcessing.pixelColor(of: image, at: CGPoint(x: -1, y: 0)) == nil)
    }

    @Test func parsesAndFormatsHexColors() {
        let color = CaptureColor(hex: "#1e90ff")
        #expect(color?.hex == "#1E90FF")
        #expect(CaptureColor(hex: "1E90FF80")?.alpha == CGFloat(0x80) / 255)
        #expect(CaptureColor(hex: "#12345") == nil)
        #expect(CaptureColor(hex: "zzzzzz") == nil)
    }
}

struct BeautifierTests {
    let sampleColor = CaptureColor(red: 1, green: 1, blue: 1)

    @Test(arguments: [0, 16, 48])
    func growsTheImageByTwiceThePadding(padding: Int) throws {
        let image = TestImages.solid(width: 120, height: 80, color: sampleColor)
        let style = BeautifyStyle(padding: CGFloat(padding), cornerRadius: 8, shadowRadius: 10, fill: .gradient(BeautifyBackground.ocean.gradientColors!))
        let output = try #require(Beautifier.apply(to: image, style: style))
        #expect(output.width == 120 + padding * 2)
        #expect(output.height == 80 + padding * 2)
    }

    @Test func fillsTheBackgroundAndKeepsTheContent() throws {
        let background = try #require(CaptureColor(hex: "#336699"))
        let image = TestImages.solid(width: 60, height: 40, color: sampleColor)
        let style = BeautifyStyle(padding: 20, cornerRadius: 0, shadowRadius: 0, fill: .solid(background))
        let output = try #require(Beautifier.apply(to: image, style: style))
        #expect(TestImages.color(output, 0, 0).hex == "#336699")
        #expect(TestImages.color(output, 99, 79).hex == "#336699")
        #expect(TestImages.color(output, 50, 40).hex == "#FFFFFF")
        #expect(TestImages.color(output, 20, 20).hex == "#FFFFFF")
    }

    @Test func roundsTheContentCornersOnATransparentBackground() throws {
        let image = TestImages.solid(width: 80, height: 80, color: sampleColor)
        let style = BeautifyStyle(padding: 10, cornerRadius: 20, shadowRadius: 0, fill: .transparent)
        let output = try #require(Beautifier.apply(to: image, style: style))
        #expect(TestImages.color(output, 0, 0).alpha == 0)
        #expect(TestImages.color(output, 10, 10).alpha == 0)
        #expect(TestImages.color(output, 30, 30).alpha == 1)
        #expect(TestImages.color(output, 50, 10).alpha == 1)
    }

    @Test func castsAShadowOntoThePadding() throws {
        let image = TestImages.solid(width: 80, height: 80, color: sampleColor)
        let style = BeautifyStyle(padding: 30, cornerRadius: 0, shadowRadius: 12, fill: .transparent)
        let output = try #require(Beautifier.apply(to: image, style: style))
        #expect(TestImages.color(output, 70, 115).alpha > 0)
        #expect(TestImages.color(output, 0, 0).alpha == 0)
    }

    @Test func startsTheGradientInTheTopLeftCorner() throws {
        let colors = try #require(BeautifyBackground.sunset.gradientColors)
        let image = TestImages.solid(width: 40, height: 40, color: sampleColor)
        let output = try #require(Beautifier.apply(to: image, style: BeautifyStyle(padding: 40, cornerRadius: 0, shadowRadius: 0, fill: .gradient(colors))))
        let topLeft = TestImages.color(output, 0, 0)
        let bottomRight = TestImages.color(output, output.width - 1, output.height - 1)
        #expect(abs(topLeft.red - colors[0].red) < 0.03)
        #expect(abs(topLeft.blue - colors[0].blue) < 0.03)
        #expect(abs(bottomRight.blue - colors[1].blue) < 0.03)
    }

    @Test func clampsTheCornerRadiusToHalfTheShortestSide() {
        let style = BeautifyStyle(padding: 0, cornerRadius: 500, shadowRadius: 0, fill: .transparent)
        #expect(Beautifier.effectiveCornerRadius(for: CGSize(width: 100, height: 60), style: style) == 30)
    }

    @Test func scalesSettingsToPixels() {
        let style = BeautifyStyle(background: .solid, solidColor: sampleColor, padding: 24, cornerRadius: 10, shadow: false, scale: 2)
        #expect(style.padding == 48)
        #expect(style.cornerRadius == 20)
        #expect(style.shadowRadius == 0)
        #expect(style.fill == .solid(sampleColor))
        #expect(BeautifyStyle(background: .transparent, solidColor: sampleColor, padding: 24, cornerRadius: 10, shadow: true, scale: 2).shadowRadius > 0)
        #expect(BeautifyStyle(background: .forest, solidColor: sampleColor, padding: 0, cornerRadius: 0, shadow: false, scale: 1).fill == .gradient(BeautifyBackground.forest.gradientColors!))
    }

    @Test func everyGradientHasTwoStops() {
        for background in BeautifyBackground.allCases where background != .solid && background != .transparent {
            #expect(background.gradientColors?.count == 2)
        }
    }
}

struct PrivacyRedactionTests {
    @Test func mapsGlobalWindowFramesIntoImagePixels() {
        let rect = PrivacyRedaction.imageRect(
            forGlobal: CGRect(x: 1540, y: 120, width: 300, height: 200),
            captureOrigin: CGPoint(x: 1440 + 50, y: 100),
            scale: 2
        )
        #expect(rect == CGRect(x: 100, y: 40, width: 600, height: 400))
    }

    @Test func combinesDisplayOriginAndRegion() {
        let geometry = CaptureGeometry(displayID: 1, region: CGRect(x: 30, y: 40, width: 100, height: 100), scale: 2, displayOrigin: CGPoint(x: -1920, y: 0))
        #expect(geometry.captureOrigin == CGPoint(x: -1890, y: 40))
    }

    @Test func masksSensitiveWindowsFromTheTopLeft() throws {
        let windows = [PrivacyWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 30), isSensitive: true)]
        let mask = try #require(PrivacyRedaction.sensitiveMask(windows: windows, captureOrigin: .zero, scale: 1, pixelSize: CGSize(width: 100, height: 100)))
        #expect(TestImages.color(mask, 50, 10).red == 1)
        #expect(TestImages.color(mask, 50, 80).red == 0)
    }

    @Test func respectsWindowsInFrontOfSensitiveOnes() throws {
        let size = CGSize(width: 100, height: 100)
        let covered = [
            PrivacyWindow(frame: CGRect(x: 0, y: 0, width: 50, height: 100), isSensitive: false),
            PrivacyWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100), isSensitive: true),
        ]
        let mask = try #require(PrivacyRedaction.sensitiveMask(windows: covered, captureOrigin: .zero, scale: 1, pixelSize: size))
        #expect(TestImages.color(mask, 25, 50).red == 0)
        #expect(TestImages.color(mask, 75, 50).red == 1)

        let inFront = Array(covered.reversed())
        let frontMask = try #require(PrivacyRedaction.sensitiveMask(windows: inFront, captureOrigin: .zero, scale: 1, pixelSize: size))
        #expect(TestImages.color(frontMask, 25, 50).red == 1)
        #expect(TestImages.color(frontMask, 75, 50).red == 1)
    }

    @Test func skipsTheMaskWhenNoSensitiveWindowIsInFrame() {
        let windows = [
            PrivacyWindow(frame: CGRect(x: 500, y: 500, width: 100, height: 100), isSensitive: true),
            PrivacyWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100), isSensitive: false),
        ]
        #expect(PrivacyRedaction.sensitiveMask(windows: windows, captureOrigin: .zero, scale: 1, pixelSize: CGSize(width: 100, height: 100)) == nil)
    }

    @Test func blursOnlyTheSensitiveArea() throws {
        let image = TestImages.checkerboard(width: 100, height: 100)
        let windows = [PrivacyWindow(frame: CGRect(x: 5, y: 5, width: 20, height: 20), isSensitive: true)]
        let output = PrivacyRedaction.redact(image, windows: windows, captureOrigin: .zero, scale: 2, blurRadius: 6)
        #expect(output.width == 100 && output.height == 100)
        let inside = TestImages.color(output, 30, 30)
        #expect(inside.red > 0.25 && inside.red < 0.75)
        for (x, y) in [(80, 80), (60, 61), (51, 20), (5, 95)] {
            let original = TestImages.color(image, x, y)
            #expect(TestImages.color(output, x, y) == original)
        }
    }

    @Test func leavesImagesWithoutSensitiveWindowsUntouched() {
        let image = TestImages.checkerboard(width: 20, height: 20)
        let output = PrivacyRedaction.redact(image, windows: [], captureOrigin: .zero, scale: 1, blurRadius: 4)
        #expect(output === image)
    }

    @Test func cropsTheMenuBarFromTheTopOfACapture() {
        let size = CGSize(width: 2880, height: 1800)
        #expect(PrivacyRedaction.menuBarCrop(region: CGRect(x: 0, y: 0, width: 1440, height: 900), menuBarHeight: 33, scale: 2, pixelSize: size) == CGRect(x: 0, y: 66, width: 2880, height: 1734))
        #expect(PrivacyRedaction.menuBarCrop(region: CGRect(x: 100, y: 20, width: 200, height: 100), menuBarHeight: 33, scale: 2, pixelSize: CGSize(width: 400, height: 200)) == CGRect(x: 0, y: 26, width: 400, height: 174))
    }

    @Test func keepsCapturesThatDoNotTouchOrOnlyContainTheMenuBar() {
        let size = CGSize(width: 200, height: 100)
        #expect(PrivacyRedaction.menuBarCrop(region: CGRect(x: 0, y: 40, width: 100, height: 50), menuBarHeight: 33, scale: 2, pixelSize: size) == nil)
        #expect(PrivacyRedaction.menuBarCrop(region: CGRect(x: 0, y: 0, width: 100, height: 30), menuBarHeight: 33, scale: 2, pixelSize: size) == nil)
        #expect(PrivacyRedaction.menuBarCrop(region: CGRect(x: 0, y: 0, width: 100, height: 50), menuBarHeight: 0, scale: 2, pixelSize: size) == nil)
    }

    @Test func hidesTheMenuBarRows() {
        let image = TestImages.make(width: 100, height: 100) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 80, width: 100, height: 20))
        }
        let output = PrivacyRedaction.hideMenuBar(image, region: CGRect(x: 0, y: 0, width: 50, height: 50), menuBarHeight: 10, scale: 2)
        #expect(output.height == 80)
        #expect(TestImages.color(output, 50, 0).hex == "#00FF00")
    }
}

struct LastRegionTests {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func remembersTheLastRegionPerDisplay() {
        var regions = LastRegions()
        regions.remember(CGRect(x: 10.4, y: 20.6, width: 300, height: 200), forDisplay: "A")
        regions.remember(CGRect(x: 0, y: 0, width: 50, height: 50), forDisplay: "B")
        regions.remember(CGRect(x: 100, y: 100, width: 400, height: 300), forDisplay: "A")
        #expect(regions.region(forDisplay: "A", within: bounds) == CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(regions.region(forDisplay: "B", within: bounds) == CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(regions.region(forDisplay: "C", within: bounds) == nil)
    }

    @Test func ignoresTinySelections() {
        var regions = LastRegions()
        regions.remember(CGRect(x: 0, y: 0, width: 2, height: 200), forDisplay: "A")
        #expect(regions.regions.isEmpty)
    }

    @Test func clampsToTheCurrentDisplaySize() {
        var regions = LastRegions()
        regions.remember(CGRect(x: 1200, y: 700, width: 600, height: 400), forDisplay: "A")
        #expect(regions.region(forDisplay: "A", within: bounds) == CGRect(x: 1200, y: 700, width: 240, height: 200))
        #expect(regions.region(forDisplay: "A", within: CGRect(x: 0, y: 0, width: 1000, height: 600)) == nil)
    }

    @Test func picksTheMostRecentlyUsedDisplay() {
        var regions = LastRegions()
        let now = Date()
        regions.remember(CGRect(x: 0, y: 0, width: 100, height: 100), forDisplay: "A", at: now)
        regions.remember(CGRect(x: 0, y: 0, width: 100, height: 100), forDisplay: "B", at: now.addingTimeInterval(10))
        #expect(regions.mostRecentDisplay(among: ["A", "B"]) == "B")
        #expect(regions.mostRecentDisplay(among: ["A", "C"]) == "A")
        #expect(regions.mostRecentDisplay(among: ["C"]) == nil)
    }

    @Test func survivesEncoding() throws {
        var regions = LastRegions()
        regions.remember(CGRect(x: 12, y: 34, width: 56, height: 78), forDisplay: "A", at: Date(timeIntervalSince1970: 1000))
        let decoded = try JSONDecoder().decode(LastRegions.self, from: JSONEncoder().encode(regions))
        #expect(decoded == regions)
    }

    @Test func isReachableAsACaptureType() {
        #expect(CaptureType(rawValue: "last_region".uppercased()) == .LAST_REGION)
    }
}
