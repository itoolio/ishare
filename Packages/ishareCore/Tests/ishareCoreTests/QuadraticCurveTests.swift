import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct QuadraticCurveTests {
    let arch = QuadraticCurve(start: CGPoint(x: 0, y: 100), control: CGPoint(x: 50, y: 0), end: CGPoint(x: 100, y: 100))

    func close(_ first: CGFloat, _ second: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool {
        abs(first - second) <= tolerance
    }

    @Test func passesThroughTheDraggedMidpoint() {
        let curve = QuadraticCurve(start: CGPoint(x: 0, y: 0), through: CGPoint(x: 50, y: 40), end: CGPoint(x: 100, y: 0))
        #expect(close(curve.midpoint.x, 50))
        #expect(close(curve.midpoint.y, 40))
        #expect(curve.control == CGPoint(x: 50, y: 80))
    }

    @Test func endTangentFollowsTheLastControlSegment() {
        #expect(close(arch.endTangent.dx, 1 / 5.squareRoot()))
        #expect(close(arch.endTangent.dy, 2 / 5.squareRoot()))
        #expect(close(arch.endTangentAngle, atan2(100, 50)))
        #expect(close(arch.startTangentAngle, atan2(200, -100)))
    }

    @Test func degenerateControlFallsBackToTheChord() {
        let curve = QuadraticCurve(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 100, y: 0), end: CGPoint(x: 100, y: 0))
        #expect(close(curve.endTangentAngle, 0))
        let point = QuadraticCurve(start: .zero, control: .zero, end: .zero)
        #expect(point.endTangent == CGVector(dx: 1, dy: 0))
    }

    @Test func boundingBoxIncludesTheApex() {
        let box = arch.boundingBox
        #expect(close(box.minX, 0))
        #expect(close(box.maxX, 100))
        #expect(close(box.minY, 50))
        #expect(close(box.maxY, 100))
        let straight = QuadraticCurve(start: CGPoint(x: 10, y: 10), control: CGPoint(x: 20, y: 20), end: CGPoint(x: 30, y: 30))
        #expect(straight.boundingBox == CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    @Test func measuresTheDistanceToTheCurveNotTheChord() {
        #expect(close(arch.distance(to: CGPoint(x: 50, y: 50)), 0, 0.001))
        #expect(close(arch.distance(to: CGPoint(x: 50, y: 40)), 10, 0.001))
        #expect(arch.distance(to: CGPoint(x: 50, y: 100)) > 40)
        #expect(close(arch.distance(to: CGPoint(x: -10, y: 100)), 10, 0.001))
    }

    @Test func measuresBendAndStraightness() {
        #expect(close(arch.bend, 50))
        let straight = QuadraticCurve(start: .zero, through: CGPoint(x: 50, y: 0.5), end: CGPoint(x: 100, y: 0))
        #expect(straight.isStraight(tolerance: 1))
        #expect(!arch.isStraight(tolerance: 1))
    }

    @Test func splitsIntoMatchingHalves() {
        let (first, second) = arch.split(at: 0.5)
        #expect(first.end == second.start)
        #expect(close(first.end.x, arch.midpoint.x))
        #expect(close(first.point(at: 0.5).x, arch.point(at: 0.25).x))
        #expect(close(second.point(at: 0.5).y, arch.point(at: 0.75).y))
    }

    @Test func trimsByDistanceFromEachEnd() {
        let trimmed = arch.trimmed(startBy: 10, endBy: 20)
        #expect(close(hypot(trimmed.end.x - arch.end.x, trimmed.end.y - arch.end.y), 20, 0.05))
        #expect(close(hypot(trimmed.start.x - arch.start.x, trimmed.start.y - arch.start.y), 10, 0.05))
        #expect(close(arch.distance(to: trimmed.midpoint), 0, 0.05))
        #expect(arch.trimmed(startBy: 0, endBy: 0) == arch)
    }

    @Test func defaultControlBulgesToTheSide() {
        let control = QuadraticCurve.defaultControl(from: .zero, to: CGPoint(x: 100, y: 0))
        let curve = QuadraticCurve(start: .zero, control: control, end: CGPoint(x: 100, y: 0))
        #expect(close(curve.midpoint.y, 25))
        #expect(QuadraticCurve.defaultControl(from: .zero, to: .zero) == .zero)
    }

    @Test func samplesIncludeBothEnds() {
        let samples = arch.samples(count: 4)
        #expect(samples.count == 5)
        #expect(samples.first == arch.start)
        #expect(samples.last == arch.end)
    }
}
