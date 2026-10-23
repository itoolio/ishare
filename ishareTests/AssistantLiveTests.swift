import Foundation
import ishareCore
import Testing
@testable import ishare

@MainActor
struct AssistantLiveTests {
    nonisolated static var enabled: Bool {
        ProcessInfo.processInfo.environment["ISHARE_LIVE_ASSISTANT"] == "1" && UploaderAssistantAvailability.isAvailable
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(3)))
    func buildsAnUploaderFromAConversation() async throws {
        let model = UploaderAssistantChatModel()
        model.input =
            "I self-host Zipline at https://share.example.com. Uploads go to /api/upload as multipart with the field file, and my token abc123 goes in the Authorization header. The response looks like {\"files\": [{\"url\": \"https://share.example.com/u/x.png\"}]}"
        model.send()
        while model.isResponding {
            try await Task.sleep(for: .milliseconds(200))
        }
        let draft = try #require(model.draft, "The assistant replied without building a draft: \(model.messages.last?.text ?? "")")
        print("assistant reply:", model.messages.last?.text ?? "")
        print("draft:", String(data: try draft.toJSON(), encoding: .utf8) ?? "")
        #expect(draft.requestURL.hasPrefix("https://share.example.com"))
        #expect(draft.headers?["Authorization"]?.contains("abc123") == true)
        #expect(draft.responseURL.contains("files[0].url"))
        #expect(UploaderValidator.issues(for: draft).isEmpty)
    }
}
