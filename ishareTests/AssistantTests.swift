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
