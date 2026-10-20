import Foundation
import Testing
@testable import ishare

struct UploaderAssistantMapperTests {
    let spec = GeneratedUploaderSpec(
        name: "zipline", requestURL: "https://model-guess.example.com/upload", bodyType: "multipart", fileFormName: "file",
        headerNames: ["Authorization", "X-Extra"], headerValues: ["YOUR_API_KEY", "1"], formFieldNames: ["folder"], formFieldValues: ["shots"],
        responseURL: "files[0].url", deletionURL: "", deletionMethod: "GET"
    )

    @Test func wrapsBareJSONPathsInPlaceholders() {
        #expect(UploaderAssistantMapper.template("files[0].url") == "{{files[0].url}}")
        #expect(UploaderAssistantMapper.template("$.data.link") == "{{data.link}}")
        #expect(UploaderAssistantMapper.template("{{url}}") == "{{url}}")
        #expect(UploaderAssistantMapper.template("https://cdn/{{id}}") == "https://cdn/{{id}}")
        #expect(UploaderAssistantMapper.template("  ") == "")
    }

    @Test func prefersTheUsersAnswersOverTheModel() {
        let answers = AssistantAnswers(service: "Zipline", endpoint: "https://share.example.com/api/upload", authHeaderName: "authorization", authHeaderValue: "real-token", fileFieldName: "upload")
        let uploader = UploaderAssistantMapper.uploader(from: spec, answers: answers)
        #expect(uploader.requestURL == "https://share.example.com/api/upload")
        #expect(uploader.headers?["authorization"] == "real-token")
        #expect(uploader.headers?["Authorization"] == nil)
        #expect(uploader.headers?["X-Extra"] == "1")
        #expect(uploader.fileFormName == "upload")
        #expect(uploader.formData == ["folder": "shots"])
        #expect(uploader.responseURL == "{{files[0].url}}")
        #expect(uploader.deletionURL == nil)
        #expect(UploaderValidator.issues(for: uploader).isEmpty)
    }

    @Test func mapsBinaryUploadsAndDeletion() {
        var binary = spec
        binary.bodyType = "binary"
        binary.deletionURL = "delete_url"
        binary.deletionMethod = "delete"
        let uploader = UploaderAssistantMapper.uploader(from: binary, answers: AssistantAnswers())
        #expect(uploader.requestBodyType == .binary)
        #expect(uploader.fileFormName == nil)
        #expect(uploader.formData == nil)
        #expect(uploader.requestURL == "https://model-guess.example.com/upload")
        #expect(uploader.deletionURL == "{{delete_url}}")
        #expect(uploader.deleteRequestType == .delete)
    }

    @Test func buildsAPromptFromTheAnswers() {
        let prompt = AssistantAnswers(service: "chibisafe", endpoint: "https://c.example.com/api/upload", exampleResponse: #"{"url": "x"}"#).prompt
        #expect(prompt.contains("Service: chibisafe"))
        #expect(prompt.contains("Upload endpoint: https://c.example.com/api/upload"))
        #expect(prompt.contains(#"{"url": "x"}"#))
        #expect(!prompt.contains("Authentication"))
    }
}

struct AssistantRefinementTests {
    @Test func findsJSONExamplesInChatText() {
        let objects = AssistantRefinement.jsonObjects(in: #"it returns {"files": [{"url": "https://a.b/x.png"}]} and sometimes "{" in prose"#)
        #expect(objects.count == 1)
    }

    @Test func findsTheLinkPathInAnExampleResponse() {
        let object = try! JSONSerialization.jsonObject(with: Data(#"{"ok": true, "data": {"delete_url": "https://x/d", "link": "https://x/i.png"}}"#.utf8))
        #expect(AssistantRefinement.urlPath(in: object) == "data.link")
        let array = try! JSONSerialization.jsonObject(with: Data(#"{"files": [{"url": "https://x/f.png"}]}"#.utf8))
        #expect(AssistantRefinement.urlPath(in: array) == "files[0].url")
    }

    @Test func fixesTemplatesThatDoNotMatchTheExample() {
        let draft = CustomUploader(
            name: "zipline", requestURL: "https://share.example.com/api/upload", headers: ["Authorization": "abc123"],
            formData: ["token": "abc123", "folder": "shots"], fileFormName: "file", responseURL: "{{data.url}}",
            deletionURL: "/api/delete/{{url}}", deleteRequestType: .delete
        )
        let refined = AssistantRefinement.refine(draft, conversation: #"response is {"files": [{"url": "https://share.example.com/u/x.png"}]}"#)
        #expect(refined.responseURL == "{{files[0].url}}")
        #expect(refined.deletionURL == nil)
        #expect(refined.deleteRequestType == nil)
        #expect(refined.formData == ["folder": "shots"])
        #expect(refined.id == draft.id)
    }

    @Test func keepsTemplatesThatAlreadyResolve() {
        let draft = CustomUploader(name: "x", requestURL: "https://a.b/u", headers: nil, formData: nil, fileFormName: nil, responseURL: "{{data.link}}")
        let refined = AssistantRefinement.refine(draft, conversation: #"{"data": {"link": "https://a.b/1.png", "url": "https://a.b/other"}}"#)
        #expect(refined.responseURL == "{{data.link}}")
    }
}

struct AssistantDeletionTemplateTests {
    @Test(arguments: [("{{/api/delete}}", false), ("/api/delete/{{id}}", false), ("https://x/del/{{id}}", true), ("{{files[0].delete}}", true)])
    func filtersDeletionTemplates(pair: (String, Bool)) {
        #expect(AssistantRefinement.isUsableDeletionTemplate(pair.0, examples: []) == pair.1)
    }
}
