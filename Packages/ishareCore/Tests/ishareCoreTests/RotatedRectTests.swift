import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct RotatedRectTests {
    let quarterTurn = RotatedRect(rect: CGRect(x: 0, y: 40, width: 100, height: 20), angle: .pi / 2)

    func close(_ first: CGPoint, _ second: CGPoint, _ tolerance: CGFloat = 0.001) -> Bool {
        abs(first.x - second.x) <= tolerance && abs(first.y - second.y) <= tolerance
    }

    @Test func normalizesAnglesIntoOneTurn() {
        #expect(abs(RotatedRect.normalized(3 * .pi) - .pi) < 1e-9)
        #expect(abs(RotatedRect.normalized(-.pi * 1.5) - .pi / 2) < 1e-9)
        #expect(RotatedRect.normalized(2 * .pi) == 0)
    }

    @Test func rotatesAroundTheCenter() {
        #expect(close(quarterTurn.toWorld(CGPoint(x: 100, y: 50)), CGPoint(x: 50, y: 100)))
        #expect(close(quarterTurn.toLocal(CGPoint(x: 50, y: 100)), CGPoint(x: 100, y: 50)))
        #expect(close(quarterTurn.corners[0], CGPoint(x: 60, y: 0)))
    }

    @Test func boundingBoxCoversTheRotatedCorners() {
        let box = quarterTurn.boundingBox
        #expect(abs(box.minX - 40) < 0.001)
        #expect(abs(box.width - 20) < 0.001)
        #expect(abs(box.height - 100) < 0.001)
        let flat = RotatedRect(rect: CGRect(x: 1, y: 2, width: 3, height: 4), angle: 0)
        #expect(flat.boundingBox == CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    @Test func hitTestsInTheRotatedFrame() {
        #expect(quarterTurn.contains(CGPoint(x: 50, y: 5)))
        #expect(!quarterTurn.contains(CGPoint(x: 5, y: 50)))
        #expect(quarterTurn.contains(CGPoint(x: 38, y: 50), tolerance: 3))
        let diamond = RotatedRect(rect: CGRect(x: 0, y: 0, width: 100, height: 100), angle: .pi / 4)
        #expect(!diamond.contains(CGPoint(x: 2, y: 2)))
        #expect(diamond.contains(CGPoint(x: 50, y: -15)))
    }

    @Test func hitTestsRotatedEllipses() {
        let ellipse = RotatedRect(rect: CGRect(x: 0, y: 40, width: 100, height: 20), angle: .pi / 2)
        #expect(ellipse.ellipseContains(CGPoint(x: 50, y: 2)))
        #expect(!ellipse.ellipseContains(CGPoint(x: 2, y: 50)))
    }

    @Test func resizingInTheLocalFrameKeepsTheOppositeEdgeInPlace() {
        let resized = quarterTurn.replacingLocalRect(CGRect(x: 0, y: 40, width: 150, height: 20))
        #expect(close(resized.toWorld(CGPoint(x: resized.rect.minX, y: resized.rect.midY)), quarterTurn.toWorld(CGPoint(x: 0, y: 50))))
        #expect(abs(resized.rect.width - 150) < 0.001)
        #expect(resized.angle == quarterTurn.angle)
    }

    @Test func movesItsCenter() {
        let moved = quarterTurn.movingCenter(to: CGPoint(x: 0, y: 0))
        #expect(moved.center == .zero)
        #expect(moved.rect.size == quarterTurn.rect.size)
    }
}
