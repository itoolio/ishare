import Foundation
import Testing
@testable import ishare

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = date
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}

struct LocalShareRequestTests {
    @Test func parsesTheMethodAndToken() {
        let token = LocalShareRequest.makeToken()
        let request = LocalShareRequest.parse(Data("GET /\(token)/shot%20one.png?x=1 HTTP/1.1\r\nHost: a\r\n\r\n".utf8))
        #expect(request == LocalShareRequest(method: "GET", token: token))
    }

    @Test func rejectsMalformedRequests() {
        #expect(LocalShareRequest.parse(Data("GET / HTTP/1.1\r\n".utf8)) == nil)
        #expect(LocalShareRequest.parse(Data("NONSENSE\r\n\r\n".utf8)) == nil)
        #expect(LocalShareRequest.parse(Data("GET /short/a.png HTTP/1.1\r\n\r\n".utf8))?.token == nil)
        #expect(LocalShareRequest.parse(Data("GET /../../etc/passwd HTTP/1.1\r\n\r\n".utf8))?.token == nil)
    }

    @Test func makesLongURLSafeTokens() {
        let tokens = Set((0 ..< 50).map { _ in LocalShareRequest.makeToken() })
        #expect(tokens.count == 50)
        #expect(tokens.allSatisfy { $0.count == 32 && LocalShareRequest.isWellFormedToken($0) })
    }

    @Test func comparesTokensInConstantTime() {
        #expect(LocalShareServer.constantTimeEquals("abc", "abc"))
        #expect(!LocalShareServer.constantTimeEquals("abc", "abd"))
        #expect(!LocalShareServer.constantTimeEquals("abc", "abcd"))
    }

    @Test func expiryChoicesMapToIntervals() {
        #expect(LocalShareExpiry.fiveMinutes.interval == 300)
        #expect(LocalShareExpiry.oneHour.interval == 3600)
        #expect(LocalShareExpiry.untilQuit.interval == nil)
    }
}

struct LocalNetworkAddressTests {
    let interfaces = [
        LocalNetworkInterface(name: "lo0", address: "127.0.0.1", isIPv6: false),
        LocalNetworkInterface(name: "utun3", address: "10.8.0.2", isIPv6: false),
        LocalNetworkInterface(name: "en1", address: "10.0.0.7", isIPv6: false),
        LocalNetworkInterface(name: "en0", address: "fe80::1%en0", isIPv6: true),
        LocalNetworkInterface(name: "en0", address: "fd00::5", isIPv6: true),
        LocalNetworkInterface(name: "en0", address: "192.168.1.20", isIPv6: false),
        LocalNetworkInterface(name: "bridge0", address: "169.254.3.3", isIPv6: false),
    ]

    @Test func prefersEn0IPv4AndListsAlternatives() {
        let candidates = LocalNetworkAddress.candidates(from: interfaces)
        #expect(candidates.map(\.address) == ["192.168.1.20", "10.0.0.7", "fd00::5"])
    }

    @Test func buildsURLsWithBracketedIPv6Hosts() {
        let urls = LocalNetworkAddress.urls(port: 5123, path: "/token/a.png", interfaces: interfaces)
        #expect(
            urls.map(\.absoluteString) == [
                "http://192.168.1.20:5123/token/a.png", "http://10.0.0.7:5123/token/a.png", "http://[fd00::5]:5123/token/a.png",
            ])
    }

    @Test func recognizesPrivateHosts() {
        #expect(LocalNetworkAddress.isPrivateHost("192.168.0.4"))
        #expect(LocalNetworkAddress.isPrivateHost("172.20.1.1"))
        #expect(LocalNetworkAddress.isPrivateHost("10.1.2.3"))
        #expect(!LocalNetworkAddress.isPrivateHost("172.40.1.1"))
        #expect(!LocalNetworkAddress.isPrivateHost("i.imgur.com"))
        #expect(!LocalNetworkAddress.isPrivateHost("8.8.8.8"))
    }
}

struct LocalShareServerTests {
    let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func makeFile(_ contents: String = "hello from ishare") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LocalShareTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "shot one.png")
        try Data(contents.utf8).write(to: file)
        return file
    }

    func fetch(_ port: UInt16, _ path: String, method: String = "GET") async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)\(path)")))
        request.httpMethod = method
        let (data, response) = try await session.data(for: request)
        return (data, try #require(response as? HTTPURLResponse))
    }

    @Test func servesTheFileAndRejectsUnknownTokens() async throws {
        let server = LocalShareServer()
        defer { server.stop() }
        let port = try await server.start()
        let file = try makeFile()
        let entry = server.add(fileURL: file, expiry: .untilQuit, maxDownloads: nil)

        let (data, response) = try await fetch(port, entry.path)
        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "hello from ishare")
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(response.value(forHTTPHeaderField: "Cache-Control") == "no-store")

        let (_, wrong) = try await fetch(port, "/\(LocalShareRequest.makeToken())/shot%20one.png")
        #expect(wrong.statusCode == 404)
        let (_, missing) = try await fetch(port, "/")
        #expect(missing.statusCode == 404)
        let (_, post) = try await fetch(port, entry.path, method: "POST")
        #expect(post.statusCode == 405)
    }

    @Test func stopsServingAfterTheMaximumDownloads() async throws {
        let server = LocalShareServer()
        defer { server.stop() }
        let port = try await server.start()
        let entry = server.add(fileURL: try makeFile(), expiry: .untilQuit, maxDownloads: 2)

        let (_, head) = try await fetch(port, entry.path, method: "HEAD")
        #expect(head.statusCode == 200)
        #expect(try await fetch(port, entry.path).1.statusCode == 200)
        #expect(try await fetch(port, entry.path).1.statusCode == 200)
        #expect(try await fetch(port, entry.path).1.statusCode == 410)
        #expect(server.entry(for: entry.token)?.downloads == 2)
    }

    @Test func stopsServingOnceExpired() async throws {
        let clock = TestClock()
        let server = LocalShareServer(clock: { clock.now })
        defer { server.stop() }
        let port = try await server.start()
        let entry = server.add(fileURL: try makeFile(), expiry: .fiveMinutes, maxDownloads: nil)

        #expect(try await fetch(port, entry.path).1.statusCode == 200)
        clock.advance(by: 299)
        #expect(try await fetch(port, entry.path).1.statusCode == 200)
        clock.advance(by: 2)
        #expect(try await fetch(port, entry.path).1.statusCode == 410)
        #expect(server.removeUnavailable().map(\.token) == [entry.token])
        #expect(try await fetch(port, entry.path).1.statusCode == 404)
    }

    @Test func streamsLargeFilesCompletely() async throws {
        let server = LocalShareServer()
        defer { server.stop() }
        let port = try await server.start()
        let contents = String(repeating: "0123456789abcdef", count: 80_000)
        let entry = server.add(fileURL: try makeFile(contents), expiry: .untilQuit, maxDownloads: nil)
        let (data, response) = try await fetch(port, entry.path)
        #expect(response.statusCode == 200)
        #expect(data.count == contents.utf8.count)
    }

    @MainActor @Test func managerCopiesTheFileAndBuildsLANLinks() async throws {
        let storage = FileManager.default.temporaryDirectory.appending(path: "LocalShares-\(UUID().uuidString)", directoryHint: .isDirectory)
        let manager = LocalShareManager(
            server: LocalShareServer(), storageDirectory: storage,
            interfaces: { [LocalNetworkInterface(name: "en0", address: "127.0.0.1", isIPv6: false), LocalNetworkInterface(name: "en0", address: "192.168.7.7", isIPv6: false)] }
        )
        defer { manager.stopAll() }
        let file = try makeFile()
        let share = try await manager.share(fileURL: file, expiry: .oneHour, maxDownloads: 1)
        try FileManager.default.removeItem(at: file)
        #expect(share.url.host() == "192.168.7.7")
        #expect(share.url.path().hasPrefix("/\(share.entry.token)/"))
        let port = try #require(share.url.port)
        let (data, response) = try await fetch(UInt16(port), share.entry.path)
        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "hello from ishare")
        #expect(try await fetch(UInt16(port), share.entry.path).1.statusCode == 410)
        manager.stop(token: share.entry.token)
        #expect(manager.activeShares.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storage.appending(path: share.entry.token).path))
    }

    @MainActor @Test func managerFailsWithoutANetworkAddress() async throws {
        let manager = LocalShareManager(
            server: LocalShareServer(), storageDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), interfaces: { [] }
        )
        defer { manager.stopAll() }
        await #expect(throws: LocalShareError.noNetworkAddress) {
            try await manager.share(fileURL: try makeFile(), expiry: .oneHour, maxDownloads: nil)
        }
        #expect(manager.activeShares.isEmpty)
    }

    @Test func localNetworkLinksAreNeverShortened() throws {
        let outcome = UploadOutcome(url: try #require(URL(string: "http://192.168.1.2:5000/t/a.png")), deletionURL: nil, uploaderID: nil, s3Key: nil, isLocalNetwork: true)
        #expect(!outcome.canBeShortened)
        #expect(outcome.deliveredURL != nil)
    }
}
