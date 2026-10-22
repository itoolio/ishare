import CoreGraphics
import Foundation
import Testing
@testable import ishare

private func solidImage(width: Int = 400, height: Int = 300, gray: CGFloat = 1) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return data
}

private func isClose(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

struct CanvasTransformTests {
    @Test(arguments: [0.1, 0.33, 0.5, 1, 2, 4, 8] as [CGFloat])
    func mapsBetweenViewAndImageAtEveryZoom(scale: CGFloat) {
        let visible = CGRect(x: 120, y: 80, width: 800, height: 500)
        let transform = CanvasTransform.make(visibleRect: visible, container: CGSize(width: 900, height: 600), scale: scale, center: CGPoint(x: 400, y: 300))
        for point in [CGPoint(x: 120, y: 80), CGPoint(x: 400, y: 300), CGPoint(x: 919.5, y: 579.25)] {
            #expect(isClose(transform.toImage(transform.toView(point)), point))
        }
        let rect = CGRect(x: 200, y: 150, width: 60, height: 40)
        let viewRect = transform.toView(rect)
        #expect(abs(viewRect.width - 60 * scale) < 0.001)
        #expect(isClose(transform.toImage(viewRect).origin, rect.origin))
        #expect(isClose(transform.toView(visible.origin), transform.origin))
        #expect(isClose(CGPoint(x: 400, y: 300).applying(transform.cgTransform), transform.toView(CGPoint(x: 400, y: 300))))
    }

    @Test func centersContentThatFits() {
        let transform = CanvasTransform.make(visibleRect: CGRect(x: 0, y: 0, width: 400, height: 200), container: CGSize(width: 1000, height: 600), scale: 1, center: nil)
        #expect(transform.contentRect == CGRect(x: 300, y: 200, width: 400, height: 200))
    }

    @Test func clampsPanningToTheContentEdges() {
        let container = CGSize(width: 500, height: 400)
        let transform = CanvasTransform.make(visibleRect: CGRect(x: 0, y: 0, width: 2000, height: 1000), container: container, scale: 1, center: CGPoint(x: -500, y: 5000))
        #expect(transform.origin.x == CanvasTransform.padding)
        #expect(transform.origin.y == container.height - 1000 - CanvasTransform.padding)
        let panned = transform.panned(by: CGVector(dx: -300, dy: 0), in: container)
        #expect(panned.origin.x == CanvasTransform.padding - 300)
    }

    @Test func zoomKeepsTheAnchorUnderThePointer() {
        let container = CGSize(width: 800, height: 600)
        let transform = CanvasTransform.make(visibleRect: CGRect(x: 0, y: 0, width: 3000, height: 2000), container: container, scale: 0.5, center: CGPoint(x: 1500, y: 1000))
        let anchor = CGPoint(x: 300, y: 250)
        let pinned = transform.toImage(anchor)
        let zoomed = transform.zoomed(to: 2, anchor: anchor, in: container)
        #expect(isClose(zoomed.toView(pinned), anchor))
    }

    @Test func fitsWithoutUpscalingBeyondActualSize() {
        #expect(CanvasTransform.fitScale(for: CGSize(width: 200, height: 100), in: CGSize(width: 1000, height: 800), backingScale: 2) == 0.5)
        #expect(CanvasTransform.fitScale(for: CGSize(width: 4000, height: 1000), in: CGSize(width: 1040, height: 800), backingScale: 2) == 0.25)
    }

    @Test func stepsThroughZoomLevels() {
        #expect(CanvasTransform.zoomIn(from: 1) == 1.25)
        #expect(CanvasTransform.zoomOut(from: 1) == 0.75)
        #expect(CanvasTransform.zoomIn(from: 8) == 8)
        #expect(CanvasTransform.zoomOut(from: 0.1) == 0.1)
        #expect(CanvasTransform.clampZoom(20) == CanvasTransform.maximumZoom)
    }
}

@MainActor
struct EditorViewportTests {
    @Test func switchesBetweenFitAndActualSize() {
        let viewport = EditorViewport(visibleRect: CGRect(x: 0, y: 0, width: 4000, height: 2000), backingScale: 2)
        viewport.update(containerSize: CGSize(width: 1040, height: 800))
        #expect(viewport.isFit)
        #expect(viewport.percentage == 50)
        viewport.actualSize()
        #expect(viewport.percentage == 100)
        #expect(viewport.transform.scale == 0.5)
        viewport.zoomIn()
        #expect(viewport.percentage == 125)
        viewport.fit()
        #expect(viewport.percentage == 50)
    }

    @Test func pansOnlyWhenZoomedIn() {
        let viewport = EditorViewport(visibleRect: CGRect(x: 0, y: 0, width: 4000, height: 2000), backingScale: 2)
        viewport.update(containerSize: CGSize(width: 1040, height: 800))
        let fitted = viewport.transform
        viewport.pan(by: CGVector(dx: 100, dy: 0))
        #expect(viewport.transform == fitted)
        viewport.setZoom(2)
        let before = viewport.transform.origin
        viewport.pan(by: CGVector(dx: 100, dy: 50))
        #expect(viewport.transform.origin.x == before.x + 100)
        #expect(viewport.transform.origin.y == before.y + 50)
    }
}

struct CropGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func resizesCornersWithAnAspectRatio() {
        let rect = CropGeometry.resize(CGRect(x: 100, y: 100, width: 200, height: 200), handle: .bottomRight, to: CGPoint(x: 500, y: 250), ratio: 1, bounds: bounds)
        #expect(rect == CGRect(x: 100, y: 100, width: 400, height: 400))
        let clamped = CropGeometry.resize(CGRect(x: 100, y: 100, width: 200, height: 200), handle: .bottomRight, to: CGPoint(x: 2000, y: 2000), ratio: 1, bounds: bounds)
        #expect(clamped == CGRect(x: 100, y: 100, width: 500, height: 500))
    }

    @Test func resizesEdgesFreelyWithinBounds() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        #expect(CropGeometry.resize(rect, handle: .left, to: CGPoint(x: -50, y: 0), ratio: nil, bounds: bounds) == CGRect(x: 0, y: 100, width: 300, height: 200))
        #expect(CropGeometry.resize(rect, handle: .bottom, to: CGPoint(x: 0, y: 450), ratio: nil, bounds: bounds) == CGRect(x: 100, y: 100, width: 200, height: 350))
        #expect(CropGeometry.resize(rect, handle: .right, to: CGPoint(x: 0, y: 0), ratio: nil, bounds: bounds).width == CropGeometry.minimumSize)
    }

    @Test func resizesEdgesWithAnAspectRatioAroundTheCenter() {
        let rect = CropGeometry.resize(CGRect(x: 100, y: 100, width: 200, height: 200), handle: .right, to: CGPoint(x: 400, y: 0), ratio: 1, bounds: bounds)
        #expect(rect == CGRect(x: 100, y: 50, width: 300, height: 300))
    }

    @Test func fitsPresetsInsideTheImage() {
        let wide = CropGeometry.fit(bounds, ratio: 16.0 / 9.0, bounds: bounds)
        #expect(abs(wide.width / wide.height - 16.0 / 9.0) < 0.001)
        #expect(bounds.contains(wide))
        #expect(wide.width == 1000)
        let tall = CropGeometry.fit(bounds, ratio: 9.0 / 16.0, bounds: bounds)
        #expect(tall.height == 600)
        #expect(abs(tall.midX - 500) < 0.001)
    }

    @Test func findsTheNearestHandle() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(CropGeometry.handle(at: CGPoint(x: 103, y: 98), in: rect, tolerance: 8) == .topLeft)
        #expect(CropGeometry.handle(at: CGPoint(x: 200, y: 203), in: rect, tolerance: 8) == .bottom)
        #expect(CropGeometry.handle(at: CGPoint(x: 200, y: 150), in: rect, tolerance: 8) == nil)
        #expect(CropGeometry.thirds(of: rect).count == 4)
    }

    @Test func resolvesAspectRatios() {
        #expect(CropAspect.free.ratio(for: CGSize(width: 10, height: 5)) == nil)
        #expect(CropAspect.original.ratio(for: CGSize(width: 10, height: 5)) == 2)
        #expect(abs((CropAspect.nineSixteen.ratio(for: .zero) ?? 0) - 0.5625) < 0.0001)
    }
}

@MainActor
struct EditorCropFlowTests {
    @Test func editsCropsWithPresetsUndoAndCancel() throws {
        let document = EditorDocument(image: solidImage(width: 400, height: 300), fileURL: nil)
        document.select(tool: .pen)
        document.select(tool: .crop)
        #expect(document.draftCrop == document.imageBounds)
        #expect(document.visibleRect == document.imageBounds)
        document.setCropAspect(.square)
        #expect(document.draftCrop == CGRect(x: 50, y: 0, width: 300, height: 300))
        document.applyPendingCrop()
        #expect(document.crop == CGRect(x: 50, y: 0, width: 300, height: 300))
        #expect(document.tool == .pen)
        #expect(document.visibleRect == document.crop)
        let rendered = try #require(document.render())
        #expect(rendered.width == 300 && rendered.height == 300)

        document.select(tool: .crop)
        #expect(document.draftCrop == document.crop)
        document.draftCrop = CGRect(x: 0, y: 0, width: 100, height: 100)
        document.cancelCropping()
        #expect(document.crop == CGRect(x: 50, y: 0, width: 300, height: 300))

        document.select(tool: .crop)
        document.undo()
        #expect(document.crop == nil)
        #expect(document.draftCrop == document.imageBounds)
        document.redo()
        #expect(document.draftCrop == CGRect(x: 50, y: 0, width: 300, height: 300))
        document.resetCrop()
        #expect(document.crop == nil)
        #expect(document.draftCrop == document.imageBounds)
        document.commitPendingEdits()
        #expect(!document.isCropping)
        #expect(document.crop == nil)
    }

    @Test func switchingToolsAppliesThePendingCrop() {
        let document = EditorDocument(image: solidImage(), fileURL: nil)
        document.select(tool: .crop)
        document.draftCrop = CGRect(x: 10, y: 10, width: 100, height: 80)
        document.select(tool: .arrow)
        #expect(document.crop == CGRect(x: 10, y: 10, width: 100, height: 80))
        #expect(document.draftCrop == nil)
    }
}

@MainActor
struct SpotlightTests {
    @Test func dimsEverythingOutsideTheUnionOfSpotlights() throws {
        let document = EditorDocument(image: solidImage(gray: 1), fileURL: nil)
        document.add(Annotation(shape: .spotlight(CGRect(x: 20, y: 20, width: 100, height: 100)), color: .red, lineWidth: 2, spotlightShape: .rectangle))
        document.add(Annotation(shape: .spotlight(CGRect(x: 80, y: 80, width: 100, height: 100)), color: .red, lineWidth: 2, spotlightShape: .rectangle))
        let rendered = try #require(document.render())
        #expect(pixel(rendered, x: 50, y: 50)[0] == 255)
        #expect(pixel(rendered, x: 100, y: 100)[0] == 255)
        #expect(pixel(rendered, x: 160, y: 160)[0] == 255)
        let outside = pixel(rendered, x: 300, y: 250)[0]
        #expect(outside > 100 && outside < 130)
    }

    @Test func respectsShapeAndDimAmount() throws {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let document = EditorDocument(image: solidImage(gray: 1), fileURL: nil)
        document.add(Annotation(shape: .spotlight(rect), color: .red, lineWidth: 2, spotlightShape: .ellipse))
        document.setDimAmount(0.8)
        let ellipse = try #require(document.render())
        #expect(pixel(ellipse, x: 150, y: 150)[0] == 255)
        #expect(pixel(ellipse, x: 103, y: 103)[0] < 70)
        document.updateAnnotations(where: \.isSpotlight) { $0.spotlightShape = .rectangle }
        let rectangle = try #require(document.render())
        #expect(pixel(rectangle, x: 105, y: 105)[0] == 255)
        document.undo()
        #expect(document.annotations.first?.spotlightShape == .ellipse)
    }

    @Test func prefersOtherAnnotationsWhenHitTesting() {
        let document = EditorDocument(image: solidImage(), fileURL: nil)
        let arrow = Annotation(shape: .arrow(CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50)), color: .red, lineWidth: 4)
        document.add(arrow)
        let spotlight = Annotation(shape: .spotlight(CGRect(x: 0, y: 0, width: 300, height: 200)), color: .red, lineWidth: 4)
        document.add(spotlight)
        #expect(document.annotation(at: CGPoint(x: 100, y: 50))?.id == arrow.id)
        #expect(document.annotation(at: CGPoint(x: 250, y: 150))?.id == spotlight.id)
    }

    @Test func slidingTheDimAmountIsOneUndoStep() {
        let document = EditorDocument(image: solidImage(), fileURL: nil)
        document.add(Annotation(shape: .spotlight(CGRect(x: 0, y: 0, width: 50, height: 50)), color: .red, lineWidth: 4))
        document.beginContinuousChange()
        document.setDimAmount(0.3)
        document.setDimAmount(0.2)
        document.endContinuousChange()
        #expect(document.annotations.first?.dimAmount == 0.2)
        document.undo()
        #expect(document.annotations.first?.dimAmount == Annotation.defaultDimAmount)
        #expect(document.annotations.count == 1)
    }
}

@MainActor
struct ArrowStyleTests {
    @Test func createsCurvedArrowsWithTheDocumentStyle() throws {
        let document = EditorDocument(image: solidImage(), fileURL: nil)
        document.arrowPath = .curved
        document.arrowHead = .open
        document.doubleHeaded = true
        document.dashed = true
        let arrow = try #require(document.makeAnnotation(tool: .arrow, from: CGPoint(x: 20, y: 150), to: CGPoint(x: 380, y: 150), points: []))
        guard case let .curvedArrow(start, control, end) = arrow.shape else {
            Issue.record("Expected a curved arrow")
            return
        }
        #expect(start == CGPoint(x: 20, y: 150) && end == CGPoint(x: 380, y: 150))
        #expect(control.y != 150)
        #expect(arrow.arrowHead == .open && arrow.doubleHeaded && arrow.dashed)
        #expect(document.isSubstantial(arrow))
    }

    @Test func dragsTheControlHandleThroughThePointer() {
        let arrow = Annotation(shape: .curvedArrow(CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)), color: .red, lineWidth: 4)
        let edited = arrow.editing(.control, to: CGPoint(x: 50, y: 80))
        guard case let .curvedArrow(start, control, end) = edited.shape else {
            Issue.record("Expected a curved arrow")
            return
        }
        #expect(isClose(ArrowGeometry.midpoint(from: start, control: control, to: end), CGPoint(x: 50, y: 80)))
        #expect(edited.hitTest(CGPoint(x: 50, y: 80), tolerance: 2))
        #expect(!edited.hitTest(CGPoint(x: 50, y: 0), tolerance: 2))
        #expect(edited.editHandle(at: CGPoint(x: 51, y: 79), tolerance: 5) == .control)
    }

    @Test func drawsCurvedDoubleHeadedArrows() throws {
        let document = EditorDocument(image: solidImage(gray: 1), fileURL: nil)
        let control = ArrowGeometry.control(passingThrough: CGPoint(x: 200, y: 60), from: CGPoint(x: 40, y: 200), to: CGPoint(x: 360, y: 200))
        document.add(Annotation(shape: .curvedArrow(CGPoint(x: 40, y: 200), control, CGPoint(x: 360, y: 200)), color: .black, lineWidth: 8, doubleHeaded: true))
        let rendered = try #require(document.render())
        #expect(pixel(rendered, x: 200, y: 60)[0] < 60)
        #expect(pixel(rendered, x: 200, y: 200)[0] == 255)
        #expect(pixel(rendered, x: 47, y: 187)[0] < 60)
        #expect(pixel(rendered, x: 353, y: 187)[0] < 60)
    }

    @Test func dashesLines() throws {
        let document = EditorDocument(image: solidImage(gray: 1), fileURL: nil)
        document.add(Annotation(shape: .line(CGPoint(x: 0, y: 100), CGPoint(x: 400, y: 100)), color: .black, lineWidth: 6, dashed: true))
        let rendered = try #require(document.render())
        let row = (0 ..< 120).map { pixel(rendered, x: $0, y: 100)[0] }
        #expect(row.contains { $0 < 30 })
        #expect(row.contains { $0 > 225 })
    }

    @Test func drawsOpenAndLineHeads() throws {
        for head in [ArrowHead.open, .line] {
            let document = EditorDocument(image: solidImage(gray: 1), fileURL: nil)
            document.add(Annotation(shape: .arrow(CGPoint(x: 20, y: 150), CGPoint(x: 380, y: 150)), color: .black, lineWidth: 6, arrowHead: head))
            let rendered = try #require(document.render())
            #expect(pixel(rendered, x: 200, y: 150)[0] < 30)
            #expect(pixel(rendered, x: 365, y: 133)[0] == 255)
        }
    }

    @Test func convertsTheSelectionBetweenPaths() {
        var arrow = Annotation(shape: .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)), color: .red, lineWidth: 4)
        arrow.setArrowPath(.curved)
        guard case .curvedArrow = arrow.shape else {
            Issue.record("Expected a curved arrow")
            return
        }
        arrow.setArrowPath(.straight)
        #expect(arrow.shape == .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)))
    }
}

@MainActor
struct StampTests {
    @Test func placesStampsAtTheDefaultSizeOrTheDraggedSize() throws {
        let document = EditorDocument(image: solidImage(width: 1200, height: 600), fileURL: nil)
        document.stamp = .emoji("🎉")
        let clicked = try #require(document.makeAnnotation(tool: .stamp, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 300, y: 300), points: []))
        #expect(clicked.bounds == CGRect(x: 250, y: 250, width: 100, height: 100))
        #expect(document.isSubstantial(clicked))
        let dragged = try #require(document.makeAnnotation(tool: .stamp, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 80, y: 40), points: []))
        #expect(dragged.bounds == CGRect(x: 0, y: 0, width: 80, height: 80))
        #expect(dragged.shape == .stamp(CGRect(x: 0, y: 0, width: 80, height: 80), .emoji("🎉")))
    }

    @Test func resizesStampsProportionally() {
        let stamp = Annotation(shape: .stamp(CGRect(x: 0, y: 0, width: 50, height: 50), .symbol("star.fill")), color: .red, lineWidth: 4)
        #expect(stamp.editHandles.count == 4)
        let resized = stamp.editing(.resize(.bottomRight), to: CGPoint(x: 120, y: 90))
        #expect(resized.bounds == CGRect(x: 0, y: 0, width: 120, height: 120))
        let moved = resized.offset(by: CGVector(dx: 10, dy: 5))
        #expect(moved.bounds.origin == CGPoint(x: 10, y: 5))
    }

    @Test func rendersSymbolAndEmojiStamps() throws {
        let document = EditorDocument(image: solidImage(gray: 1), fileURL: nil)
        document.add(Annotation(shape: .stamp(CGRect(x: 20, y: 20, width: 120, height: 120), .symbol("heart.fill")), color: .red, lineWidth: 4))
        document.add(Annotation(shape: .stamp(CGRect(x: 220, y: 20, width: 120, height: 120), .emoji("🔥")), color: .red, lineWidth: 4))
        let rendered = try #require(document.render())
        let heart = pixel(rendered, x: 80, y: 85)
        #expect(heart[0] > 200 && heart[1] < 120)
        let fire = (40 ..< 120).map { pixel(rendered, x: 280, y: 20 + $0) }
        #expect(fire.contains { $0[2] < 150 })
        #expect(pixel(rendered, x: 200, y: 250) == [255, 255, 255, 255])
    }

    @Test func picksEmojiFromCharacterPaletteInput() {
        #expect(Stamp.firstEmoji(in: "abc😀") == "😀")
        #expect(Stamp.firstEmoji(in: "❤️") == "❤️")
        #expect(Stamp.firstEmoji(in: "abc123") == nil)
    }

    @Test func resizesRectangleAnnotationsThroughHandles() {
        let rectangle = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)), color: .red, lineWidth: 4)
        #expect(rectangle.editHandles.count == 8)
        let resized = rectangle.editing(.resize(.left), to: CGPoint(x: 0, y: 30))
        #expect(resized.bounds == CGRect(x: 0, y: 10, width: 110, height: 50))
        let line = Annotation(shape: .line(.zero, CGPoint(x: 10, y: 10)), color: .red, lineWidth: 2)
        #expect(line.editing(.end, to: CGPoint(x: 40, y: 0)).shape == .line(.zero, CGPoint(x: 40, y: 0)))
    }
}
