import Testing
@testable import ishareCore

struct ImagePointScaleTests {
    @Test func readsTheScaleFromTheResolution() {
        #expect(ImagePointScale.scale(dpi: 144) == 2)
        #expect(ImagePointScale.scale(dpi: 72) == 1)
        #expect(ImagePointScale.scale(dpi: 216) == 3)
        #expect(ImagePointScale.scale(dpi: 143.9) == 2)
        #expect(ImagePointScale.scale(dpi: 1200) == 4)
        #expect(ImagePointScale.scale(dpi: nil) == nil)
        #expect(ImagePointScale.scale(dpi: 0) == nil)
    }

    @Test func writesTheResolutionForAScale() {
        #expect(ImagePointScale.dpi(for: 2) == 144)
        #expect(ImagePointScale.dpi(for: 0.5) == 72)
    }
}
