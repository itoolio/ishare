import Alamofire
import Foundation

struct CapturedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data
}

struct StubResponse: Sendable {
    var status: Int = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var body: Data = Data()
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: (@Sendable (CapturedRequest) -> StubResponse) = { _ in StubResponse() }
    nonisolated(unsafe) static var captured: [CapturedRequest] = []
    private static let lock = NSLock()

    static func reset(responder: @escaping @Sendable (CapturedRequest) -> StubResponse) {
        lock.withLock {
            self.responder = responder
            captured = []
        }
    }

    static var lastRequest: CapturedRequest? {
        lock.withLock { captured.last }
    }

    static func makeSession() -> Session {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return Session(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let captured = CapturedRequest(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.readBody(of: request)
        )
        let response = Self.lock.withLock { () -> StubResponse in
            Self.captured.append(captured)
            return Self.responder(captured)
        }
        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
