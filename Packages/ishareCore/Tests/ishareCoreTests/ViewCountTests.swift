import Foundation
import Testing
@testable import ishareCore

struct ViewCountTests {
    @Test func decodesTheSpecFromAnUploader() throws {
        let json = """
            {"name": "zipline", "requestURL": "https://z.example/api/upload", "responseURL": "{{files[0].url}}",
             "viewCount": {"URL": "https://z.example/api/user/files/{{files[0].id}}", "path": "views"}}
            """
        let uploader = try JSONDecoder().decode(CustomUploader.self, from: Data(json.utf8))
        #expect(uploader.viewCount == ViewCountSpec(url: "https://z.example/api/user/files/{{files[0].id}}", path: "views"))
        let encoded = try JSONEncoder().encode(uploader)
        #expect(try JSONDecoder().decode(CustomUploader.self, from: encoded).viewCount == uploader.viewCount)
    }

    @Test func readsCountsFromNestedResponses() {
        #expect(ViewCountParser.count(in: Data(#"{"views": 42}"#.utf8), path: "views") == 42)
        #expect(ViewCountParser.count(in: Data(#"{"file": {"stats": [{"views": "7"}]}}"#.utf8), path: "file.stats[0].views") == 7)
        #expect(ViewCountParser.count(in: Data(#"{"views": 3.0}"#.utf8), path: "views") == 3)
        #expect(ViewCountParser.count(in: Data(#"{"other": 1}"#.utf8), path: "views") == nil)
        #expect(ViewCountParser.count(in: Data("nope".utf8), path: "views") == nil)
    }

    @Test func refreshesStaleCounts() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(ViewCountParser.needsRefresh(checkedAt: nil, now: now))
        #expect(!ViewCountParser.needsRefresh(checkedAt: now.addingTimeInterval(-60), now: now))
        #expect(ViewCountParser.needsRefresh(checkedAt: now.addingTimeInterval(-601), now: now))
    }

    @Test func shortensLargeCounts() {
        #expect(ViewCountParser.label(for: 999) == "999")
        #expect(ViewCountParser.label(for: 1000) == "1K")
        #expect(ViewCountParser.label(for: 1260) == "1.3K")
        #expect(ViewCountParser.label(for: 2_000_000) == "2M")
    }
}
