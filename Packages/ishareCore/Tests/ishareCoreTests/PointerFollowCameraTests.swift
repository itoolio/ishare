import CoreGraphics
import Testing
@testable import ishareCore

struct PointerFollowCameraTests {
    let display = CGSize(width: 2000, height: 1200)

    @Test func startsCenteredOnThePointerWithinTheDisplay() {
        let camera = PointerFollowCamera(display: display, size: CGSize(width: 800, height: 400), centeredAt: CGPoint(x: 1000, y: 600))
        #expect(camera.rect == CGRect(x: 600, y: 400, width: 800, height: 400))
        let corner = PointerFollowCamera(display: display, size: CGSize(width: 800, height: 400), centeredAt: CGPoint(x: 10, y: 10))
        #expect(corner.origin == .zero)
    }

    @Test func staysStillWhileThePointerIsInTheDeadZone() {
        var camera = PointerFollowCamera(display: display, size: CGSize(width: 800, height: 400), centeredAt: CGPoint(x: 1000, y: 600))
        let moved = camera.step(toward: CGPoint(x: 1100, y: 640), elapsed: 1)
        #expect(!moved)
        #expect(camera.origin == CGPoint(x: 600, y: 400))
    }

    @Test func followsUntilThePointerIsBackAtTheDeadZoneEdge() {
        var camera = PointerFollowCamera(display: display, size: CGSize(width: 800, height: 400), centeredAt: CGPoint(x: 1000, y: 600), timeConstant: 0)
        let moved = camera.step(toward: CGPoint(x: 1500, y: 600), elapsed: 0.1)
        #expect(moved)
        #expect(camera.origin == CGPoint(x: 980, y: 400))
    }

    @Test func easesTowardsTheTarget() {
        var camera = PointerFollowCamera(display: display, size: CGSize(width: 800, height: 400), centeredAt: CGPoint(x: 1000, y: 600))
        camera.step(toward: CGPoint(x: 1500, y: 600), elapsed: 0.05)
        #expect(camera.origin.x > 600 && camera.origin.x < 980)
    }

    @Test func neverLeavesTheDisplay() {
        var camera = PointerFollowCamera(display: display, size: CGSize(width: 800, height: 400), centeredAt: CGPoint(x: 1000, y: 600), timeConstant: 0)
        camera.step(toward: CGPoint(x: 5000, y: 5000), elapsed: 1)
        #expect(camera.rect.maxX == 2000 && camera.rect.maxY == 1200)
    }

    @Test func sizesFitSmallDisplays() {
        #expect(FollowPointerSize.hd1080.pointSize(fitting: CGSize(width: 1440, height: 900)) == CGSize(width: 1440, height: 810))
        #expect(FollowPointerSize.hd720.pointSize(fitting: display) == CGSize(width: 1280, height: 720))
    }
}
