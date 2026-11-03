import Foundation
import Synchronization
import Testing
@testable import ishare

struct MCPServerTests {
    final class Recorder: Sendable {
        let commands = Mutex<[CLICommand]>([])
    }

    func server(_ recorder: Recorder = Recorder(), succeeds: Bool = true) -> MCPServer {
        MCPServer(version: "9.9") { command, _ in
            recorder.commands.withLock { $0.append(command) }
            var response = CLIResponse(id: UUID(), success: succeeds, error: succeeds ? nil : "No uploader is selected")
            response.payload.capture = CLICaptureResult(file: "/tmp/shot.png", link: "https://example.com/shot.png")
            return response
        }
    }

    func object(_ reply: String?) throws -> [String: Any] {
        let data = try #require(reply?.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func negotiatesTheProtocol() async throws {
        let reply = try object(await server().handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2024-11-05")
        #expect((result["serverInfo"] as? [String: Any])?["version"] as? String == "9.9")
        let newer = try object(await server().handle(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        #expect((newer["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.protocolVersion)
    }

    @Test func ignoresNotificationsAndRejectsUnknownMethods() async throws {
        #expect(await server().handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        let reply = try object(await server().handle(#"{"jsonrpc":"2.0","id":"a","method":"resources/list"}"#))
        #expect((reply["error"] as? [String: Any])?["code"] as? Int == -32601)
        let garbage = try object(await server().handle("not json"))
        #expect((garbage["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test func listsEveryTool() async throws {
        let reply = try object(await server().handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
        let tools = try #require((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["capture", "capture_app", "upload", "list_uploaders", "recent_uploads", "record"])
    }

    @Test func runsToolsThroughTheCommandLineProtocol() async throws {
        let recorder = Recorder()
        let reply = try object(
            await server(recorder).handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"capture","arguments":{"mode":"screen","upload":true}}}"#))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(text.contains("https://example.com/shot.png"))
        _ = await server(recorder).handle(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"capture_app","arguments":{"app":"Safari"}}}"#)
        _ = await server(recorder).handle(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"recent_uploads","arguments":{"limit":900}}}"#)
        #expect(recorder.commands.withLock { $0 } == [.capture(mode: .screen, upload: true), .captureApp(app: "Safari", contactSheet: false, upload: false), .history(limit: 500)])
    }

    @Test func reportsBadArgumentsAndFailuresAsToolErrors() async throws {
        let bad = try object(await server().handle(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"upload","arguments":{"paths":["relative.png"]}}}"#))
        #expect((bad["result"] as? [String: Any])?["isError"] as? Bool == true)
        let failed = try object(await server(succeeds: false).handle(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"list_uploaders"}}"#))
        #expect((failed["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test func startsFromTheCommandLine() throws {
        #expect(try CLIArguments.parse(["mcp"]) == .mcp)
        #expect(CLIArguments.usage.contains("mcp"))
    }
}
