import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct CombineLayoutTests {
    let sizes = [CGSize(width: 100, height: 50), CGSize(width: 60, height: 80), CGSize(width: 40, height: 40)]

    @Test func horizontalLayoutPlacesImagesSideBySide() {
        let layout = CombineLayoutEngine.layout(for: sizes, style: CombineStyle(layout: .horizontal, alignment: .center, spacing: 10, padding: 5))
        #expect(layout.canvasSize == CGSize(width: 5 + 100 + 10 + 60 + 10 + 40 + 5, height: 90))
        #expect(layout.frames[0] == CGRect(x: 5, y: 20, width: 100, height: 50))
        #expect(layout.frames[1] == CGRect(x: 115, y: 5, width: 60, height: 80))
        #expect(layout.frames[2] == CGRect(x: 185, y: 25, width: 40, height: 40))
    }

    @Test(arguments: [(CombineAlignment.leading, CGFloat(0)), (.center, 20), (.trailing, 40)])
    func verticalLayoutAlignsHorizontally(alignment: CombineAlignment, offset: CGFloat) {
        let layout = CombineLayoutEngine.layout(for: sizes, style: CombineStyle(layout: .vertical, alignment: alignment, spacing: 0, padding: 0))
        #expect(layout.canvasSize == CGSize(width: 100, height: 170))
        #expect(layout.frames[1].minX == offset)
        #expect(layout.frames[2].minY == 130)
    }

    @Test func gridUsesSquareishColumns() {
        #expect(CombineLayoutEngine.gridColumns(for: 4, preferred: nil) == 2)
        #expect(CombineLayoutEngine.gridColumns(for: 5, preferred: nil) == 3)
        #expect(CombineLayoutEngine.gridColumns(for: 3, preferred: 8) == 3)
        #expect(CombineLayoutEngine.gridColumns(for: 0, preferred: 2) == 1)
        let layout = CombineLayoutEngine.layout(for: sizes, style: CombineStyle(layout: .grid, alignment: .leading, spacing: 4, padding: 0, columns: 2))
        #expect(layout.canvasSize == CGSize(width: 164, height: 124))
        #expect(layout.frames[2] == CGRect(x: 0, y: 84, width: 40, height: 40))
    }

    @Test func emptyInputHasNoCanvas() {
        #expect(CombineLayoutEngine.layout(for: [], style: CombineStyle()) == CombinedLayout(canvasSize: .zero, frames: []))
    }

    @Test func roundsSpacingAndPaddingAndIgnoresNegatives() {
        let layout = CombineLayoutEngine.layout(for: [CGSize(width: 10, height: 10), CGSize(width: 10, height: 10)], style: CombineStyle(spacing: 3.6, padding: -5))
        #expect(layout.canvasSize == CGSize(width: 24, height: 10))
        #expect(layout.frames[1].minX == 14)
    }

    @Test func shadowRadiusFollowsThePadding() {
        #expect(CombineLayoutEngine.shadowRadius(enabled: false, padding: 40, scale: 1) == 0)
        #expect(CombineLayoutEngine.shadowRadius(enabled: true, padding: 2, scale: 1) == 4)
        #expect(CombineLayoutEngine.shadowRadius(enabled: true, padding: 40, scale: 0.5) == 10)
        #expect(CombineLayoutEngine.shadowRadius(enabled: true, padding: 200, scale: 1) == 28)
    }

    @Test func cornerRadiusNeverExceedsHalfTheShortSide() {
        #expect(CombineLayoutEngine.cornerRadius(50, for: CGRect(x: 0, y: 0, width: 40, height: 80)) == 20)
        #expect(CombineLayoutEngine.cornerRadius(8, for: CGRect(x: 0, y: 0, width: 40, height: 80)) == 8)
    }
}
