import CoreGraphics
import Foundation
import Testing
@testable import ishare

private func makeImage(width: Int = 400, height: Int = 300, gray: CGFloat = 1) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func stripedImage(width: Int = 400, height: Int = 300) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0 ..< width {
        context.setFillColor(CGColor(srgbRed: x % 4 < 2 ? 0 : 1, green: CGFloat(x) / CGFloat(width), blue: x % 6 < 3 ? 0.2 : 0.9, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    return context.makeImage()!
}

private func pixels(of image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return data
}

private func maximumDifference(_ lhs: CGImage, _ rhs: CGImage) -> Int {
    guard lhs.width == rhs.width, lhs.height == rhs.height else { return .max }
    return zip(pixels(of: lhs), pixels(of: rhs)).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

private func isClose(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

private func isClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.001) -> Bool {
    isClose(lhs.origin, rhs.origin, tolerance: tolerance) && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
}

private func rectangle(_ rect: CGRect, color: RGBAColor = .red) -> Annotation {
    Annotation(shape: .rectangle(rect), color: color, lineWidth: 4)
}

private final class ManualClock {
    var now: TimeInterval = 100
}

struct AnnotationTemplateTests {
    @Test func roundTripsEveryShapeThroughJSON() throws {
        var arrow = Annotation(shape: .curvedArrow(CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 0), CGPoint(x: 90, y: 40)), color: .blue, lineWidth: 5)
        arrow.arrowHead = .open
        arrow.doubleHeaded = true
        arrow.dashed = true
        var spotlight = Annotation(shape: .spotlight(CGRect(x: 30, y: 30, width: 100, height: 60)), color: .black, lineWidth: 2)
        spotlight.spotlightShape = .ellipse
        spotlight.dimAmount = 0.7
        let source: [Annotation] = [
            arrow,
            spotlight,
            Annotation(shape: .text(CGPoint(x: 5, y: 6), "Hello"), color: .green, lineWidth: 3, fontSize: 24, textBackground: true),
            Annotation(shape: .stamp(CGRect(x: 200, y: 100, width: 40, height: 40), .emoji("🔥")), color: .red, lineWidth: 3),
            Annotation(shape: .stamp(CGRect(x: 250, y: 100, width: 40, height: 40), .symbol("star.fill")), color: .yellow, lineWidth: 3),
            Annotation(shape: .pen([CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]), color: .purple, lineWidth: 2),
            Annotation(shape: .callout(CGPoint(x: 10, y: 10), CGRect(x: 40, y: 40, width: 120, height: 40), "Hi"), color: .orange, lineWidth: 2),
            Annotation(shape: .step(CGPoint(x: 300, y: 200), 2), color: .red, lineWidth: 2),
            Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .white, lineWidth: 1, filled: true),
        ]
        let template = AnnotationTemplate(name: "Review", annotations: source, frame: CGRect(x: 0, y: 0, width: 400, height: 300), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try AnnotationTemplate.decode(template.encoded())
        #expect(decoded.id == template.id)
        #expect(decoded.name == "Review")
        #expect(decoded.createdAt == template.createdAt)
        #expect(decoded.referenceSize == CGSize(width: 400, height: 300))
        #expect(decoded.annotations.count == source.count)
        for (lhs, rhs) in zip(decoded.annotations, template.annotations) {
            var normalizedID = lhs
            normalizedID.id = rhs.id
            #expect(normalizedID == rhs)
        }
    }

    @Test func decodesAnnotationsWithMissingStyleFields() throws {
        let json = #"{"shape":{"rectangle":{"_0":[[1,2],[3,4]]}}}"#
        let annotation = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        #expect(annotation.shape == .rectangle(CGRect(x: 1, y: 2, width: 3, height: 4)))
        #expect(annotation.arrowHead == .filled)
        #expect(!annotation.locked)
        #expect(!annotation.hidden)
    }

    @Test func storesPositionsRelativeToTheFrame() throws {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let template = AnnotationTemplate(name: "A", annotations: [rectangle(CGRect(x: 100, y: 50, width: 200, height: 100))], frame: frame)
        guard case let .rectangle(normalized) = template.annotations.first?.shape else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(isClose(normalized, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
    }

    @Test func scalesPositionsAndLengthsToTheTargetFrame() throws {
        var line = Annotation(shape: .line(CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 300)), color: .red, lineWidth: 6, fontSize: 20)
        line.dashed = true
        let stamp = Annotation(shape: .stamp(CGRect(x: 180, y: 130, width: 40, height: 40), .emoji("✅")), color: .red, lineWidth: 6)
        let template = AnnotationTemplate(name: "B", annotations: [line, stamp], frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let placed = template.annotations(fittedTo: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(placed[0].shape == .line(CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 600)))
        #expect(abs(placed[0].lineWidth - 12) < 0.001)
        #expect(abs(placed[0].fontSize - 40) < 0.001)
        #expect(placed[0].dashed)
        guard case let .stamp(rect, .emoji("✅")) = placed[1].shape else {
            Issue.record("Expected a stamp")
            return
        }
        #expect(isClose(rect, CGRect(x: 360, y: 260, width: 80, height: 80)))
        #expect(placed[0].id != line.id)
    }

    @Test func keepsSquareShapesSquareWhenTheAspectRatioChanges() {
        let magnifier = Annotation(shape: .magnify(CGRect(x: 150, y: 100, width: 100, height: 100)), color: .red, lineWidth: 4)
        let template = AnnotationTemplate(name: "C", annotations: [magnifier], frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let placed = template.annotations(fittedTo: CGRect(x: 0, y: 0, width: 1600, height: 300))
        guard case let .magnify(rect) = placed[0].shape else {
            Issue.record("Expected a magnifier")
            return
        }
        #expect(abs(rect.width - rect.height) < 0.001)
        #expect(abs(rect.width - 200) < 0.001)
        #expect(isClose(CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: 800, y: 150)))
    }

    @Test func placesTemplatesInsideAnOffsetFrame() {
        let template = AnnotationTemplate(name: "D", annotations: [Annotation(shape: .step(CGPoint(x: 50, y: 50), 1), color: .red, lineWidth: 2)], frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let placed = template.annotations(fittedTo: CGRect(x: 200, y: 100, width: 100, height: 100))
        #expect(placed[0].shape == .step(CGPoint(x: 250, y: 150), 1))
        let mapping = TemplateMapping(source: CGRect(x: 10, y: 20, width: 100, height: 50), target: TemplateMapping.unit)
        #expect(isClose(mapping.point(CGPoint(x: 60, y: 45)), CGPoint(x: 0.5, y: 0.5)))
    }
}

@MainActor
struct TemplateStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ishare-template-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func savesRenamesAndDeletesTemplatesOnDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TemplateStore(directory: directory)
        #expect(store.templates.isEmpty)
        let saved = try store.save(name: "  Bug report  ", annotations: [rectangle(CGRect(x: 10, y: 10, width: 20, height: 20))], frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(saved.name == "Bug report")
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: saved.id).path(percentEncoded: false)))

        let reloaded = TemplateStore(directory: directory)
        #expect(reloaded.templates.map(\.name) == ["Bug report"])
        try reloaded.rename(saved.id, to: "Release notes")
        #expect(TemplateStore(directory: directory).templates.map(\.name) == ["Release notes"])

        try reloaded.delete(saved.id)
        #expect(reloaded.templates.isEmpty)
        #expect(TemplateStore(directory: directory).templates.isEmpty)
    }

    @Test func fallsBackToAGeneratedNameAndRendersAPreview() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TemplateStore(directory: directory)
        var filled = rectangle(CGRect(x: 0, y: 0, width: 200, height: 100))
        filled.filled = true
        let first = try store.save(name: "", annotations: [filled], frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let second = try store.save(name: " ", annotations: [rectangle(CGRect(x: 0, y: 0, width: 50, height: 50))], frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        #expect(first.name != second.name)
        let size = TemplatePreview.size(for: first, fitting: TemplateStore.previewSize)
        #expect(size.width <= TemplateStore.previewSize.width && size.height <= TemplateStore.previewSize.height)
        #expect(abs(size.width / size.height - 2) < 0.1)
        let preview = try #require(TemplatePreview.cgImage(for: first, size: size, pixelScale: 1))
        #expect(pixel(preview, x: 2, y: Int(size.height) / 4)[0] > 200)
        #expect(pixel(preview, x: Int(size.width) - 2, y: Int(size.height) - 2)[0] < 200)
    }
}

@MainActor
struct EditorTemplateInsertionTests {
    @Test func insertsATemplateAsOneSelectedUndoStep() {
        let document = EditorDocument(image: makeImage(width: 800, height: 600), fileURL: nil)
        document.add(Annotation(shape: .step(CGPoint(x: 10, y: 10), 1), color: .red, lineWidth: 2))
        let template = AnnotationTemplate(
            name: "Steps",
            annotations: [
                Annotation(shape: .step(CGPoint(x: 10, y: 10), 1), color: .red, lineWidth: 2),
                Annotation(shape: .step(CGPoint(x: 20, y: 10), 2), color: .red, lineWidth: 2),
                rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
            ],
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        document.tool = .arrow
        document.insert(template)
        #expect(document.annotations.count == 4)
        #expect(document.tool == .select)
        let inserted = Array(document.annotations.suffix(3))
        #expect(document.selectedIDs == Set(inserted.map(\.id)))
        #expect(inserted[0].shape == .step(CGPoint(x: 80, y: 60), 2))
        #expect(inserted[1].shape == .step(CGPoint(x: 160, y: 60), 3))
        document.move(document.selectedIDs, by: CGVector(dx: 5, dy: 5))
        #expect(document.annotations[1].shape == .step(CGPoint(x: 85, y: 65), 2))
        document.undo()
        document.undo()
        #expect(document.annotations.count == 1)
    }

    @Test func templatesUseTheSelectionOrEverythingVisibleWithinTheCrop() {
        let document = EditorDocument(image: makeImage(), fileURL: nil)
        let first = rectangle(CGRect(x: 10, y: 10, width: 10, height: 10))
        var hidden = rectangle(CGRect(x: 30, y: 30, width: 10, height: 10))
        hidden.hidden = true
        let third = rectangle(CGRect(x: 50, y: 50, width: 10, height: 10))
        document.replaceAnnotations(with: [first, hidden, third])
        #expect(document.templateSource.map(\.id) == [first.id, third.id])
        document.selectedID = third.id
        #expect(document.templateSource.map(\.id) == [third.id])
        document.applyCrop(CGRect(x: 20, y: 20, width: 100, height: 100))
        #expect(document.templateFrame == CGRect(x: 20, y: 20, width: 100, height: 100))
    }
}

@MainActor
struct EditorLayerTests {
    @Test func listsLayersTopMostFirstWithLabels() {
        let document = EditorDocument(image: makeImage(), fileURL: nil)
        let a = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = Annotation(shape: .text(.zero, "Release blocker\nsecond line"), color: .red, lineWidth: 2)
        let c = rectangle(CGRect(x: 20, y: 0, width: 10, height: 10))
        let d = Annotation(shape: .stamp(CGRect(x: 0, y: 0, width: 40, height: 40), .emoji("🚀")), color: .red, lineWidth: 2)
        let e = Annotation(shape: .curvedArrow(.zero, CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 0)), color: .red, lineWidth: 2)
        let f = Annotation(shape: .step(.zero, 7), color: .red, lineWidth: 2)
        document.replaceAnnotations(with: [a, b, c, d, e, f])
        #expect(document.layers.map(\.id) == [f.id, e.id, d.id, c.id, b.id, a.id])
        #expect(document.label(for: a) == "\(EditorTool.rectangle.title.localized()) 1")
        #expect(document.label(for: c) == "\(EditorTool.rectangle.title.localized()) 2")
        #expect(document.label(for: b) == "Release blocker")
        #expect(document.label(for: d) == "🚀")
        #expect(document.label(for: e) == "\(EditorTool.arrow.title.localized()) 1")
        #expect(document.label(for: f) == "\(EditorTool.step.title.localized()) 7")
        #expect(e.layerSymbol == ArrowPath.curved.symbol)
        #expect(a.layerSymbol == EditorTool.rectangle.symbol)
        #expect(LayerLabel.excerpt(String(repeating: "x", count: 80))?.count == LayerLabel.maximumLength)
    }

    @Test func reorderingChangesZOrderAndIsUndoable() throws {
        let document = EditorDocument(image: makeImage(gray: 1), fileURL: nil)
        var red = rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), color: .red)
        red.filled = true
        var blue = rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), color: .blue)
        blue.filled = true
        document.add(red)
        document.add(blue)
        #expect(pixel(try #require(document.render()), x: 50, y: 50)[2] > 200)
        document.moveLayers(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(document.annotations.map(\.id) == [blue.id, red.id])
        #expect(document.layers.first?.id == red.id)
        let reordered = try #require(document.render())
        #expect(pixel(reordered, x: 50, y: 50)[0] > 200)
        #expect(pixel(reordered, x: 50, y: 50)[2] < 100)
        document.undo()
        #expect(document.annotations.map(\.id) == [red.id, blue.id])
        document.redo()
        #expect(document.annotations.map(\.id) == [blue.id, red.id])
    }

    @Test func lockedAnnotationsCannotBePickedMovedOrDeletedFromTheCanvas() {
        let document = EditorDocument(image: makeImage(), fileURL: nil)
        let annotation = rectangle(CGRect(x: 10, y: 10, width: 50, height: 50))
        document.add(annotation)
        document.setLocked(true, for: [annotation.id])
        #expect(document.annotations[0].locked)
        #expect(document.annotation(at: CGPoint(x: 10, y: 30)) == nil)
        document.move(annotation.id, by: CGVector(dx: 30, dy: 0))
        #expect(document.annotations[0].shape == annotation.shape)
        document.selectedID = annotation.id
        document.deleteSelection()
        #expect(document.annotations.count == 1)
        document.undo()
        #expect(!document.annotations[0].locked)
        #expect(document.annotation(at: CGPoint(x: 10, y: 30))?.id == annotation.id)
        document.delete([annotation.id])
        #expect(document.annotations.isEmpty)
    }

    @Test func hiddenAnnotationsAreExcludedFromHitTestingAndRendering() throws {
        let document = EditorDocument(image: makeImage(gray: 1), fileURL: nil)
        var fill = rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), color: .black)
        fill.filled = true
        let blur = Annotation(shape: .pixelate(CGRect(x: 200, y: 0, width: 100, height: 100)), color: .red, lineWidth: 2)
        document.add(fill)
        document.add(blur)
        document.selectedIDs = [fill.id, blur.id]
        #expect(pixel(try #require(document.render()), x: 50, y: 50)[0] < 30)
        document.setHidden(true, for: [fill.id])
        #expect(document.selectedIDs == [blur.id])
        #expect(document.annotation(at: CGPoint(x: 50, y: 50)) == nil)
        let rendered = try #require(document.render())
        #expect(pixel(rendered, x: 50, y: 50) == [255, 255, 255, 255])
        #expect(document.annotations.count == 2)
        document.setHidden(true, for: [blur.id])
        #expect(maximumDifference(document.effectedBase, document.base) == 0)
        document.undo()
        document.undo()
        #expect(pixel(try #require(document.render()), x: 50, y: 50)[0] < 30)
    }

    @Test func groupSelectionMovesTogetherAndSkipsLockedMembers() {
        let document = EditorDocument(image: makeImage(), fileURL: nil)
        let a = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))
        var b = rectangle(CGRect(x: 50, y: 50, width: 10, height: 10))
        b.locked = true
        let c = rectangle(CGRect(x: 100, y: 0, width: 10, height: 10))
        document.replaceAnnotations(with: [a, b, c])
        document.selectedIDs = [a.id, b.id, c.id]
        #expect(document.selectedID == nil)
        #expect(document.selectionBounds == CGRect(x: 0, y: 0, width: 110, height: 60))
        document.move(document.selectedIDs, by: CGVector(dx: 10, dy: 0))
        #expect(document.annotations[0].shape == .rectangle(CGRect(x: 10, y: 0, width: 10, height: 10)))
        #expect(document.annotations[1].shape == b.shape)
        #expect(document.annotations[2].shape == .rectangle(CGRect(x: 110, y: 0, width: 10, height: 10)))
        document.toggleSelection(a.id)
        #expect(document.selectedIDs == [b.id, c.id])
        document.updateSelection { $0.color = .green }
        #expect(document.annotations[2].color == .green)
        #expect(document.annotations[0].color == .red)
    }
}

@MainActor
struct ZoomAnchorTests {
    private let container = CGSize(width: 800, height: 600)

    private func transform() -> CanvasTransform {
        .make(visibleRect: CGRect(x: 0, y: 0, width: 3000, height: 2000), container: container, scale: 0.5, center: CGPoint(x: 1500, y: 1000))
    }

    @Test func prefersThePointerOverTheCanvas() {
        let anchor = transform().zoomAnchor(pointer: CGPoint(x: 120, y: 80), selection: CGRect(x: 10, y: 10, width: 20, height: 20), in: container)
        #expect(anchor == CGPoint(x: 120, y: 80))
    }

    @Test func fallsBackToTheSelectionCenterThenTheViewCenter() {
        let transform = transform()
        let selection = CGRect(x: 1400, y: 900, width: 100, height: 100)
        let outside = transform.zoomAnchor(pointer: CGPoint(x: 900, y: 100), selection: selection, in: container)
        #expect(isClose(outside, transform.toView(CGPoint(x: 1450, y: 950))))
        let noPointer = transform.zoomAnchor(pointer: nil, selection: selection, in: container)
        #expect(isClose(noPointer, transform.toView(CGPoint(x: 1450, y: 950))))
        #expect(transform.zoomAnchor(pointer: nil, selection: nil, in: container) == CGPoint(x: 400, y: 300))
    }

    @Test func clampsAnOffscreenSelectionIntoTheView() {
        let anchor = transform().zoomAnchor(pointer: nil, selection: CGRect(x: 2900, y: 1900, width: 50, height: 50), in: container)
        #expect(anchor == CGPoint(x: 800, y: 600))
    }

    @Test func zoomButtonsKeepThePointerAnchoredInImageSpace() {
        let viewport = EditorViewport(visibleRect: CGRect(x: 0, y: 0, width: 3000, height: 2000), backingScale: 1)
        viewport.update(containerSize: container)
        viewport.setZoom(0.5)
        let pointer = CGPoint(x: 200, y: 150)
        viewport.pointerLocation = pointer
        let pinned = viewport.transform.toImage(pointer)
        viewport.zoomIn()
        #expect(viewport.effectiveZoom > 0.5)
        #expect(isClose(viewport.transform.toView(pinned), pointer, tolerance: 0.01))
        viewport.zoomOut()
        #expect(isClose(viewport.transform.toView(pinned), pointer, tolerance: 0.01))
    }

    @Test func zoomButtonsKeepTheSelectionCenterInPlace() {
        let viewport = EditorViewport(visibleRect: CGRect(x: 0, y: 0, width: 3000, height: 2000), backingScale: 1)
        viewport.update(containerSize: container)
        viewport.setZoom(0.5)
        let selection = CGRect(x: 1000, y: 800, width: 200, height: 100)
        let center = CGPoint(x: selection.midX, y: selection.midY)
        let before = viewport.transform.toView(center)
        viewport.zoomIn(selection: selection)
        #expect(isClose(viewport.transform.toView(center), before, tolerance: 0.01))
        viewport.fit()
        #expect(viewport.isFit)
        viewport.actualSize()
        #expect(viewport.effectiveZoom == 1)
    }

    @Test func zoomButtonsUseTheViewCenterWithoutPointerOrSelection() {
        let viewport = EditorViewport(visibleRect: CGRect(x: 0, y: 0, width: 3000, height: 2000), backingScale: 1)
        viewport.update(containerSize: container)
        viewport.setZoom(0.5)
        let centerBefore = viewport.transform.center(in: container)
        viewport.zoomIn()
        #expect(isClose(viewport.transform.center(in: container), centerBefore, tolerance: 0.01))
    }
}

@MainActor
struct LiveEffectPreviewTests {
    @Test func throttlesToTheFrameInterval() {
        var throttle = FrameThrottle(interval: 1.0 / 30)
        #expect(throttle.decision(at: 10) == .renderNow)
        throttle.didRender(at: 10)
        guard case let .wait(delay) = throttle.decision(at: 10.01) else {
            Issue.record("Expected to wait")
            return
        }
        #expect(abs(delay - (1.0 / 30 - 0.01)) < 0.0001)
        #expect(throttle.decision(at: 10.034) == .renderNow)
        throttle.reset()
        #expect(throttle.decision(at: 10.001) == .renderNow)
    }

    @Test func downscalesTheCachedSourceForLargeImagesAndLowZoom() {
        #expect(LiveEffectPreview.sourceScale(for: CGSize(width: 800, height: 600), zoom: 2) == 1)
        #expect(LiveEffectPreview.sourceScale(for: CGSize(width: 3200, height: 1000), zoom: 2) == 0.5)
        #expect(LiveEffectPreview.sourceScale(for: CGSize(width: 800, height: 600), zoom: 0.25) == 0.25)
        #expect(LiveEffectPreview.sourceScale(for: CGSize(width: 800, height: 600), zoom: 0.01) == LiveEffectPreview.minimumSourceScale)
    }

    @Test func rendersAtMostOneFramePerIntervalAndKeepsTheLatestPending() throws {
        let clock = ManualClock()
        let preview = LiveEffectPreview(clock: { clock.now })
        let base = stripedImage()
        let blur = Annotation(shape: .blur(CGRect(x: 10, y: 10, width: 100, height: 100)), color: .red, lineWidth: 2)
        preview.begin(for: blur, background: base, zoom: 1)
        #expect(preview.isActive)
        #expect(preview.renderCount == 1)
        let firstTile = try #require(preview.tile)
        #expect(isClose(firstTile.rect, CGRect(x: 10, y: 10, width: 100, height: 100)))

        clock.now += 0.01
        preview.update(blur.resized(to: CGRect(x: 10, y: 10, width: 150, height: 100)))
        #expect(preview.renderCount == 1)
        #expect(preview.hasPendingFrame)
        clock.now += 0.005
        preview.update(blur.resized(to: CGRect(x: 10, y: 10, width: 180, height: 120)))
        #expect(preview.renderCount == 1)

        clock.now += 0.03
        preview.flush()
        #expect(preview.renderCount == 2)
        #expect(!preview.hasPendingFrame)
        #expect(isClose(try #require(preview.tile).rect, CGRect(x: 10, y: 10, width: 180, height: 120)))

        clock.now += 0.04
        preview.update(blur.resized(to: CGRect(x: 10, y: 10, width: 60, height: 60)))
        #expect(preview.renderCount == 3)

        preview.end()
        #expect(!preview.isActive)
        #expect(preview.tile == nil)
    }

    @Test(arguments: [
        Annotation.Shape.blur(CGRect(x: 40, y: 30, width: 120, height: 90)),
        .pixelate(CGRect(x: 40, y: 30, width: 120, height: 90)),
        .eraser(CGRect(x: 40, y: 30, width: 120, height: 90)),
        .pixelate(CGRect(x: -20, y: 250, width: 120, height: 90)),
    ])
    func fullScaleTilesMatchTheFullQualityEffect(shape: Annotation.Shape) throws {
        let base = stripedImage()
        let annotation = Annotation(shape: shape, color: .red, lineWidth: 2)
        let tile = try #require(LiveEffectPreview.tile(for: annotation, source: base, scale: 1))
        let full = AnnotationRenderer.applyingEffects([annotation], to: base)
        let expected = try #require(full.cropping(to: tile.rect))
        #expect(maximumDifference(tile.image, expected) <= 2)
    }

    @Test func downscaledTilesCoverTheRegionAndApproximateTheEffect() throws {
        let base = stripedImage(width: 800, height: 600)
        let annotation = Annotation(shape: .blur(CGRect(x: 100, y: 100, width: 300, height: 200)), color: .red, lineWidth: 2)
        let preview = LiveEffectPreview()
        preview.begin(for: annotation, background: base, zoom: 0.5)
        #expect(abs(preview.sourceScale - 0.5) < 0.01)
        let tile = try #require(preview.tile)
        #expect(tile.image.width <= 152)
        #expect(isClose(tile.rect, CGRect(x: 100, y: 100, width: 300, height: 200), tolerance: 4))
    }

    @Test func committingAfterALiveDragMatchesTheFullQualityPath() throws {
        let base = stripedImage()
        let document = EditorDocument(image: base, fileURL: nil)
        let other = Annotation(shape: .pixelate(CGRect(x: 250, y: 150, width: 100, height: 100)), color: .red, lineWidth: 2)
        let original = Annotation(shape: .blur(CGRect(x: 20, y: 20, width: 80, height: 80)), color: .red, lineWidth: 2)
        document.add(other)
        document.add(original)
        let clock = ManualClock()
        let preview = LiveEffectPreview(clock: { clock.now })
        let background = document.effectedBase(excluding: original.id)
        #expect(maximumDifference(background, AnnotationRenderer.applyingEffects([other], to: base)) == 0)
        preview.begin(for: original, background: background, zoom: 1)
        var live = original
        for step in 1 ... 6 {
            clock.now += 0.012
            live = original.editing(.resize(.bottomRight), to: CGPoint(x: 100 + CGFloat(step) * 15, y: 100 + CGFloat(step) * 10))
            preview.update(live)
        }
        #expect(preview.renderCount < 6)
        document.replace(live)
        preview.end()

        let expectedBase = AnnotationRenderer.applyingEffects([other, live], to: base)
        #expect(maximumDifference(document.effectedBase, expectedBase) == 0)
        let rendered = try #require(document.render())
        let expectedRender = try #require(AnnotationRenderer.render(base: base, annotations: [other, live], crop: nil))
        #expect(maximumDifference(rendered, expectedRender) == 0)
        document.undo()
        #expect(maximumDifference(document.effectedBase, AnnotationRenderer.applyingEffects([other, original], to: base)) == 0)
    }
}
