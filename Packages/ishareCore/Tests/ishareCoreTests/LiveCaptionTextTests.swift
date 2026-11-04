import Testing
@testable import ishareCore

struct LiveCaptionTextTests {
    @Test func wrapsAtWordBoundaries() {
        #expect(LiveCaptionText.lines(of: "one two three four", lineLength: 9, lineCount: 3) == ["one two", "three", "four"])
    }

    @Test func keepsOnlyTheLatestLines() {
        #expect(LiveCaptionText.lines(of: "alpha beta gamma delta epsilon", lineLength: 11, lineCount: 2) == ["gamma delta", "epsilon"])
    }

    @Test func clipsWordsLongerThanALine() {
        #expect(LiveCaptionText.lines(of: "supercalifragilistic", lineLength: 5, lineCount: 1) == ["istic"])
    }

    @Test func ignoresEmptyTranscripts() {
        #expect(LiveCaptionText.lines(of: "   ").isEmpty)
    }
}
