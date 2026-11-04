import CoreGraphics
import Testing
@testable import ishareCore

struct ExportPresetTests {
    @Test func fitsTheLongestSide() {
        let slack = ExportPreset.builtIn[0]
        #expect(slack.outputSize(for: CGSize(width: 4800, height: 2400), pointScale: 2) == CGSize(width: 2400, height: 1200))
        #expect(slack.outputSize(for: CGSize(width: 800, height: 600), pointScale: 2) == CGSize(width: 800, height: 600))
    }

    @Test func halvesRetinaImagesWhenAsked() {
        let docs = ExportPreset.builtIn[1]
        #expect(docs.outputSize(for: CGSize(width: 2000, height: 1000), pointScale: 2) == CGSize(width: 1000, height: 500))
        #expect(docs.outputSize(for: CGSize(width: 2000, height: 1000), pointScale: 1) == CGSize(width: 2000, height: 1000))
        let small = ExportPreset.builtIn[3]
        #expect(small.outputSize(for: CGSize(width: 6000, height: 3000), pointScale: 2) == CGSize(width: 1280, height: 640))
    }
}
