import Foundation
import ishareCore
import Testing
@testable import ishare

struct AutomationTestModeTests {
    @Test func isOnlyEnabledByAnExplicitYes() {
        #expect(AutomationTestMode.isEnabled(arguments: ["ishare", "-ishareAutomationTestMode", "YES"]))
        #expect(AutomationTestMode.isEnabled(arguments: ["ishare", "-ishareAutomationTestMode", "true"]))
        #expect(!AutomationTestMode.isEnabled(arguments: ["ishare", "-ishareAutomationTestMode", "NO"]))
        #expect(!AutomationTestMode.isEnabled(arguments: ["ishare", "-ishareAutomationTestMode"]))
        #expect(!AutomationTestMode.isEnabled(arguments: ["ishare", "-ishareUITestMode"]))
        #expect(!AutomationTestMode.isActive)
        #expect(AutomationTestMode.directory == nil)
        #expect(AutomationTestMode.mailboxDirectory == nil)
        #expect(!ScreenshotMode.isAutomationTesting)
    }

    @Test func usesTheRequestedAbsoluteDirectory() {
        let temporary = URL(fileURLWithPath: "/tmp/t", isDirectory: true)
        #expect(AutomationTestMode.directory(arguments: ["-ishareAutomationDirectory", "/tmp/work"], temporaryDirectory: temporary).path == "/tmp/work")
        #expect(AutomationTestMode.directory(arguments: ["-ishareAutomationDirectory", "relative"], temporaryDirectory: temporary).path == "/tmp/t/ishare-automation")
        #expect(AutomationTestMode.directory(arguments: [], temporaryDirectory: temporary).path == "/tmp/t/ishare-automation")
        let work = URL(fileURLWithPath: "/tmp/work", isDirectory: true)
        #expect(AutomationTestMode.mailbox(in: work).path == "/tmp/work/mailbox")
        #expect(AutomationTestMode.replies(in: work).path == "/tmp/work/replies")
        #expect(AutomationTestMode.uploads(in: work).path == "/tmp/work/uploads")
    }

    @Test func readsOnlySafeReplyIdentifiers() throws {
        #expect(AutomationTestMode.replyID(for: try #require(URL(string: "ishare://capture?automation-test-id=url-capture_1"))) == "url-capture_1")
        #expect(AutomationTestMode.replyID(for: try #require(URL(string: "ishare://capture?automation-test-id=..%2Fescape"))) == nil)
        #expect(AutomationTestMode.replyID(for: try #require(URL(string: "ishare://capture"))) == nil)
    }

    @Test func stubUploaderIsAValidFolderDestinationWithWebLinks() {
        let stub = AutomationTestMode.stubUploader(uploadsDirectory: URL(fileURLWithPath: "/tmp/work/uploads"))
        #expect(stub.name == AutomationTestMode.stubUploaderName)
        #expect(stub.folder?.path == "/tmp/work/uploads")
        #expect(stub.folder?.publicURL == "https://stub.ishare.test/{{path}}")
        #expect(UploaderValidator.issues(for: stub).isEmpty)
    }

    @MainActor @Test func testActionsStubRecordingOpeningAndCallbacks() async throws {
        let actions = AutomationTestActions(live: LiveAutomationActions.shared)
        #expect(await actions.record(.start, gif: false, region: false))
        #expect(await actions.record(.start, gif: true, region: true))
        #expect(!(await actions.record(.toggle, gif: false, region: false)))
        #expect(await actions.record(.toggle, gif: false, region: false))
        #expect(!(await actions.record(.stop, gif: false, region: false)))
        actions.open(.editor)
        #expect(actions.opened == ["editor"])
        let callback = try #require(URL(string: "shortcuts://done"))
        actions.openCallback(callback)
        #expect(actions.takeCallback() == callback)
        #expect(actions.takeCallback() == nil)
        actions.reset()
        #expect(actions.opened.isEmpty)
    }

    @MainActor @Test func repliesDescribeEveryOutcome() throws {
        let actions = AutomationTestActions(live: LiveAutomationActions.shared)
        let url = try #require(URL(string: "ishare://x-callback-url/capture/region?automation-test-id=a"))
        let completed = AutomationReply(url: url, outcome: .completed(link: "https://stub.ishare.test/a.png"), callback: nil, state: actions)
        #expect(completed.action == "x-callback-url/capture/region")
        #expect(completed.outcome == "completed")
        #expect(completed.link == "https://stub.ishare.test/a.png")
        let rejected = AutomationReply(url: url, outcome: .rejected(.unreadablePath("/x")), callback: URL(string: "a://b"), state: actions)
        #expect(rejected.outcome == "rejected")
        #expect(rejected.errorCode == 5)
        #expect(rejected.callback == "a://b")
        #expect(AutomationReply(url: url, outcome: .failed(.cancelled), callback: nil, state: actions).outcome == "cancelled")
        #expect(AutomationReply(url: url, outcome: .failed(.failed("x")), callback: nil, state: actions).outcome == "failed")
        let decoded = try CLICoding.decode(AutomationReply.self, from: CLICoding.encode(completed))
        #expect(decoded == completed)
    }

    @MainActor @Test func routerReportsOutcomesToItsObserver() async throws {
        let actions = AutomationTestActions(live: LiveAutomationActions.shared)
        let router = URLSchemeRouter(actions: actions, commandLine: CommandLineServer(mailbox: nil, actions: actions))
        var observed: [URLSchemeOutcome] = []
        router.onOutcome = { _, outcome in observed.append(outcome) }
        await router.handle(try #require(URL(string: "ishare://record/start")))
        await router.handle(try #require(URL(string: "ishare://teleport")))
        #expect(observed == [.completed(link: nil), .rejected(.unknownAction("teleport"))])
        #expect(actions.isRecording)
    }
}
