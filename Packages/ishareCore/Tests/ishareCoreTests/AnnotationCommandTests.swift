import CoreGraphics
import Testing
@testable import ishareCore

struct AnnotationCommandTests {
    @Test func readsTheKindAndTarget() {
        #expect(AnnotationCommand.parse("arrow to the Save button") == ParsedAnnotationCommand(kind: .arrow, target: "save"))
        #expect(AnnotationCommand.parse("draw a box around Export PDF") == ParsedAnnotationCommand(kind: .rectangle, target: "export pdf"))
        #expect(AnnotationCommand.parse("blur the email address") == ParsedAnnotationCommand(kind: .blur, target: "email address"))
        #expect(AnnotationCommand.parse("circle “Sign in”") == ParsedAnnotationCommand(kind: .ellipse, target: "sign in"))
        #expect(AnnotationCommand.parse("make it pretty") == nil)
        #expect(AnnotationCommand.parse("arrow") == nil)
    }

    @Test func picksTheClosestLabel() {
        let labels = ["Cancel", "Save As…", "Save", "Saved searches"]
        #expect(AnnotationCommand.bestMatch(for: "save", in: labels) == 2)
        #expect(AnnotationCommand.bestMatch(for: "cancel", in: labels) == 0)
        #expect(AnnotationCommand.bestMatch(for: "delete", in: labels) == nil)
    }

    @Test func readsTheModelReply() {
        #expect(AnnotationCommand.parseModelReply("arrow | 3", labelCount: 5)! == (.arrow, 3))
        #expect(AnnotationCommand.parseModelReply("blur|9", labelCount: 5) == nil)
        #expect(AnnotationCommand.parseModelReply("nope", labelCount: 5) == nil)
    }

    @Test func pointsArrowsInFromTheMiddleOfTheImage() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let arrow = AnnotationCommand.arrow(to: CGRect(x: 800, y: 600, width: 100, height: 40), in: bounds)
        #expect(arrow.end == CGPoint(x: 796, y: 596))
        #expect(arrow.start.x < arrow.end.x && arrow.start.y < arrow.end.y)
    }
}
