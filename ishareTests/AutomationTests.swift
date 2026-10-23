import Defaults
import Foundation
import Testing
@testable import ishare

@MainActor
final class FakeAutomationActions: AutomationActions {
    var calls: [String] = []
    var openedCallbacks: [URL] = []
    var captureResult: Result<CLICaptureResult, AutomationError> = .success(CLICaptureResult(file: "/tmp/shot.png", link: "https://example.com/shot.png"))
    var afterCaptureLink: String? = "https://example.com/flow.png"
    var uploadLinks: [String: String] = [:]
    var recording = false
    var knownUploaders = ["Imgur", "My Server"]

    func capture(_ mode: CLICaptureMode, upload: Bool) async -> Result<CLICaptureResult, AutomationError> {
        calls.append("capture \(mode.rawValue) upload=\(upload)")
        return captureResult
    }

    func captureWithAfterCaptureSteps(_ mode: CLICaptureMode) async -> String? {
        calls.append("flow \(mode.rawValue)")
        return afterCaptureLink
    }

    func record(_ action: CLIRecordAction, gif: Bool, region: Bool) async -> Bool {
        calls.append("record \(action.rawValue) gif=\(gif) region=\(region)")
        switch action {
        case .start: recording = true
        case .stop: recording = false
        case .toggle: recording.toggle()
        }
        return recording
    }

    func upload(_ files: [URL], uploader: String?) async -> [CLIUploadResult] {
        calls.append("upload \(files.map(\.lastPathComponent).joined(separator: ",")) via \(uploader ?? "default")")
        return files.map { file in
            if let link = uploadLinks[file.lastPathComponent] {
                return CLIUploadResult(file: file.path, link: link)
            }
            return CLIUploadResult(file: file.path, error: "Upload failed")
        }
    }

    func selectUploader(named name: String) -> Bool {
        calls.append("select \(name)")
        return knownUploaders.contains(name)
    }

    func uploaders() -> [CLIUploaderInfo] {
        knownUploaders.enumerated().map { CLIUploaderInfo(id: "u\($0.offset)", name: $0.element, kind: "custom", selected: $0.offset == 0) }
    }

    func history(limit: Int) -> [CLIHistoryEntry] {
        (0 ..< 30).prefix(limit).map { CLIHistoryEntry(link: "https://example.com/\($0).png", title: "\($0).png") }
    }

    func open(_ target: AutomationOpenTarget) {
        calls.append("open \(target)")
    }

    func openCallback(_ url: URL) {
        openedCallbacks.append(url)
    }
}

struct TemporaryFiles {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "AutomationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data("data".utf8).write(to: url)
        return url.resolvingSymlinksInPath()
    }
}

struct URLSchemeParserTests {
    let anything = URLSchemeFileAccess { _ in true }
    let nothing = URLSchemeFileAccess { _ in false }

    func parse(_ string: String, access: URLSchemeFileAccess? = nil) -> Result<URLSchemeRequest, URLSchemeError> {
        URLSchemeParser.parse(URL(string: string)!, fileAccess: access ?? anything)
    }

    func command(_ string: String) -> URLSchemeCommand? {
        try? parse(string).get().command
    }

    @Test(arguments: [
        ("ishare://capture/region", CLICaptureMode.region), ("ishare://capture/window", .window), ("ishare://capture/screen", .screen),
        ("ishare://capture/scrolling", .scrolling), ("ishare://capture?type=window", .window), ("ishare://capture", .region),
        ("ishare://x-callback-url/capture/screen", .screen), ("ISHARE://Capture/Region", .region),
    ])
    func parsesCaptureActions(url: String, mode: CLICaptureMode) {
        #expect(command(url) == .capture(mode))
    }

    @Test func parsesRecordActions() {
        #expect(command("ishare://record/start") == .record(.start, gif: false, region: false))
        #expect(command("ishare://record/stop") == .record(.stop, gif: false, region: false))
        #expect(command("ishare://record/toggle?gif=1&region=true") == .record(.toggle, gif: true, region: true))
        #expect(command("ishare://record?gif=0") == .record(.toggle, gif: false, region: false))
        #expect(parse("ishare://record/pause") == .failure(.invalidValue(parameter: "record", value: "pause")))
    }

    @Test func parsesUploadsOfReadablePaths() throws {
        let result = parse("ishare://upload?path=/Users/me/Pictures/a%20b.png&path=/tmp/c.png")
        #expect(try result.get().command == .upload([URL(fileURLWithPath: "/Users/me/Pictures/a b.png"), URL(fileURLWithPath: "/tmp/c.png").resolvingSymlinksInPath()]))
    }

    @Test func acceptsTheLegacyShareExtensionFormat() throws {
        let file = URL(fileURLWithPath: "/Users/me/Library/Group Containers/x/tmp/A.png")
        let encoded = file.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        #expect(command("ishare://upload?file=\(encoded)") == .upload([file]))
    }

    @Test func rejectsPathsTheAppCannotRead() {
        #expect(parse("ishare://upload?path=/etc/master.passwd", access: nothing) == .failure(.unreadablePath("/etc/master.passwd")))
        #expect(parse("ishare://upload?path=relative/a.png") == .failure(.unreadablePath("relative/a.png")))
        #expect(parse("ishare://upload") == .failure(.missingParameter("path")))
        let many = (0 ... URLSchemeParser.maximumFiles).map { "path=/tmp/\($0).png" }.joined(separator: "&")
        #expect(parse("ishare://upload?\(many)") == .failure(.tooManyFiles(URLSchemeParser.maximumFiles + 1)))
    }

    @Test func checksRealFilesWithTheLiveAccessPolicy() throws {
        let files = try TemporaryFiles()
        let file = try files.file("real.png")
        #expect(URLSchemeParser.validatedFile(file.path, fileAccess: .live) == .success(file))
        #expect(URLSchemeParser.validatedFile(files.directory.path, fileAccess: .live) == .failure(.unreadablePath(files.directory.path)))
        #expect(URLSchemeParser.validatedFile(files.directory.appending(path: "missing.png").path, fileAccess: .live) != .success(file))
    }

    @Test func parsesUploaderSelectionAndOpenTargets() {
        #expect(command("ishare://uploader/select?name=My%20Server") == .selectUploader("My Server"))
        #expect(parse("ishare://uploader/select") == .failure(.missingParameter("name")))
        #expect(parse("ishare://uploader/delete?name=a") == .failure(.unknownAction("uploader/delete")))
        #expect(command("ishare://open/history") == .open(.history))
        #expect(command("ishare://open/settings?pane=Advanced") == .open(.settings("advanced")))
        #expect(command("ishare://open/editor") == .open(.editor))
        #expect(parse("ishare://open/finder") == .failure(.invalidValue(parameter: "open", value: "finder")))
        #expect(parse("ishare://launch-missiles") == .failure(.unknownAction("launch-missiles")))
        #expect(parse("https://capture/region") == .failure(.unsupportedScheme("https")))
    }

    @Test func parsesCommandLineRequests() {
        let id = UUID()
        #expect(command("ishare://cli?id=\(id.uuidString)") == .commandLine(id))
        #expect(parse("ishare://cli?id=nope") == .failure(.invalidValue(parameter: "id", value: "nope")))
        #expect(parse("ishare://cli") == .failure(.missingParameter("id")))
    }

    @Test func parsesCallbacksAndRejectsWebOrFileCallbacks() throws {
        let request = try parse("ishare://capture/region?x-success=raycast%3A%2F%2Fdone&x-error=shortcuts%3A%2F%2Fx-callback-url%2Ferr&x-cancel=app%3A%2F%2Fc").get()
        #expect(request.callback.success == URL(string: "raycast://done"))
        #expect(request.callback.error == URL(string: "shortcuts://x-callback-url/err"))
        #expect(request.callback.cancel == URL(string: "app://c"))
        #expect(parse("ishare://capture/region?x-success=https%3A%2F%2Fevil.example%2F") == .failure(.invalidCallback("x-success")))
        #expect(parse("ishare://capture/region?x-error=file%3A%2F%2F%2Ftmp") == .failure(.invalidCallback("x-error")))
        #expect(parse("ishare://capture/region?x-success=javascript%3Aalert(1)") == .failure(.invalidCallback("x-success")))
    }

    @Test func appendsTheLinkAndErrorDetailsToCallbacks() throws {
        let callback = XCallback(success: URL(string: "app://done?keep=1"), error: URL(string: "app://failed"))
        #expect(callback.successURL(link: "https://example.com/a b.png")?.absoluteString == "app://done?keep=1&link=https://example.com/a%20b.png")
        #expect(callback.successURL(link: nil)?.absoluteString == "app://done?keep=1")
        #expect(callback.errorURL(code: 5, message: "Nope")?.absoluteString == "app://failed?errorCode=5&errorMessage=Nope")
    }

    @Test func redactsCallbacksInLogs() {
        let url = URL(string: "ishare://capture/region?x-success=app%3A%2F%2Fsecret")!
        #expect(!URLSchemeRouter.redacted(url).contains("secret"))
        #expect(URLSchemeRouter.redacted(url).contains("capture"))
    }
}

@MainActor
struct URLSchemeRouterTests {
    let actions = FakeAutomationActions()

    func router() throws -> URLSchemeRouter {
        let files = try TemporaryFiles()
        let server = CommandLineServer(mailbox: CLIMailbox(directory: files.directory), actions: actions)
        server.postsNotifications = false
        let router = URLSchemeRouter(actions: actions, commandLine: server)
        router.fileAccess = URLSchemeFileAccess { _ in true }
        return router
    }

    @Test func runsCaptureAndCallsBackWithTheLink() async throws {
        let outcome = try await router().handle(URL(string: "ishare://capture/window?x-success=app%3A%2F%2Fok")!)
        #expect(outcome == .completed(link: "https://example.com/flow.png"))
        #expect(actions.calls == ["flow window"])
        #expect(actions.openedCallbacks.map(\.absoluteString) == ["app://ok?link=https://example.com/flow.png"])
    }

    @Test func routesRecordingUploaderAndOpenActions() async throws {
        let router = try router()
        await router.handle(URL(string: "ishare://record/start")!)
        await router.handle(URL(string: "ishare://record/stop")!)
        await router.handle(URL(string: "ishare://uploader/select?name=My%20Server")!)
        await router.handle(URL(string: "ishare://open/history")!)
        #expect(actions.calls == ["record start gif=false region=false", "record stop gif=false region=false", "select My Server", "open history"])
    }

    @Test func reportsFailuresToTheErrorCallback() async throws {
        let outcome = try await router().handle(URL(string: "ishare://uploader/select?name=Nope&x-error=app%3A%2F%2Ferr")!)
        #expect(outcome == .failed(.failed("No uploader named “Nope”")))
        #expect(actions.openedCallbacks.first?.absoluteString.hasPrefix("app://err?errorCode=100&errorMessage=") == true)
    }

    @Test func rejectsInvalidInputWithoutRunningAnything() async throws {
        let outcome = try await router().handle(URL(string: "ishare://upload?x-error=app%3A%2F%2Ferr")!)
        #expect(outcome == .rejected(.missingParameter("path")))
        #expect(actions.calls.isEmpty)
        #expect(actions.openedCallbacks.map(\.absoluteString) == ["app://err?errorCode=3&errorMessage=Missing%20parameter%20path"])
    }

    @Test func uploadsAndReturnsTheLinks() async throws {
        actions.uploadLinks = ["a.png": "https://example.com/a.png", "b.png": "https://example.com/b.png"]
        let outcome = try await router().handle(URL(string: "ishare://upload?path=/tmp/a.png&path=/tmp/b.png&x-success=app%3A%2F%2Fok")!)
        #expect(outcome == .completed(link: "https://example.com/a.png\nhttps://example.com/b.png"))
        #expect(actions.calls == ["upload a.png,b.png via default"])
    }

    @Test func cancelledCapturesUseTheCancelCallback() async throws {
        actions.afterCaptureLink = nil
        let outcome = try await router().handle(URL(string: "ishare://capture/region?x-success=app%3A%2F%2Fok")!)
        #expect(outcome == .completed(link: nil))
        #expect(actions.openedCallbacks.map(\.absoluteString) == ["app://ok"])
    }
}

struct CLIArgumentTests {
    func run(_ arguments: [String]) throws -> CLIInvocation {
        guard case let .run(invocation) = try CLIArguments.parse(arguments, workingDirectory: "/Users/me/Desktop") else {
            throw CLIArgumentError.missingCommand
        }
        return invocation
    }

    func error(_ arguments: [String]) -> CLIArgumentError? {
        do {
            _ = try CLIArguments.parse(arguments, workingDirectory: "/tmp")
            return nil
        } catch {
            return error
        }
    }

    @Test func parsesUploadsWithAbsoluteAndRelativePaths() throws {
        let invocation = try run(["upload", "a.png", "../b.mov", "/tmp/c.txt", "--uploader", "My Server", "--json"])
        #expect(invocation.command == .upload(files: ["/Users/me/Desktop/a.png", "/Users/me/b.mov", "/tmp/c.txt"], uploader: "My Server"))
        #expect(invocation.json)
        #expect(invocation.timeout == CLIArguments.defaultTimeout)
        #expect(try run(["upload", "--uploader=Imgur", "x.png"]).command == .upload(files: ["/Users/me/Desktop/x.png"], uploader: "Imgur"))
        #expect(try run(["upload", "--", "--weird.png"]).command == .upload(files: ["/Users/me/Desktop/--weird.png"], uploader: nil))
    }

    @Test func parsesCaptureRecordUploadersAndHistory() throws {
        #expect(try run(["capture", "region"]).command == .capture(mode: .region, upload: false))
        let capture = try run(["capture", "Window", "--upload", "--timeout", "30"])
        #expect(capture.command == .capture(mode: .window, upload: true))
        #expect(capture.timeout == 30)
        #expect(try run(["capture", "screen"]).timeout == CLIArguments.interactiveTimeout)
        #expect(try run(["record", "start"]).command == .record(.start))
        #expect(try run(["record", "stop"]).command == .record(.stop))
        #expect(try run(["uploaders", "list", "--json"]).command == .listUploaders)
        #expect(try run(["history"]).command == .history(limit: 20))
        #expect(try run(["history", "--limit", "5"]).command == .history(limit: 5))
        #expect(try run(["history", "-n", "9999"]).command == .history(limit: 500))
    }

    @Test func reportsUsageErrors() {
        #expect(error([]) == .missingCommand)
        #expect(error(["frobnicate"]) == .unknownCommand("frobnicate"))
        #expect(error(["upload"]) == .missingArgument("file"))
        #expect(error(["capture"]) == .missingArgument("capture mode (region, window, screen or scrolling)"))
        #expect(error(["capture", "everything"]) == .invalidValue(option: "capture", value: "everything"))
        #expect(error(["capture", "region", "extra"]) == .unexpectedArgument("extra"))
        #expect(error(["record", "pause"]) == .invalidValue(option: "record", value: "pause"))
        #expect(error(["uploaders"]) == .missingArgument("uploaders subcommand (list)"))
        #expect(error(["history", "--limit", "0"]) == .invalidValue(option: "--limit", value: "0"))
        #expect(error(["history", "--limit"]) == .missingValue("--limit"))
        #expect(error(["history", "--upload"]) == .unknownOption("--upload"))
        #expect(error(["capture", "region", "--uploader", "x"]) == .unknownOption("--uploader"))
        #expect(error(["upload", "a", "--bogus"]) == .unknownOption("--bogus"))
        #expect(error(["upload", "a", "--timeout", "-1"]) == .invalidValue(option: "--timeout", value: "-1"))
    }

    @Test func showsHelpAndVersion() throws {
        #expect(try CLIArguments.parse(["--help"]) == .help(CLIArguments.usage))
        #expect(try CLIArguments.parse(["upload", "-h"]) == .help(CLIArguments.usage))
        #expect(try CLIArguments.parse(["help"]) == .help(CLIArguments.usage))
        #expect(try CLIArguments.parse(["--version"]) == .version)
    }
}

struct CLIProtocolTests {
    @Test func roundTripsRequestsAndResponses() throws {
        let commands: [CLICommand] = [
            .upload(files: ["/a.png"], uploader: nil), .upload(files: ["/a.png", "/b.png"], uploader: "S3"), .capture(mode: .scrolling, upload: true),
            .record(.toggle), .listUploaders, .history(limit: 3),
        ]
        for command in commands {
            let request = CLIRequest(id: UUID(), command: command, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
            #expect(try CLICoding.decode(CLIRequest.self, from: CLICoding.encode(request)) == request)
        }
        var response = CLIResponse(id: UUID(), success: true)
        response.payload.uploads = [CLIUploadResult(file: "/a.png", link: "https://x/a.png"), CLIUploadResult(file: "/b.png", error: "nope")]
        response.payload.history = [CLIHistoryEntry(link: "https://x/a.png", title: "a.png", date: Date(timeIntervalSince1970: 1_800_000_000))]
        #expect(try CLICoding.decode(CLIResponse.self, from: CLICoding.encode(response)) == response)
    }

    @Test func formatsTextAndJSONOutput() throws {
        var response = CLIResponse(id: UUID(), success: true)
        response.payload.uploads = [CLIUploadResult(file: "/a.png", link: "https://x/a.png"), CLIUploadResult(file: "/b.png", error: "nope")]
        #expect(CLIOutput.text(for: response, command: .upload(files: [], uploader: nil)) == "https://x/a.png")
        #expect(CLIOutput.errors(for: response) == ["/b.png: nope"])
        #expect(CLIOutput.exitCode(for: response) == 1)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(CLIOutput.json(for: response).utf8)) as? [String: Any])
        #expect(json["success"] as? Bool == true)
        let uploads = (json["payload"] as? [String: Any])?["uploads"] as? [[String: Any]]
        #expect(uploads?.first?["link"] as? String == "https://x/a.png")

        var uploaders = CLIResponse(id: UUID(), success: true)
        uploaders.payload.uploaders = [CLIUploaderInfo(id: "imgur", name: "Imgur", kind: "imgur", selected: true), CLIUploaderInfo(id: "2", name: "S3", kind: "s3", selected: false)]
        #expect(CLIOutput.text(for: uploaders, command: .listUploaders) == "* Imgur (imgur)\n  S3 (s3)")
        #expect(CLIOutput.exitCode(for: .failure(UUID(), "x")) == 1)
    }

    @Test func matchesResponsesToTheirRequestID() throws {
        let files = try TemporaryFiles()
        let mailbox = CLIMailbox(directory: files.directory)
        let mine = UUID()
        let other = UUID()
        try mailbox.write(CLIResponse(id: other, success: true))
        #expect(mailbox.takeResponse(for: mine) == nil)
        try FileManager.default.copyItem(at: mailbox.responseFile(for: other), to: mailbox.responseFile(for: mine))
        #expect(mailbox.takeResponse(for: mine) == nil)
        try mailbox.write(CLIResponse(id: mine, success: true))
        #expect(mailbox.takeResponse(for: mine)?.id == mine)
        #expect(mailbox.takeResponse(for: mine) == nil)
        #expect(mailbox.takeResponse(for: other)?.id == other)
    }

    @Test func rejectsRequestFilesWithAnotherID() throws {
        let files = try TemporaryFiles()
        let mailbox = CLIMailbox(directory: files.directory)
        let request = CLIRequest(id: UUID(), command: .listUploaders)
        try mailbox.write(request)
        let forged = UUID()
        try FileManager.default.moveItem(at: mailbox.requestFile(for: request.id), to: mailbox.requestFile(for: forged))
        #expect(throws: CLIProtocolError.mismatchedRequest) { try mailbox.takeRequest(forged) }
        #expect(!FileManager.default.fileExists(atPath: mailbox.requestFile(for: forged).path))
    }

    @Test func removesStaleMailboxFiles() throws {
        let files = try TemporaryFiles()
        let mailbox = CLIMailbox(directory: files.directory)
        try mailbox.write(CLIRequest(id: UUID(), command: .listUploaders))
        mailbox.removeStaleFiles(now: Date().addingTimeInterval(CLIMailbox.staleAge + 60))
        #expect((try FileManager.default.contentsOfDirectory(atPath: mailbox.requestsDirectory.path)).isEmpty)
    }
}

@MainActor
struct CommandLineEndToEndTests {
    let actions = FakeAutomationActions()

    func makeSystem() throws -> (client: CLIClient, server: CommandLineServer, files: TemporaryFiles) {
        let files = try TemporaryFiles()
        let mailbox = CLIMailbox(directory: files.directory.appending(path: "CommandLine", directoryHint: .isDirectory))
        let server = CommandLineServer(mailbox: mailbox, actions: actions)
        server.postsNotifications = false
        let router = URLSchemeRouter(actions: actions, commandLine: server)
        let client = CLIClient(mailbox: mailbox, launch: { url in
            Task { @MainActor in
                await router.handle(url)
            }
        })
        return (client, server, files)
    }

    @Test func uploadsThroughTheMailboxAndURLScheme() async throws {
        let (client, server, files) = try makeSystem()
        let readable = try files.file("a.png")
        server.fileAccess = URLSchemeFileAccess { $0 == readable.path }
        actions.uploadLinks = ["a.png": "https://example.com/a.png"]
        let response = try await client.send(.upload(files: [readable.path, "/private/secret.txt"], uploader: "My Server"), timeout: 5)
        #expect(response.success)
        #expect(response.payload.uploads?.map(\.link) == ["https://example.com/a.png", nil])
        #expect(response.payload.uploads?.last?.error == "ishare can't read /private/secret.txt")
        #expect(actions.calls == ["upload a.png via My Server"])
        #expect(CLIOutput.text(for: response, command: .upload(files: [], uploader: nil)) == "https://example.com/a.png")
    }

    @Test func listsUploadersHistoryAndCaptures() async throws {
        let (client, _, _) = try makeSystem()
        let uploaders = try await client.send(.listUploaders, timeout: 5)
        #expect(uploaders.payload.uploaders?.map(\.name) == ["Imgur", "My Server"])
        let history = try await client.send(.history(limit: 3), timeout: 5)
        #expect(history.payload.history?.count == 3)
        let capture = try await client.send(.capture(mode: .region, upload: true), timeout: 5)
        #expect(capture.payload.capture?.link == "https://example.com/shot.png")
        let record = try await client.send(.record(.start), timeout: 5)
        #expect(record.payload.recording == true)
        #expect(actions.calls == ["capture region upload=true", "record start gif=false region=false"])
    }

    @Test func reportsCancelledCaptures() async throws {
        let (client, _, _) = try makeSystem()
        actions.captureResult = .failure(.cancelled)
        let response = try await client.send(.capture(mode: .window, upload: false), timeout: 5)
        #expect(!response.success)
        #expect(response.error == "Cancelled")
    }

    @Test func timesOutWhenTheAppNeverAnswers() async throws {
        let files = try TemporaryFiles()
        let mailbox = CLIMailbox(directory: files.directory)
        let client = CLIClient(mailbox: mailbox, launch: { _ in })
        await #expect(throws: CLIProtocolError.timedOut(0.3)) {
            try await client.send(.listUploaders, timeout: 0.3)
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: mailbox.requestsDirectory.path))?.isEmpty == true)
    }

    @Test func reportsLaunchFailures() async throws {
        struct Unreachable: Error {}
        let files = try TemporaryFiles()
        let client = CLIClient(mailbox: CLIMailbox(directory: files.directory), launch: { _ in throw Unreachable() })
        await #expect(throws: CLIProtocolError.launchFailed("Unreachable()")) {
            try await client.send(.listUploaders, timeout: 1)
        }
    }

    @Test func answersUnknownRequestIDsWithAnError() async throws {
        let (client, server, _) = try makeSystem()
        let id = UUID()
        await server.handle(id)
        let response = try await client.waitForResponse(to: id, timeout: 1)
        #expect(!response.success)
        #expect(actions.calls.isEmpty)
    }
}

@MainActor
struct CommandLineToolInstallerTests {
    @Test func quotesPathsForTheShellAndAppleScript() {
        let tool = URL(fileURLWithPath: "/Applications/ishare's copy.app/Contents/Helpers/ishare")
        #expect(CommandLineToolInstaller.shellCommand(tool: tool) == "sudo mkdir -p '/usr/local/bin' && sudo ln -sf '/Applications/ishare'\\''s copy.app/Contents/Helpers/ishare' '/usr/local/bin/ishare'")
        #expect(CommandLineToolInstaller.appleScriptQuoted("a\"b\\c") == "\"a\\\"b\\\\c\"")
        #expect(CommandLineToolInstaller.administratorScript(tool: URL(fileURLWithPath: "/A/ishare")).hasSuffix("with administrator privileges"))
    }

    @Test func installsAndDetectsTheSymlink() throws {
        let files = try TemporaryFiles()
        let tool = try files.file("ishare-tool")
        let link = files.directory.appending(path: "bin/ishare").path
        #expect(CommandLineToolInstaller.state(tool: tool, link: link) == .notInstalled)
        try CommandLineToolInstaller.install(tool: tool, link: link)
        #expect(CommandLineToolInstaller.state(tool: tool, link: link) == .installed)
        try CommandLineToolInstaller.install(tool: tool, link: link)
        #expect(CommandLineToolInstaller.state(tool: tool, link: link) == .installed)
        let other = try files.file("other")
        #expect(CommandLineToolInstaller.state(tool: other, link: link) == .linkedElsewhere(tool.path))
        #expect(CommandLineToolInstaller.state(tool: files.directory.appending(path: "missing"), link: link) == .missingTool)
    }

    @Test func theAppBundleEmbedsTheTool() {
        #expect(FileManager.default.isExecutableFile(atPath: CommandLineToolInstaller.toolURL().path))
    }
}

@MainActor
struct LatestUploadCommandTests {
    @Test func offersAQRCodeForTheLastUploadedLink() {
        let saved = Defaults[.uploadHistory]
        defer { Defaults[.uploadHistory] = saved }
        Defaults[.uploadHistory] = [HistoryItem(fileUrl: "https://example.com/latest.png", date: Date())]
        let ids = AppCommand.all().map(\.id)
        #expect(ids.contains("history.qr"))
        #expect(!ids.contains("history.localNetwork"))
        Defaults[.uploadHistory] = []
        #expect(!AppCommand.all().map(\.id).contains("history.qr"))
    }
}
