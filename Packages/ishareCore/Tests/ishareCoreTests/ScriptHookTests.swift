import Testing
@testable import ishareCore

struct ScriptHookTests {
    @Test func runsExecutableScriptsDirectly() {
        let invocation = ScriptHookInvocation.make(script: "/Users/me/hook.sh", event: .upload, file: "/tmp/a.png", link: "https://x/a.png", isExecutable: true)
        #expect(invocation.executable == "/Users/me/hook.sh")
        #expect(invocation.arguments == ["upload", "/tmp/a.png", "https://x/a.png"])
        #expect(invocation.environment == ["ISHARE_EVENT": "upload", "ISHARE_FILE": "/tmp/a.png", "ISHARE_LINK": "https://x/a.png"])
    }

    @Test func runsOtherScriptsWithTheShell() {
        let invocation = ScriptHookInvocation.make(script: "/Users/me/hook.sh", event: .capture, file: "/tmp/a.png", link: nil, isExecutable: false)
        #expect(invocation.executable == ScriptHookInvocation.shell)
        #expect(invocation.arguments == ["/Users/me/hook.sh", "capture", "/tmp/a.png"])
        #expect(invocation.environment["ISHARE_LINK"] == nil)
    }
}
