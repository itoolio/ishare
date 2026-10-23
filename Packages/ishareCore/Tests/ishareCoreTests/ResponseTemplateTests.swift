import Foundation
import SwiftyJSON
import Testing
@testable import ishareCore

struct ResponseTemplateTests {
    let json = JSON(
        parseJSON: """
            {"url": "https://example.com/a.png", "files": [{"url": "https://cdn.example.com/f.png", "id": 7}],
             "data": {"link": "https://i.imgur.com/x.png", "nested": {"deep": [1, {"value": true}]}}}
            """)

    @Test func rendersSimpleKey() throws {
        #expect(try ResponseTemplate.render("{{url}}", json: json) == "https://example.com/a.png")
    }

    @Test func rendersArrayIndexAndNestedKeys() throws {
        #expect(try ResponseTemplate.render("{{files[0].url}}", json: json) == "https://cdn.example.com/f.png")
        #expect(try ResponseTemplate.render("{{data.nested.deep[1].value}}", json: json) == "true")
    }

    @Test func rendersMultiplePlaceholdersWithLiterals() throws {
        let rendered = try ResponseTemplate.render("https://host/{{files[0].id}}?link={{data.link}}", json: json)
        #expect(rendered == "https://host/7?link=https://i.imgur.com/x.png")
    }

    @Test func throwsForMissingValues() {
        #expect(throws: ResponseTemplateError.missingValue("files[3].url")) {
            try ResponseTemplate.render("{{files[3].url}}", json: json)
        }
    }

    @Test func rendersRawResponseBodyForNonJSONResponses() throws {
        let data = Data("https://paste.example.com/abc\n".utf8)
        #expect(try ResponseTemplate.render("{{response}}", data: data) == "https://paste.example.com/abc")
    }

    @Test func listsPlaceholders() {
        #expect(ResponseTemplate.placeholders(in: "a{{x}}b{{y.z[0]}}") == ["x", "y.z[0]"])
    }

    @Test func parsesPathComponents() {
        #expect(ResponseTemplate.pathComponents("a.b[2].c") == [.key("a"), .key("b"), .index(2), .key("c")])
    }

    @Test func leavesTemplatesWithoutPlaceholdersUntouched() throws {
        #expect(try ResponseTemplate.render("https://static.example.com", json: json) == "https://static.example.com")
    }
}
