import Foundation
import Testing
@testable import ishare

struct GuideScenesTests {
    @Test func everySceneHasAShortClipWithCopy() {
        for scene in GuideScene.allCases {
            #expect(scene.frameCount > 30)
            #expect(scene.duration <= 8)
            #expect(!scene.title.isEmpty && !scene.subtitle.isEmpty)
        }
        #expect(GuideScene.allCases.map(\.rawValue) == ["capture", "editor", "region", "shelf"])
        #expect(GuideScene.capture.frameCount == 98)
        #expect(GuideScene.editor.frameCount == 90)
    }

    @Test func timelineProgressIsClampedAndEased() {
        #expect(GuideTimeline.progress(0, from: 1, to: 2) == 0)
        #expect(GuideTimeline.progress(1.5, from: 1, to: 2) == 0.5)
        #expect(GuideTimeline.progress(3, from: 1, to: 2) == 1)
        #expect(GuideTimeline.progress(2, from: 2, to: 2) == 1)
        #expect(GuideTimeline.eased(0) == 0)
        #expect(GuideTimeline.eased(1) == 1)
        #expect(GuideTimeline.eased(0.5) == 0.5)
        #expect(GuideTimeline.eased(0.25) < 0.25)
        #expect(GuideTimeline.interpolate(CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 30), 0.5) == CGPoint(x: 5, y: 20))
    }

    @MainActor @Test func clockAdvancesFrameByFrameUpToTheLastFrame() {
        let clock = GuideClock(scene: .editor)
        #expect(clock.frame == 0)
        for _ in 0 ..< 200 {
            clock.advance()
        }
        #expect(clock.frame == GuideScene.editor.frameCount)
        #expect(clock.time == GuideScene.editor.duration)
        #expect(GuideMode.scene == nil)
    }
}
