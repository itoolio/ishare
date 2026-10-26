import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct UpscaleGeometryTests {
    @Test func multipliesBothSides() {
        #expect(UpscaleGeometry.outputSize(for: CGSize(width: 300, height: 200), factor: .double) == CGSize(width: 600, height: 400))
        #expect(UpscaleGeometry.outputSize(for: CGSize(width: 300, height: 200), factor: .quadruple) == CGSize(width: 1200, height: 800))
        #expect(UpscaleFactor.quadruple.passes == 2)
    }

    @Test func refusesResultsBeyondTheLimit() {
        #expect(UpscaleGeometry.canUpscale(CGSize(width: 4096, height: 100), by: .quadruple))
        #expect(!UpscaleGeometry.canUpscale(CGSize(width: 4097, height: 100), by: .quadruple))
        #expect(UpscaleGeometry.canUpscale(CGSize(width: 8192, height: 8192), by: .double))
        #expect(!UpscaleGeometry.canUpscale(CGSize(width: 100, height: 8193), by: .double))
        #expect(!UpscaleGeometry.canUpscale(.zero, by: .double))
    }

    @Test func listsTheFactorsThatFit() {
        #expect(UpscaleGeometry.availableFactors(for: CGSize(width: 800, height: 600)) == [.double, .quadruple])
        #expect(UpscaleGeometry.availableFactors(for: CGSize(width: 6000, height: 600)) == [.double])
        #expect(UpscaleGeometry.availableFactors(for: CGSize(width: 9000, height: 600)).isEmpty)
        #expect(UpscaleGeometry.availableFactors(for: CGSize(width: 100, height: 100), maximum: 300) == [.double])
    }
}
