import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import ishare

private func canvasImage(width: Int = 400, height: Int = 300) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@MainActor
struct EditorStyleTests {
    let pasteboard = AnnotationStylePasteboard(pasteboard: NSPasteboard.withUniqueName())

    var dashedArrow: Annotation {
        var arrow = Annotation(shape: .arrow(.zero, CGPoint(x: 100, y: 0)), color: .blue, lineWidth: 9, fontSize: 50)
        arrow.arrowHead = .open
        arrow.doubleHeaded = true
        arrow.dashed = true
        return arrow
    }

    func document(with annotations: [Annotation], styles: ToolStyleStore = ToolStyleStore(styles: [:])) -> EditorDocument {
        let document = EditorDocument(image: canvasImage(), fileURL: nil, toolStyles: styles)
        annotations.forEach { document.add($0) }
        return document
    }

    @Test func capturesOnlyThePropertiesThatApply() {
        let style = AnnotationStyle(of: dashedArrow)
        #expect(style.color == .blue)
        #expect(style.lineWidth == 9)
        #expect(style.arrowHead == .open)
        #expect(style.doubleHeaded == true)
        #expect(style.dashed == true)
        #expect(style.fontSize == nil)
        #expect(style.filled == nil)
        let text = Annotation(shape: .text(.zero, "Hi"), color: .green, lineWidth: 3, fontSize: 40, textBackground: true)
        let textStyle = AnnotationStyle(of: text)
        #expect(textStyle.fontSize == 40)
        #expect(textStyle.textBackground == true)
        #expect(textStyle.lineWidth == nil)
        #expect(AnnotationStyle(of: Annotation(shape: .blur(.zero), color: .red, lineWidth: 2)).isEmpty)
    }

    @Test func appliesAcrossTypesSkippingMismatchedProperties() {
        let style = AnnotationStyle(of: dashedArrow)
        let rectangle = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, lineWidth: 2, fontSize: 20, filled: true)
        let styledRectangle = rectangle.applying(style)
        #expect(styledRectangle.color == .blue)
        #expect(styledRectangle.lineWidth == 9)
        #expect(styledRectangle.dashed)
        #expect(styledRectangle.filled)
        #expect(styledRectangle.arrowHead == rectangle.arrowHead)
        #expect(styledRectangle.fontSize == 20)
        let text = Annotation(shape: .text(.zero, "Hi"), color: .red, lineWidth: 2, fontSize: 20)
        let styledText = text.applying(style)
        #expect(styledText.color == .blue)
        #expect(styledText.lineWidth == 2)
        #expect(styledText.fontSize == 20)
        let blur = Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, lineWidth: 2)
        #expect(blur.applying(style) == blur)
        var spotlight = Annotation(shape: .spotlight(.zero), color: .red, lineWidth: 2)
        spotlight.dimAmount = 0.2
        let other = Annotation(shape: .spotlight(.zero), color: .red, lineWidth: 2)
        #expect(other.applying(AnnotationStyle(of: spotlight)).dimAmount == 0.2)
    }

    @Test func copiesAndPastesThroughThePrivatePasteboard() {
        let arrow = dashedArrow
        let line = Annotation(shape: .line(.zero, CGPoint(x: 10, y: 10)), color: .red, lineWidth: 2)
        let step = Annotation(shape: .step(CGPoint(x: 50, y: 50), 1), color: .red, lineWidth: 2, fontSize: 30)
        let source = document(with: [arrow])
        source.selectedID = arrow.id
        #expect(source.copyStyle(to: pasteboard))
        #expect(pasteboard.read() == AnnotationStyle(of: arrow))
        #expect(pasteboard.pasteboard.string(forType: .string) == nil)
        let target = document(with: [line, step])
        #expect(!target.canPasteStyle(from: pasteboard))
        target.selectedIDs = [line.id, step.id]
        #expect(target.canPasteStyle(from: pasteboard))
        #expect(target.pasteStyle(from: pasteboard))
        let styledLine = target.annotations[0]
        let styledStep = target.annotations[1]
        #expect(styledLine.color == .blue && styledLine.lineWidth == 9 && styledLine.dashed)
        #expect(styledStep.color == .blue && styledStep.fontSize == 30)
        target.undo()
        #expect(target.annotations == [line, step])
    }

    @Test func pastingSkipsLockedAnnotations() {
        var locked = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, lineWidth: 2)
        locked.locked = true
        let target = document(with: [locked])
        target.selectedID = locked.id
        pasteboard.write(AnnotationStyle(color: .green))
        #expect(!target.pasteStyle(from: pasteboard))
        #expect(target.annotations.first?.color == .red)
    }

    @Test func emptyPasteboardsPasteNothing() {
        let target = document(with: [dashedArrow])
        target.selectedIDs = Set(target.annotations.map(\.id))
        #expect(!target.pasteStyle(from: pasteboard))
        #expect(!target.canPasteStyle(from: pasteboard))
    }

    @Test func usesAnObjectsStyleAsTheToolDefault() throws {
        let styles = ToolStyleStore(styles: [:])
        var rectangle = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .purple, lineWidth: 13, filled: true)
        rectangle.dashed = false
        let document = document(with: [rectangle], styles: styles)
        document.useAsDefault(rectangle)
        #expect(document.color == .red)
        document.select(tool: .rectangle)
        #expect(document.color == .purple)
        #expect(document.lineWidth == 13)
        #expect(document.filled)
        let drawn = try #require(document.makeAnnotation(tool: .rectangle, from: .zero, to: CGPoint(x: 40, y: 40), points: []))
        #expect(drawn.color == .purple && drawn.lineWidth == 13 && drawn.filled)
        let next = EditorDocument(image: canvasImage(), fileURL: nil, toolStyles: styles)
        next.select(tool: .rectangle)
        #expect(next.color == .purple)
        #expect(EditorDocument.useAsDefaultTitle(for: rectangle).contains("Rectangle".localized()))
    }

    @Test func storedToolStylesSurviveCoding() throws {
        let styles = ["arrow": AnnotationStyle(of: dashedArrow)]
        let decoded = try JSONDecoder().decode([String: AnnotationStyle].self, from: JSONEncoder().encode(styles))
        #expect(decoded == styles)
        #expect(SettingsTransfer.preferenceNames.contains("editorToolStyles"))
    }

    @Test func contextMenuOffersTheStyleActions() {
        let arrow = dashedArrow
        let document = document(with: [arrow])
        document.selectedID = arrow.id
        let menu = AnnotationContextMenu.make(for: document, pasteboard: pasteboard)
        #expect(menu.items.map(\.title).prefix(2) == ["Copy Style".localized(), "Paste Style".localized()])
        #expect(menu.items[0].isEnabled)
        #expect(!menu.items[1].isEnabled)
        #expect(menu.items[0].keyEquivalentModifierMask == [.command, .option])
        #expect(menu.items.last?.title == EditorDocument.useAsDefaultTitle(for: arrow))
    }
}
