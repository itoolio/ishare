import Foundation
import Testing
@testable import ishareCore

struct LocalAPITests {
    func raw(_ text: String) -> Data { Data(text.utf8) }

    @Test func parsesRequestsOnceTheBodyHasArrived() throws {
        let head = "POST /v1/capture?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc\r\nContent-Length: 17\r\n\r\n"
        #expect(LocalAPIRequest.parse(raw(head + "{\"mode\":")) == .incomplete)
        guard case let .complete(request) = LocalAPIRequest.parse(raw(head + "{\"mode\":\"screen\"}")) else {
            Issue.record("The request didn't parse")
            return
        }
        #expect(request.method == "POST")
        #expect(request.toolName == "capture")
        #expect(request.query == ["x": "1"])
        #expect(String(decoding: request.body, as: UTF8.self) == "{\"mode\":\"screen\"}")
        #expect(request.isAuthorized(token: "abc"))
        #expect(!request.isAuthorized(token: "abd"))
        #expect(!request.isAuthorized(token: ""))
    }

    @Test func rejectsMalformedRequests() {
        #expect(LocalAPIRequest.parse(raw("GET /v1/x\r\n\r\n")) == .invalid)
        #expect(LocalAPIRequest.parse(raw("GET /v1/x HTTP/1.1\r\nBroken\r\n\r\n")) == .invalid)
        #expect(LocalAPIRequest.parse(raw("GET /v1/x HTTP/1.1\r\nHost: a")) == .incomplete)
    }

    @Test func onlyRoutesVersionedTools() {
        guard case let .complete(request) = LocalAPIRequest.parse(raw("GET /other/path HTTP/1.1\r\n\r\n")) else { return }
        #expect(request.toolName == nil)
        #expect(LocalAPIRequest.makeToken().count == 64)
        #expect(String(decoding: LocalAPIRequest.response(status: 401, body: Data()), as: UTF8.self).hasPrefix("HTTP/1.1 401 Unauthorized"))
    }
}
