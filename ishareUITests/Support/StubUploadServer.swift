import Foundation
import Network
import Synchronization

final class StubUploadServer: Sendable {
    struct ReceivedUpload: Equatable {
        let path: String
        let bodySize: Int
        let returnedURL: String
    }

    enum StartError: Error {
        case timedOut
        case failed(String)
    }

    private let queue = DispatchQueue(label: "dev.adrian.ishare.uitests.stub-server")
    private struct State {
        var listener: NWListener?
        var uploads: [ReceivedUpload] = []
        var port: UInt16 = 0
    }

    private let state = Mutex(State())

    var port: UInt16 {
        state.withLock { $0.port }
    }

    var uploads: [ReceivedUpload] {
        state.withLock { $0.uploads }
    }

    var uploadURL: String {
        "http://127.0.0.1:\(port)/upload"
    }

    func start(timeout: TimeInterval = 10) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        let failure = LockedBox<String?>(nil)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case let .failed(error):
                failure.value = error.localizedDescription
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + timeout) == .success else { throw StartError.timedOut }
        if let message = failure.value { throw StartError.failed(message) }
        state.withLock { state in
            state.listener = listener
            state.port = listener.port?.rawValue ?? 0
        }
    }

    func stop() {
        state.withLock { state in
            state.listener?.cancel()
            state.listener = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let content { buffer.append(content) }
            if let request = HTTPRequest(parsing: buffer) {
                respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let status: String
        let body: Data
        if request.method == "POST" || request.method == "PUT" {
            let returned = state.withLock { state -> String in
                let url = "http://127.0.0.1:\(state.port)/u/uitest-\(state.uploads.count + 1).png"
                state.uploads.append(ReceivedUpload(path: request.path, bodySize: request.body.count, returnedURL: url))
                return url
            }
            status = "200 OK"
            body = Data(#"{"url":"\#(returned)"}"#.utf8)
        } else {
            status = "404 Not Found"
            body = Data(#"{"error":"not found"}"#.utf8)
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(parsing data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator),
              let head = String(data: data[data.startIndex ..< headerEnd.lowerBound], encoding: .utf8)
        else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let rest = data[headerEnd.upperBound...]
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decoded = Self.decodeChunks(Data(rest)) else { return nil }
            body = decoded
        } else {
            let length = Int(headers["content-length"] ?? "0") ?? 0
            guard rest.count >= length else { return nil }
            body = Data(rest.prefix(length))
        }
        method = String(requestLine[0])
        path = String(requestLine[1])
        self.headers = headers
    }

    private static func decodeChunks(_ data: Data) -> Data? {
        var body = Data()
        var index = data.startIndex
        let lineEnd = Data("\r\n".utf8)
        while true {
            guard let sizeEnd = data[index...].range(of: lineEnd),
                  let sizeLine = String(data: data[index ..< sizeEnd.lowerBound], encoding: .ascii),
                  let size = Int(sizeLine.split(separator: ";").first.map(String.init) ?? "", radix: 16)
            else { return nil }
            let start = sizeEnd.upperBound
            if size == 0 { return body }
            guard data.distance(from: start, to: data.endIndex) >= size + 2 else { return nil }
            let end = data.index(start, offsetBy: size)
            body.append(data[start ..< end])
            index = data.index(end, offsetBy: 2)
        }
    }
}

final class LockedBox<Value: Sendable>: Sendable {
    private let stored: Mutex<Value>

    init(_ value: Value) {
        stored = Mutex(value)
    }

    var value: Value {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}
