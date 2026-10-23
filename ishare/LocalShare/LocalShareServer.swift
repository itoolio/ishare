import Foundation
import Network
import Security
import UniformTypeIdentifiers

enum LocalShareExpiry: String, CaseIterable, Identifiable, Codable, Sendable {
    case fiveMinutes
    case oneHour
    case untilQuit

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .fiveMinutes: 5 * 60
        case .oneHour: 60 * 60
        case .untilQuit: nil
        }
    }

    var title: String {
        switch self {
        case .fiveMinutes: "5 minutes".localized()
        case .oneHour: "1 hour".localized()
        case .untilQuit: "Until ishare quits".localized()
        }
    }
}

struct LocalShareEntry: Equatable, Sendable {
    let token: String
    let fileURL: URL
    let fileName: String
    let contentType: String
    let expiresAt: Date?
    let maxDownloads: Int?
    var downloads = 0

    func isAvailable(at date: Date) -> Bool {
        if let expiresAt, date >= expiresAt { return false }
        if let maxDownloads, downloads >= maxDownloads { return false }
        return true
    }

    var path: String {
        "/\(token)/\(LocalShareRequest.encodedPathComponent(fileName))"
    }
}

struct LocalShareRequest: Equatable, Sendable {
    let method: String
    let token: String?

    static let maximumHeaderSize = 16 * 1024

    static func headerEnd(in data: Data) -> Int? {
        data.range(of: Data("\r\n\r\n".utf8)).map(\.upperBound)
    }

    static func parse(_ data: Data) -> LocalShareRequest? {
        guard let end = headerEnd(in: data),
              let head = String(data: data.prefix(end), encoding: .utf8),
              let requestLine = head.components(separatedBy: "\r\n").first
        else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return nil }
        let target = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let segments = target.split(separator: "/", omittingEmptySubsequences: true)
        let token = segments.first.map(String.init).flatMap { isWellFormedToken($0) ? $0 : nil }
        return LocalShareRequest(method: String(parts[0]), token: token)
    }

    static func isWellFormedToken(_ token: String) -> Bool {
        token.count >= 16 && token.count <= 64 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func encodedPathComponent(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? "file"
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0 ..< 24).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum LocalShareResponse: Equatable, Sendable {
    case file(LocalShareEntry, includeBody: Bool)
    case notFound
    case gone
    case methodNotAllowed
    case badRequest

    var status: (code: Int, reason: String) {
        switch self {
        case .file: (200, "OK")
        case .notFound: (404, "Not Found")
        case .gone: (410, "Gone")
        case .methodNotAllowed: (405, "Method Not Allowed")
        case .badRequest: (400, "Bad Request")
        }
    }

    func header(contentLength: Int) -> Data {
        var lines = ["HTTP/1.1 \(status.code) \(status.reason)"]
        if case let .file(entry, _) = self {
            lines.append("Content-Type: \(entry.contentType)")
            lines.append("Content-Length: \(contentLength)")
            lines.append("Content-Disposition: inline; filename*=UTF-8''\(LocalShareRequest.encodedPathComponent(entry.fileName))")
        } else {
            lines.append("Content-Type: text/plain; charset=utf-8")
            lines.append("Content-Length: \(contentLength)")
        }
        if self == .methodNotAllowed {
            lines.append("Allow: GET, HEAD")
        }
        lines.append("Cache-Control: no-store")
        lines.append("X-Content-Type-Options: nosniff")
        lines.append("Referrer-Policy: no-referrer")
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    var errorBody: Data {
        Data("\(status.code) \(status.reason)\n".utf8)
    }
}

enum LocalShareError: LocalizedError, Equatable {
    case listenerFailed(String)
    case noNetworkAddress
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case let .listenerFailed(reason): String(format: "The local network server couldn't start: %@".localized(), reason)
        case .noNetworkAddress: "This Mac isn't connected to a local network.".localized()
        case .unreadableFile: "The file can't be shared because ishare can't read it.".localized()
        }
    }
}

final class LocalShareServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.adrian.ishare.localshare")
    private let clock: @Sendable () -> Date
    private var listener: NWListener?
    private var entries: [String: LocalShareEntry] = [:]
    private var boundPort: UInt16?

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    var port: UInt16? {
        queue.sync { boundPort }
    }

    var activeEntries: [LocalShareEntry] {
        queue.sync { Array(entries.values) }
    }

    func entry(for token: String) -> LocalShareEntry? {
        queue.sync { entries[token] }
    }

    func start() async throws -> UInt16 {
        if let port { return port }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = false
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw LocalShareError.listenerFailed(error.localizedDescription)
        }
        let gate = StartGate()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .ready:
                    let port = listener?.port?.rawValue ?? 0
                    self?.boundPort = port
                    gate.finish { continuation.resume(returning: port) }
                case let .failed(error):
                    self?.listener = nil
                    self?.boundPort = nil
                    listener?.cancel()
                    gate.finish { continuation.resume(throwing: LocalShareError.listenerFailed(error.localizedDescription)) }
                case .cancelled:
                    gate.finish { continuation.resume(throwing: LocalShareError.listenerFailed("cancelled")) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            queue.async {
                self.listener = listener
                listener.start(queue: self.queue)
            }
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            boundPort = nil
            entries.removeAll()
        }
    }

    @discardableResult
    func add(fileURL: URL, fileName: String? = nil, expiry: LocalShareExpiry, maxDownloads: Int?, token: String = LocalShareRequest.makeToken()) -> LocalShareEntry {
        let name = fileName ?? fileURL.lastPathComponent
        let type = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let entry = LocalShareEntry(
            token: token, fileURL: fileURL, fileName: name, contentType: type,
            expiresAt: expiry.interval.map { clock().addingTimeInterval($0) },
            maxDownloads: maxDownloads.flatMap { $0 > 0 ? $0 : nil }
        )
        queue.sync { entries[token] = entry }
        return entry
    }

    func remove(token: String) {
        queue.sync { _ = entries.removeValue(forKey: token) }
    }

    @discardableResult
    func removeUnavailable() -> [LocalShareEntry] {
        queue.sync {
            let now = clock()
            let stale = entries.values.filter { !$0.isAvailable(at: now) }
            stale.forEach { entries.removeValue(forKey: $0.token) }
            return stale
        }
    }

    func respond(to request: LocalShareRequest?) -> LocalShareResponse {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let request else { return .badRequest }
        guard request.method == "GET" || request.method == "HEAD" else { return .methodNotAllowed }
        guard let token = request.token, let entry = entries.first(where: { Self.constantTimeEquals($0.key, token) })?.value else {
            return .notFound
        }
        guard entry.isAvailable(at: clock()) else { return .gone }
        let includeBody = request.method == "GET"
        if includeBody {
            entries[token]?.downloads += 1
        }
        return .file(entries[token] ?? entry, includeBody: includeBody)
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func accept(_ connection: NWConnection) {
        let progress = HeaderProgress()
        connection.start(queue: queue)
        receiveHeader(on: connection, buffer: Data(), progress: progress)
        queue.asyncAfter(deadline: .now() + 15) { [weak connection] in
            if !progress.isComplete {
                connection?.cancel()
            }
        }
    }

    private func receiveHeader(on connection: NWConnection, buffer: Data, progress: HeaderProgress) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if LocalShareRequest.headerEnd(in: buffer) != nil {
                progress.isComplete = true
                send(respond(to: LocalShareRequest.parse(buffer)), on: connection)
            } else if error != nil || isComplete || buffer.count > LocalShareRequest.maximumHeaderSize {
                send(.badRequest, on: connection)
            } else {
                receiveHeader(on: connection, buffer: buffer, progress: progress)
            }
        }
    }

    private func send(_ response: LocalShareResponse, on connection: NWConnection) {
        guard case let .file(entry, includeBody) = response else {
            let body = response.errorBody
            connection.send(content: response.header(contentLength: body.count) + body, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        guard let handle = try? FileHandle(forReadingFrom: entry.fileURL),
              let size = try? entry.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else {
            send(.gone, on: connection)
            return
        }
        connection.send(content: response.header(contentLength: size), completion: .contentProcessed { [weak self] error in
            guard error == nil, includeBody, let self else {
                try? handle.close()
                connection.cancel()
                return
            }
            streamBody(from: handle, on: connection)
        })
    }

    private func streamBody(from handle: FileHandle, on connection: NWConnection) {
        let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? nil
        guard let chunk, !chunk.isEmpty else {
            try? handle.close()
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil, let self else {
                try? handle.close()
                connection.cancel()
                return
            }
            streamBody(from: handle, on: connection)
        })
    }
}

private final class HeaderProgress: @unchecked Sendable {
    var isComplete = false
}

private final class StartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !finished
        finished = true
        lock.unlock()
        if shouldRun { body() }
    }
}
