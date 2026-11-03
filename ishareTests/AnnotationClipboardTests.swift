import AppKit
import Testing
@testable import ishare

@MainActor
struct AnnotationClipboardTests {
    private func clipboard() -> AnnotationClipboard {
        AnnotationClipboard(pasteboard: NSPasteboard(name: NSPasteboard.Name("dev.adrian.ishare.tests.annotations.\(UUID().uuidString)")))
    }

    @Test func copiesAnnotationsBetweenDocumentsWithNewIdentities() {
        let board = clipboard()
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        let source = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), color: red, lineWidth: 3)
        board.write([source])
        let pasted = AnnotationClipboard.pasted(board.read(), into: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(pasted.count == 1)
        #expect(pasted[0].id != source.id)
        #expect(pasted[0].color == red)
        #expect(pasted[0].bounds.origin == CGPoint(x: 22, y: 22))
    }

    @Test func dropsAnnotationsThatFallOutsideTheTargetImage() {
        let board = clipboard()
        board.write([Annotation(shape: .rectangle(CGRect(x: 900, y: 900, width: 20, height: 20)), color: RGBAColor(red: 0, green: 0, blue: 0), lineWidth: 2)])
        #expect(AnnotationClipboard.pasted(board.read(), into: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    }
}
