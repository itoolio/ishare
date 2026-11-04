import Foundation
import ishareCore
import Testing
@testable import ishare

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

enum Fuzz {
    static let iterations = 1500
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789:/?&=%#.-_~+ \"'{}[],\\\0\n\r\t«»😀ü")

    static func mutate(_ text: String, using generator: inout SeededGenerator) -> String {
        var characters = Array(text)
        for _ in 0 ..< Int.random(in: 1 ... 6, using: &generator) {
            switch Int.random(in: 0 ..< 4, using: &generator) {
            case 0 where !characters.isEmpty:
                characters.remove(at: Int.random(in: 0 ..< characters.count, using: &generator))
            case 1:
                characters.insert(alphabet.randomElement(using: &generator)!, at: Int.random(in: 0 ... characters.count, using: &generator))
            case 2 where !characters.isEmpty:
                characters[Int.random(in: 0 ..< characters.count, using: &generator)] = alphabet.randomElement(using: &generator)!
            default:
                let start = Int.random(in: 0 ... characters.count, using: &generator)
                characters.insert(contentsOf: characters.prefix(Int.random(in: 0 ... min(characters.count, 12), using: &generator)), at: start)
            }
        }
        return String(characters)
    }
}

struct URLSchemeFuzzTests {
    static let seeds = [
        "ishare://capture/region?x-success=app%3A%2F%2Fok", "ishare://capture/web?url=example.com&width=1024&format=pdf",
        "ishare://upload?path=%2Ftmp%2Fa.png&path=%2Ftmp%2Fb.png", "ishare://record/start?gif=1&region=1&preset=Demo",
        "ishare://uploader/select?name=My%20Server", "ishare://open/settings?pane=uploaders", "ishare://capture/app?name=Safari&sheet=1",
        "ishare://x-callback-url/capture/scrolling?x-error=app://failed", "ishare://cli?id=6F1B2C3D-0000-4000-8000-000000000000",
    ]

    @Test func neverCrashesAndOnlyAcceptsKnownActions() {
        var generator = SeededGenerator(seed: 0x15_0A_2E)
        let access = URLSchemeFileAccess { _ in true }
        var accepted = 0
        for index in 0 ..< Fuzz.iterations {
            let input = Fuzz.mutate(Self.seeds[index % Self.seeds.count], using: &generator)
            guard let url = URL(string: input) else { continue }
            if case let .success(request) = URLSchemeParser.parse(url, fileAccess: access) {
                accepted += 1
                for callback in [request.callback.success, request.callback.error, request.callback.cancel].compactMap(\.self) {
                    #expect(!XCallback.forbiddenSchemes.contains(callback.scheme?.lowercased() ?? ""), "\(input) accepted a forbidden callback")
                }
            }
        }
        #expect(accepted > 0)
    }
}

struct MCPFuzzTests {
    static let seeds = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"capture","arguments":{"mode":"screen","upload":true}}}"#,
        #"{"jsonrpc":"2.0","id":"x","method":"tools/call","params":{"name":"upload","arguments":{"paths":["/tmp/a.png"]}}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
    ]

    @Test func alwaysAnswersWithValidJSONRPC() async {
        var generator = SeededGenerator(seed: 0x4D_43_50)
        let server = MCPServer(version: "fuzz") { command, _ in
            var response = CLIResponse(id: UUID(), success: true)
            response.payload.message = String(describing: command)
            return response
        }
        for index in 0 ..< Fuzz.iterations {
            let input = Fuzz.mutate(Self.seeds[index % Self.seeds.count], using: &generator)
            guard let reply = await server.handle(input) else { continue }
            let object = (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any]
            #expect(object?["jsonrpc"] as? String == "2.0", "No JSON-RPC reply for \(input)")
            #expect((object?["result"] == nil) != (object?["error"] == nil), "\(input) produced both or neither result and error")
        }
    }
}

struct LocalAPIFuzzTests {
    @Test func parsesOrRejectsEveryRequest() {
        var generator = SeededGenerator(seed: 0x4C_41_50)
        let seed = "POST /v1/capture?x=1 HTTP/1.1\r\nAuthorization: Bearer abc\r\nContent-Length: 17\r\n\r\n{\"mode\":\"screen\"}"
        for _ in 0 ..< Fuzz.iterations {
            let input = Fuzz.mutate(seed, using: &generator)
            if case let .complete(request) = LocalAPIRequest.parse(Data(input.utf8)) {
                #expect(request.body.count <= LocalAPIRequest.maximumSize)
                #expect(!request.isAuthorized(token: ""))
            }
        }
    }
}
