import AppKit
import Foundation
import Testing
@testable import ishare

struct ScriptingTests {
    private func dictionary() throws -> XMLDocument {
        try XMLDocument(contentsOf: Fixtures.url("ishare/Scripting/ishare.sdef"), options: [])
    }

    @Test func everyCommandAndClassInTheDictionaryExists() throws {
        let document = try dictionary()
        let classes = try document.nodes(forXPath: "//cocoa/@class").compactMap(\.stringValue)
        #expect(classes.contains("ScriptCaptureCommand"))
        for name in classes where name != "NSApplication" {
            #expect(NSClassFromString(name) != nil, "\(name) is missing")
        }
    }

    @Test func eventCodesAreFourCharactersAndUnique() throws {
        let document = try dictionary()
        let codes = try document.nodes(forXPath: "//command/@code").compactMap(\.stringValue)
        #expect(codes.allSatisfy { $0.utf8.count == 8 })
        #expect(Set(codes).count == codes.count)
    }

    @Test func mapsEnumeratorCodesToActions() {
        #expect(ScriptingCodes.captureMode(nil) == .region)
        #expect(ScriptingCodes.captureMode(ScriptingCodes.fourCharCode("cWin")) == .window)
        #expect(ScriptingCodes.captureMode(ScriptingCodes.fourCharCode("zzzz")) == nil)
        #expect(ScriptingCodes.recordAction(ScriptingCodes.fourCharCode("rPau")) == .pause)
        #expect(ScriptingCodes.recordAction(nil) == .toggle)
        #expect(ScriptingCodes.openTarget(ScriptingCodes.fourCharCode("oHis")) == .history)
    }

    @Test func historyItemsExposeTheirLinkAndDetails() {
        let entry = CLIHistoryEntry(
            link: "https://example.com/a.png", shortLink: "https://s.example/a", title: "a.png", date: nil, uploader: "Stub", altText: "A cat")
        let item = ScriptableHistoryItem(entry)
        #expect(item.link == "https://s.example/a")
        #expect(item.id == "https://example.com/a.png")
        #expect(item.uploaderName == "Stub")
        #expect(item.altText == "A cat")
    }
}
