import CoreGraphics
import Foundation
import Testing
@testable import ishare

private let red = CaptureColor(red: 1, green: 0, blue: 0)
private let blue = CaptureColor(red: 0, green: 0, blue: 1)
private let white = CaptureColor(red: 1, green: 1, blue: 1)

private func marked(width: Int, height: Int, marker: CGRect, background: CaptureColor = white, color: CaptureColor = red) -> CGImage {
    TestImages.make(width: width, height: height) { context in
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: marker.minX, y: CGFloat(height) - marker.maxY, width: marker.width, height: marker.height))
    }
}

private func isClose(_ first: CaptureColor, _ second: CaptureColor, tolerance: CGFloat = 0.08) -> Bool {
    abs(first.red - second.red) <= tolerance && abs(first.green - second.green) <= tolerance
        && abs(first.blue - second.blue) <= tolerance && abs(first.alpha - second.alpha) <= tolerance
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

    @Test func noFrameHasNoLayout() {
        #expect(DeviceFrameLayout.make(for: CGSize(width: 10, height: 10), style: DeviceFrameStyle(kind: .none)) == nil)
        #expect(BeautifyStyle(padding: 0, cornerRadius: 0, shadowRadius: 0, fill: .transparent, frame: DeviceFrameStyle(kind: .none)).frame == nil)
    }

    @Test func framedImageShowsTheCaptureOnScreenAndLetterboxesInBlack() throws {
        let image = TestImages.solid(width: 400, height: 400, color: red)
        let style = DeviceFrameStyle(kind: .display, appearance: .dark, fit: .letterbox)
        let layout = try #require(DeviceFrameLayout.make(for: CGSize(width: 400, height: 400), style: style))
        let framed = try #require(DeviceFramer.apply(to: image, style: style))
        #expect(CGSize(width: framed.width, height: framed.height) == layout.canvasSize)
        #expect(isClose(TestImages.color(framed, Int(layout.screenRect.midX), Int(layout.screenRect.midY)), red))
        let bar = TestImages.color(framed, Int(layout.screenRect.minX) + 4, Int(layout.screenRect.midY))
        #expect(isClose(bar, CaptureColor(red: 0, green: 0, blue: 0)))
        #expect(TestImages.color(framed, 0, framed.height - 1).alpha == 0)
    }

    @Test func croppedFrameFillsTheScreen() throws {
        let image = TestImages.solid(width: 400, height: 400, color: blue)
        let style = DeviceFrameStyle(kind: .laptop, fit: .crop)
        let layout = try #require(DeviceFrameLayout.make(for: CGSize(width: 400, height: 400), style: style))
        let framed = try #require(DeviceFramer.apply(to: image, style: style))
        #expect(isClose(TestImages.color(framed, Int(layout.screenRect.minX) + 3, Int(layout.screenRect.midY)), blue))
        #expect(layout.screenRect.width == 400)
    }

    @Test func browserFrameDrawsTitleWithoutTouchingTheCapture() throws {
        let image = TestImages.solid(width: 600, height: 300, color: blue)
        let titled = try #require(DeviceFramer.apply(to: image, style: DeviceFrameStyle(kind: .browser, appearance: .light, title: "example.com")))
        let plain = try #require(DeviceFramer.apply(to: image, style: DeviceFrameStyle(kind: .browser, appearance: .light)))
        #expect(titled.width == 600)
        #expect(titled.height == plain.height)
        #expect(isClose(TestImages.color(titled, 300, titled.height - 150), blue))
        let line = DeviceFramer.truncatedLine(String(repeating: "long title ", count: 40), fontSize: 12, color: CGColor(gray: 0, alpha: 1), width: 120)
        #expect(CTLineGetTypographicBounds(line, nil, nil, nil) <= 121)
    }

    @Test func beautifierPadsAroundTheFrame() throws {
        let image = TestImages.solid(width: 300, height: 200, color: red)
        let frame = DeviceFrameStyle(kind: .browser)
        let layout = try #require(DeviceFrameLayout.make(for: CGSize(width: 300, height: 200), style: frame))
        let style = BeautifyStyle(padding: 20, cornerRadius: 30, shadowRadius: 0, fill: .solid(white), frame: frame)
        let output = try #require(Beautifier.apply(to: image, style: style))
        #expect(output.width == Int(layout.canvasSize.width) + 40)
        #expect(output.height == Int(layout.canvasSize.height) + 40)
        #expect(isClose(TestImages.color(output, 5, 5), white))
    }
}

struct ImageCombinerTests {
    let sizes = [CGSize(width: 100, height: 50), CGSize(width: 60, height: 80), CGSize(width: 40, height: 40)]

    @Test func horizontalLayoutPlacesImagesSideBySide() {
        let layout = ImageCombiner.layout(for: sizes, style: CombineStyle(layout: .horizontal, alignment: .center, spacing: 10, padding: 5))
        #expect(layout.canvasSize == CGSize(width: 5 + 100 + 10 + 60 + 10 + 40 + 5, height: 90))
        #expect(layout.frames[0] == CGRect(x: 5, y: 20, width: 100, height: 50))
        #expect(layout.frames[1] == CGRect(x: 115, y: 5, width: 60, height: 80))
        #expect(layout.frames[2] == CGRect(x: 185, y: 25, width: 40, height: 40))
    }

    @Test(arguments: [(CombineAlignment.leading, CGFloat(0)), (.center, 20), (.trailing, 40)])
    func verticalLayoutAlignsHorizontally(alignment: CombineAlignment, offset: CGFloat) {
        let layout = ImageCombiner.layout(for: sizes, style: CombineStyle(layout: .vertical, alignment: alignment, spacing: 0, padding: 0))
        #expect(layout.canvasSize == CGSize(width: 100, height: 170))
        #expect(layout.frames[1].minX == offset)
        #expect(layout.frames[2].minY == 130)
    }

    @Test func gridUsesSquareishColumns() {
        #expect(ImageCombiner.gridColumns(for: 4, preferred: nil) == 2)
        #expect(ImageCombiner.gridColumns(for: 5, preferred: nil) == 3)
        #expect(ImageCombiner.gridColumns(for: 3, preferred: 8) == 3)
        let layout = ImageCombiner.layout(for: sizes, style: CombineStyle(layout: .grid, alignment: .leading, spacing: 4, padding: 0, columns: 2))
        #expect(layout.canvasSize == CGSize(width: 164, height: 124))
        #expect(layout.frames[2] == CGRect(x: 0, y: 84, width: 40, height: 40))
    }

    @Test func combineDrawsEveryImageOverTheBackground() throws {
        let images = [TestImages.solid(width: 40, height: 40, color: red), TestImages.solid(width: 40, height: 20, color: blue)]
        let combined = try #require(ImageCombiner.combine(images, style: CombineStyle(layout: .horizontal, alignment: .leading, spacing: 10, padding: 10, cornerRadius: 0, fill: .solid(white))))
        #expect(combined.width == 110)
        #expect(combined.height == 60)
        #expect(isClose(TestImages.color(combined, 20, 20), red))
        #expect(isClose(TestImages.color(combined, 75, 15), blue))
        #expect(isClose(TestImages.color(combined, 75, 40), white))
        #expect(ImageCombiner.combine([], style: CombineStyle()) == nil)
    }

    @Test func combinedCornersAreTransparentWithRadius() throws {
        let images = [TestImages.solid(width: 40, height: 40, color: red), TestImages.solid(width: 40, height: 40, color: red)]
        let combined = try #require(ImageCombiner.combine(images, style: CombineStyle(layout: .vertical, spacing: 0, padding: 0, cornerRadius: 12, fill: .transparent)))
        #expect(TestImages.color(combined, 0, 0).alpha == 0)
        #expect(isClose(TestImages.color(combined, 20, 20), red))
    }
}

struct SmartShapesTests {
    let button = CGRect(x: 100, y: 100, width: 80, height: 30)
    let label = CGRect(x: 300, y: 100, width: 60, height: 20)

    @Test func snapsEdgesWithinTheThreshold() {
        let drawn = CGRect(x: 104, y: 97, width: 71, height: 36)
        #expect(SmartShapes.snap(drawn, to: [button, label], threshold: 8) == button)
    }

    @Test func leavesEdgesBeyondTheThreshold() {
        let drawn = CGRect(x: 120, y: 90, width: 40, height: 50)
        #expect(SmartShapes.snap(drawn, to: [button], threshold: 8) == drawn)
    }

    @Test func ignoresElementsThatDoNotLineUp() {
        let far = CGRect(x: 103, y: 600, width: 50, height: 20)
        let drawn = CGRect(x: 105, y: 300, width: 40, height: 40)
        #expect(SmartShapes.snap(drawn, to: [far], threshold: 8) == drawn)
    }

    @Test func keepsTheDragDirection() {
        let corners = SmartShapes.snappedCorners(from: CGPoint(x: 178, y: 132), to: CGPoint(x: 103, y: 99), targets: [button], threshold: 6)
        #expect(corners.start == CGPoint(x: 180, y: 130))
        #expect(corners.end == CGPoint(x: 100, y: 100))
    }

    @Test func neverCollapsesTheRectangle() {
        let thin = CGRect(x: 100, y: 100, width: 2, height: 40)
        let drawn = CGRect(x: 99, y: 90, width: 3, height: 60)
        let snapped = SmartShapes.snap(drawn, to: [thin], threshold: 8)
        #expect(snapped.width >= 1)
        #expect(snapped.height >= 1)
    }

    @Test func picksTheSmallestHoverCandidate() {
        let window = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(SmartShapes.candidate(at: CGPoint(x: 120, y: 110), in: [window, button], tolerance: 2) == button)
        #expect(SmartShapes.candidate(at: CGPoint(x: 900, y: 900), in: [window, button], tolerance: 2) == nil)
        #expect(SmartShapes.candidate(at: CGPoint(x: 99, y: 110), in: [button], tolerance: 2) == button)
    }

    @Test func matchesTargetsByOverlap() {
        #expect(SmartShapes.matchedTarget(for: button.insetBy(dx: 2, dy: 2), in: [button, label]) == button)
        #expect(SmartShapes.matchedTarget(for: CGRect(x: 0, y: 0, width: 500, height: 500), in: [button]) == nil)
        #expect(SmartShapes.overlapRatio(button, button) == 1)
    }

    @Test func supportsOnlyBoxTools() {
        #expect(SmartShapes.supports(.rectangle))
        #expect(SmartShapes.supports(.highlight))
        #expect(SmartShapes.supports(.spotlight))
        #expect(!SmartShapes.supports(.arrow))
    }

    @Test func convertsVisionBoxesToTopLeftPixels() {
        let rect = UIElementDetector.pixelRect(fromNormalized: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1), imageSize: CGSize(width: 1000, height: 500))
        #expect(rect == CGRect(x: 100, y: 100, width: 200, height: 50))
    }

    @Test func dropsDuplicateDetections() {
        let rects = [button, button.offsetBy(dx: 1, dy: -1), label, CGRect(x: 0, y: 0, width: 1, height: 1)]
        #expect(UIElementDetector.deduplicated(rects, tolerance: 3) == [button, label])
    }
}

struct EditorGeometryTests {
    @Test(arguments: [OrientationChange.rotateLeft, .rotateRight, .flipHorizontal, .flipVertical])
    func annotationsFollowTheImage(change: OrientationChange) throws {
        let marker = CGRect(x: 20, y: 10, width: 12, height: 8)
        let image = marked(width: 200, height: 100, marker: marker)
        let mapping = CanvasMapping.orientation(change, size: CGSize(width: 200, height: 100))
        let transformed: CGImage = switch change {
        case .rotateLeft: ImageProcessing.rotated(image, clockwise: false)
        case .rotateRight: ImageProcessing.rotated(image, clockwise: true)
        case .flipHorizontal: ImageProcessing.flipped(image, horizontally: true)
        case .flipVertical: ImageProcessing.flipped(image, horizontally: false)
        }
        #expect(CGSize(width: transformed.width, height: transformed.height) == mapping.outputSize)
        let mapped = mapping.map(marker)
        #expect(mapped.size == (change == .rotateLeft || change == .rotateRight ? CGSize(width: 8, height: 12) : marker.size))
        #expect(isClose(TestImages.color(transformed, Int(mapped.midX), Int(mapped.midY)), red))
        let annotation = Annotation(shape: .rectangle(marker), color: .blue, lineWidth: 2).mapped(by: mapping)
        #expect(annotation.shape == .rectangle(mapped))
    }

    @Test func fourQuarterTurnsAreIdentity() {
        var size = CGSize(width: 300, height: 120)
        var annotation = Annotation(shape: .arrow(CGPoint(x: 10, y: 20), CGPoint(x: 200, y: 90)), color: .red, lineWidth: 4)
        let original = annotation
        for _ in 0 ..< 4 {
            let mapping = CanvasMapping.orientation(.rotateRight, size: size)
            annotation = annotation.mapped(by: mapping)
            size = mapping.outputSize
        }
        #expect(size == CGSize(width: 300, height: 120))
        #expect(annotation.shape == original.shape)
    }

    @Test func textKeepsItsSizeWhenRotated() {
        let text = Annotation(shape: .text(CGPoint(x: 10, y: 10), "Hello"), color: .red, lineWidth: 2, fontSize: 20)
        let mapping = CanvasMapping.orientation(.rotateRight, size: CGSize(width: 200, height: 100))
        let rotated = text.mapped(by: mapping)
        #expect(rotated.bounds.size == text.bounds.size)
        let center = mapping.map(CGPoint(x: text.bounds.midX, y: text.bounds.midY))
        #expect(abs(rotated.bounds.midX - center.x) < 0.001)
        #expect(abs(rotated.bounds.midY - center.y) < 0.001)
    }

    @Test func inscribedScaleShrinksWithTheAngle() {
        #expect(StraightenGeometry.inscribedScale(for: CGSize(width: 100, height: 100), degrees: 0) == 1)
        #expect(abs(StraightenGeometry.inscribedScale(for: CGSize(width: 100, height: 100), degrees: 45) - 1 / 2.squareRoot()) < 0.0001)
        let wide = StraightenGeometry.inscribedScale(for: CGSize(width: 400, height: 100), degrees: 10)
        #expect(abs(wide - 100 / (400 * sin(10 * .pi / 180) + 100 * cos(10 * .pi / 180))) < 0.0001)
        #expect(StraightenGeometry.inscribedScale(for: CGSize(width: 400, height: 100), degrees: -10) == wide)
    }

    @Test func straightenedCropHasNoTransparentCorners() {
        let image = TestImages.solid(width: 300, height: 200, color: blue)
        let straightened = ImageProcessing.straightened(image, degrees: 12)
        let expected = StraightenGeometry.outputSize(for: CGSize(width: 300, height: 200), degrees: 12)
        #expect(CGSize(width: straightened.width, height: straightened.height) == expected)
        for (x, y) in [(0, 0), (straightened.width - 1, 0), (0, straightened.height - 1), (straightened.width - 1, straightened.height - 1)] {
            #expect(isClose(TestImages.color(straightened, x, y), blue))
        }
        #expect(ImageProcessing.straightened(image, degrees: 0) === image)
    }

    @Test(arguments: [8.0, -15.0])
    func straightenMovesAnnotationsWithThePixels(angle: Double) throws {
        let marker = CGRect(x: 180, y: 60, width: 14, height: 14)
        let image = marked(width: 300, height: 200, marker: marker)
        let straightened = ImageProcessing.straightened(image, degrees: angle)
        let mapping = CanvasMapping.straighten(degrees: angle, size: CGSize(width: 300, height: 200))
        let center = mapping.map(CGPoint(x: marker.midX, y: marker.midY))
        #expect(isClose(TestImages.color(straightened, Int(center.x), Int(center.y)), red, tolerance: 0.15))
        let mappedRect = mapping.map(marker)
        #expect(mappedRect.size == marker.size)
    }

    @Test func adjustmentsChangeTheImage() {
        let image = TestImages.solid(width: 20, height: 20, color: CaptureColor(red: 0.8, green: 0.2, blue: 0.2))
        #expect(ImageProcessing.adjusted(image, .identity) === image)
        let gray = TestImages.color(ImageProcessing.adjusted(image, ImageAdjustments(saturation: 0)), 10, 10)
        #expect(abs(gray.red - gray.green) < 0.03)
        #expect(abs(gray.green - gray.blue) < 0.03)
        let brighter = ImageProcessing.averageLuminance(of: ImageProcessing.adjusted(image, ImageAdjustments(brightness: 0.3)))
        let exposed = ImageProcessing.averageLuminance(of: ImageProcessing.adjusted(image, ImageAdjustments(exposure: 1)))
        let darker = ImageProcessing.averageLuminance(of: ImageProcessing.adjusted(image, ImageAdjustments(exposure: -1)))
        let original = ImageProcessing.averageLuminance(of: image)
        #expect(brighter > original)
        #expect(exposed > original)
        #expect(darker < original)
        #expect(ImageAdjustments(contrast: 1.2).usesColorControls)
        #expect(!ImageAdjustments(exposure: 1).usesColorControls)
    }
}

@MainActor
struct EditorTransformDocumentTests {
    @Test func rotatingKeepsAnnotationsAndIsUndoable() {
        let document = EditorDocument(image: TestImages.solid(width: 200, height: 100, color: white), fileURL: nil)
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 30)), color: .blue, lineWidth: 2))
        document.applyCrop(CGRect(x: 0, y: 0, width: 100, height: 50))
        document.apply(.rotateRight)
        #expect(document.imageSize == CGSize(width: 100, height: 200))
        #expect(document.annotations.first?.shape == .rectangle(CGRect(x: 60, y: 10, width: 30, height: 20)))
        #expect(document.crop == CGRect(x: 50, y: 0, width: 50, height: 100))
        #expect(document.hasChanges)
        document.undo()
        #expect(document.imageSize == CGSize(width: 200, height: 100))
        #expect(document.annotations.first?.shape == .rectangle(CGRect(x: 10, y: 10, width: 20, height: 30)))
    }

    @Test func straightenIsUndoableAndResetsThePreview() {
        let document = EditorDocument(image: TestImages.solid(width: 300, height: 200, color: white), fileURL: nil)
        document.add(Annotation(shape: .step(CGPoint(x: 150, y: 100), 1), color: .red, lineWidth: 2))
        document.straightenAngle = 10
        document.applyStraighten()
        #expect(document.straightenAngle == 0)
        #expect(document.imageSize == StraightenGeometry.outputSize(for: CGSize(width: 300, height: 200), degrees: 10))
        if case let .step(center, _) = document.annotations.first?.shape {
            #expect(abs(center.x - document.imageSize.width / 2) < 0.001)
            #expect(abs(center.y - document.imageSize.height / 2) < 0.001)
        } else {
            Issue.record("The step should survive straightening")
        }
        document.undo()
        #expect(document.imageSize == CGSize(width: 300, height: 200))
    }

    @Test func adjustmentsAreUndoableAndCoalesceWhileDragging() {
        let document = EditorDocument(image: TestImages.solid(width: 40, height: 40, color: CaptureColor(red: 0.5, green: 0.5, blue: 0.5)), fileURL: nil)
        document.beginContinuousChange()
        document.updateAdjustments { $0.brightness = 0.1 }
        document.updateAdjustments { $0.brightness = 0.2 }
        document.endContinuousChange()
        #expect(document.adjustments.brightness == 0.2)
        #expect(document.adjustedBase !== document.base)
        #expect(document.hasChanges)
        document.updateAdjustments { $0.saturation = 0 }
        document.undo()
        #expect(document.adjustments.saturation == 1)
        document.undo()
        #expect(document.adjustments.isIdentity)
        #expect(document.adjustedBase === document.base)
        #expect(!document.hasChanges)
    }

    @Test func beautifyFlattensIntoTheBase() {
        let document = EditorDocument(image: TestImages.solid(width: 100, height: 60, color: white), fileURL: nil)
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: .blue, lineWidth: 2))
        document.applyBeautify(BeautifyStyle(padding: 10, cornerRadius: 0, shadowRadius: 0, fill: .solid(red)))
        #expect(document.imageSize == CGSize(width: 120, height: 80))
        #expect(document.annotations.isEmpty)
        document.undo()
        #expect(document.imageSize == CGSize(width: 100, height: 60))
        #expect(document.annotations.count == 1)
    }
}

struct VectorExportTests {
    final class ElementCollector: NSObject, XMLParserDelegate {
        var names: [String] = []
        var attributes: [[String: String]] = []
        var text = ""

        func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
            names.append(elementName)
            attributes.append(attributeDict)
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            text += string
        }

        func count(_ name: String) -> Int {
            names.filter { $0 == name }.count
        }
    }

    var input: VectorExportInput {
        var hidden = Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 5, height: 5)), color: .red, lineWidth: 2)
        hidden.hidden = true
        var dashed = Annotation(shape: .line(CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)), color: .green, lineWidth: 3)
        dashed.dashed = true
        var labelled = Annotation(shape: .text(CGPoint(x: 20, y: 120), "Tom & <Jerry>\nline two"), color: .black, lineWidth: 2, fontSize: 18)
        labelled.textBackground = true
        return VectorExportInput(
            base: TestImages.solid(width: 300, height: 200, color: white),
            annotations: [
                Annotation(shape: .arrow(CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 80)), color: .red, lineWidth: 4),
                Annotation(shape: .curvedArrow(CGPoint(x: 10, y: 150), CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 160)), color: .blue, lineWidth: 4),
                Annotation(shape: .rectangle(CGRect(x: 150, y: 20, width: 60, height: 40)), color: .blue, lineWidth: 3),
                Annotation(shape: .ellipse(CGRect(x: 220, y: 20, width: 40, height: 40)), color: .orange, lineWidth: 3, filled: true),
                Annotation(shape: .highlight(CGRect(x: 150, y: 80, width: 60, height: 20)), color: .yellow, lineWidth: 3),
                Annotation(shape: .pen([CGPoint(x: 10, y: 190), CGPoint(x: 40, y: 170), CGPoint(x: 70, y: 190)]), color: .purple, lineWidth: 3),
                Annotation(shape: .marker([CGPoint(x: 100, y: 190), CGPoint(x: 140, y: 190)]), color: .yellow, lineWidth: 3),
                labelled,
                Annotation(shape: .step(CGPoint(x: 250, y: 150), 3), color: .red, lineWidth: 2, fontSize: 20),
                Annotation(shape: .callout(CGPoint(x: 200, y: 190), CGRect(x: 220, y: 100, width: 70, height: 30), "Hi"), color: .blue, lineWidth: 2, fontSize: 14),
                Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 40, height: 40)), color: .red, lineWidth: 2),
                Annotation(shape: .pixelate(CGRect(x: 40, y: 0, width: 40, height: 40)), color: .red, lineWidth: 2),
                Annotation(shape: .spotlight(CGRect(x: 100, y: 100, width: 50, height: 50)), color: .red, lineWidth: 2),
                Annotation(shape: .magnify(CGRect(x: 160, y: 120, width: 40, height: 40)), color: .white, lineWidth: 3),
                dashed,
                hidden,
            ],
            crop: nil
        )
    }

    @Test func svgParsesAndContainsVectorElements() throws {
        let svg = SVGExporter.document(for: input)
        let parser = XMLParser(data: Data(svg.utf8))
        let collector = ElementCollector()
        parser.delegate = collector
        #expect(parser.parse(), "\(parser.parserError?.localizedDescription ?? "")")
        #expect(collector.names.first == "svg")
        #expect(collector.count("image") == 2)
        #expect(collector.count("rect") == 3)
        #expect(collector.count("ellipse") == 3)
        #expect(collector.count("circle") == 1)
        #expect(collector.count("line") == 1)
        #expect(collector.count("text") == 3)
        #expect(collector.count("tspan") == 4)
        #expect(collector.count("clipPath") == 1)
        #expect(collector.count("path") == 8)
        #expect(collector.text.contains("Tom & <Jerry>"))
        #expect(collector.text.contains("line two"))
        #expect(collector.attributes.contains { $0["stroke-dasharray"] != nil })
        #expect(collector.attributes.contains { $0["fill-rule"] == "evenodd" })
        #expect(collector.attributes.first?["viewBox"] == "0 0 300 200")
        #expect(collector.attributes.contains { ($0["xlink:href"] ?? "").hasPrefix("data:image/png;base64,") })
    }

    @Test func svgUsesTheCropAsViewBox() throws {
        var cropped = input
        cropped.crop = CGRect(x: 10, y: 20, width: 100, height: 80)
        let svg = SVGExporter.document(for: cropped)
        let collector = ElementCollector()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = collector
        #expect(parser.parse())
        #expect(collector.attributes.first?["viewBox"] == "10 20 100 80")
        #expect(collector.attributes.first?["width"] == "100")
        let image = try #require(collector.names.firstIndex(of: "image").map { collector.attributes[$0] })
        #expect(image["x"] == "10")
        #expect(image["width"] == "100")
    }

    @Test func svgEmbedsTheRasterizedEffects() throws {
        let image = TestImages.checkerboard(width: 40, height: 40)
        let export = VectorExportInput(base: image, annotations: [Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 40, height: 40)), color: .red, lineWidth: 2)], crop: nil)
        #expect(export.rasterizedBase !== image)
        let svg = SVGExporter.document(for: export)
        let uri = try #require(SVGExporter.dataURI(for: export.rasterizedBase))
        #expect(svg.contains(uri))
        #expect(!svg.contains("<rect"))
    }

    @Test func formatsNumbersCompactly() {
        #expect(SVGExporter.number(10) == "10")
        #expect(SVGExporter.number(1.5) == "1.5")
        #expect(SVGExporter.number(1.256) == "1.26")
        #expect(SVGExporter.number(-0.5) == "-0.5")
        #expect(SVGExporter.escaped("a<b>&\"c'") == "a&lt;b&gt;&amp;&quot;c&apos;")
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 1, y: 2))
        path.addQuadCurve(to: CGPoint(x: 3, y: 4), control: CGPoint(x: 5, y: 6))
        path.closeSubpath()
        #expect(SVGExporter.pathData(path) == "M0 0 L1 2 Q5 6 3 4 Z")
        #expect(SVGExporter.color(.red) == "rgb(255,59,48)")
    }

    @Test func pdfHasOnePageWithTheImageSize() throws {
        let data = try #require(PDFExporter.data(for: input))
        let document = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
        #expect(document.numberOfPages == 1)
        let page = try #require(document.page(at: 1))
        #expect(page.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func pdfMediaBoxFollowsTheCrop() throws {
        var cropped = input
        cropped.crop = CGRect(x: 30, y: 40, width: 120.4, height: 90)
        let data = try #require(PDFExporter.data(for: cropped))
        let page = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init)?.page(at: 1))
        #expect(page.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 121, height: 90))
    }
}

struct SubjectLiftTests {
    @Test func reportsAMissingSubjectClearly() async {
        let image = TestImages.solid(width: 64, height: 64, color: white)
        await #expect(throws: (any Error).self) {
            try await SubjectLifter.lift(image, croppedToSubject: true)
        }
        #expect(SubjectLiftError.noSubject.errorDescription?.isEmpty == false)
    }
}
