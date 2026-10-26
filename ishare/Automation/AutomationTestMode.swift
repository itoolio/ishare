import AppKit
import Defaults
import Foundation
import ishareCore

enum AutomationTestMode {
    static let flag = "-ishareAutomationTestMode"
    static let directoryFlag = "-ishareAutomationDirectory"
    static let replyIDParameter = "automation-test-id"
    static let stubUploaderName = "Automation Stub"
    static let stubPublicHost = "stub.ishare.test"
    static let stubUploaderID = UUID(uuidString: "5E1F7E57-0000-4000-8000-000000000031")!

    nonisolated static func isEnabled(arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }

    nonisolated static var isActive: Bool {
        isEnabled(arguments: ProcessInfo.processInfo.arguments)
    }

    nonisolated static func directory(arguments: [String], temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL {
        if let index = arguments.firstIndex(of: directoryFlag), arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/") {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
        }
        return temporaryDirectory.appending(path: "ishare-automation", directoryHint: .isDirectory)
    }

    nonisolated static var directory: URL? {
        isActive ? directory(arguments: ProcessInfo.processInfo.arguments) : nil
    }

    nonisolated static func mailbox(in directory: URL) -> URL { directory.appending(path: "mailbox", directoryHint: .isDirectory) }
    nonisolated static func replies(in directory: URL) -> URL { directory.appending(path: "replies", directoryHint: .isDirectory) }
    nonisolated static func uploads(in directory: URL) -> URL { directory.appending(path: "uploads", directoryHint: .isDirectory) }
    nonisolated static func captures(in directory: URL) -> URL { directory.appending(path: "captures", directoryHint: .isDirectory) }

    nonisolated static var mailboxDirectory: URL? { directory.map(mailbox(in:)) }

    nonisolated static func stubUploader(uploadsDirectory: URL) -> CustomUploader {
        CustomUploader.folder(
            id: stubUploaderID, name: stubUploaderName,
            destination: FolderDestination(path: uploadsDirectory.path, publicURL: "https://\(stubPublicHost)/{{path}}")
        )
    }

    nonisolated static func replyID(for url: URL) -> String? {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == replyIDParameter }?.value
        guard let value, !value.isEmpty, value.count <= 64, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return value
    }

    @MainActor static func prepare() {
        guard let directory else { return }
        let manager = FileManager.default
        for folder in [mailbox(in: directory), replies(in: directory), uploads(in: directory), captures(in: directory)] {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let stub = stubUploader(uploadsDirectory: uploads(in: directory))
        Defaults[.savedCustomUploaders] = []
        Defaults[.savedLocalUploaders] = [stub]
        Defaults[.activeCustomUploader] = stub.id
        Defaults[.uploadType] = .CUSTOM
        Defaults[.uploadDestination] = .custom(stub.id)
        Defaults[.additionalUploadDestinations] = []
        Defaults[.capturePath] = captures(in: directory).path + "/"
        Defaults[.uploadMedia] = true
        Defaults[.saveToDisk] = true
        Defaults[.copyToClipboard] = false
        Defaults[.copyURLAfterUpload] = false
        Defaults[.copyImageToClipboard] = false
        Defaults[.openURLAfterUpload] = false
        Defaults[.openInFinder] = false
        Defaults[.openEditorAfterCapture] = false
        Defaults[.builtInShare] = SharingPreferences(airdrop: false, photos: false, messages: false, mail: false)
        Defaults[.captureSound] = .none
        Defaults[.uploadCompleteSound] = .none
        Defaults[.captureDelay] = .off
        Defaults[.generateAltText] = false
        Defaults[.redactBeforeUpload] = false
        Defaults[.urlShortener] = .none
        Defaults[.resultPresentation] = .toast
        Defaults[.toastTimeout] = 1
        Defaults[.uploadHistory] = []
        AutomationTestActions.shared.reset()
        let ready = AutomationReady(pid: ProcessInfo.processInfo.processIdentifier, version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        write(ready, to: directory.appending(path: "ready.json"))
        Log.app.info("Automation test mode is ready in \(directory.path, privacy: .public)")
    }

    @MainActor static func record(_ url: URL, outcome: URLSchemeOutcome) {
        guard let directory else { return }
        let reply = AutomationReply(url: url, outcome: outcome, callback: AutomationTestActions.shared.takeCallback(), state: AutomationTestActions.shared)
        let name = replyID(for: url) ?? "unnamed-\(Int(Date().timeIntervalSince1970 * 1000))"
        write(reply, to: replies(in: directory).appending(path: "\(name).json"))
    }

    private static func write(_ value: some Encodable, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try CLICoding.encode(value, pretty: true).write(to: url, options: .atomic)
        } catch {
            Log.app.error("Writing the automation reply failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct AutomationReady: Codable, Equatable {
    let pid: Int32
    let version: String?
}

struct AutomationReply: Codable, Equatable {
    var action: String
    var outcome: String
    var link: String?
    var errorCode: Int?
    var errorMessage: String?
    var callback: String?
    var recording: Bool
    var opened: [String]

    @MainActor init(url: URL, outcome: URLSchemeOutcome, callback: URL?, state: AutomationTestActions) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        action = ([components?.host ?? ""] + (components?.path.split(separator: "/").map(String.init) ?? [])).filter { !$0.isEmpty }.joined(separator: "/")
        switch outcome {
        case let .completed(link):
            self.outcome = "completed"
            self.link = link
        case let .rejected(error):
            self.outcome = "rejected"
            errorCode = error.code
            errorMessage = error.message
        case let .failed(error):
            self.outcome = error == .cancelled ? "cancelled" : "failed"
            errorMessage = error.message
        }
        self.callback = callback?.absoluteString
        recording = state.isRecording
        opened = state.opened
    }
}

@MainActor
final class AutomationTestActions: AutomationActions {
    static let shared = AutomationTestActions(live: LiveAutomationActions.shared)

    let live: LiveAutomationActions
    private(set) var isRecording = false
    private(set) var opened: [String] = []
    private var lastCallback: URL?

    init(live: LiveAutomationActions) {
        self.live = live
    }

    func reset() {
        isRecording = false
        opened = []
        lastCallback = nil
    }

    func takeCallback() -> URL? {
        defer { lastCallback = nil }
        return lastCallback
    }

    func capture(_ mode: CLICaptureMode, upload: Bool) async -> Result<CLICaptureResult, AutomationError> {
        await live.capture(mode, upload: upload)
    }

    func captureWithAfterCaptureSteps(_ mode: CLICaptureMode) async -> String? {
        await live.captureWithAfterCaptureSteps(mode)
    }

    func record(_ action: CLIRecordAction, gif _: Bool, region _: Bool, preset: String?) async -> Result<Bool, AutomationError> {
        if let preset, RecordingPresets.preset(named: preset) == nil {
            return .failure(.failed(String(format: "No recording preset named “%@”".localized(), preset)))
        }
        switch action {
        case .start: isRecording = true
        case .stop: isRecording = false
        case .toggle: isRecording.toggle()
        case .pause, .resume: break
        }
        return .success(isRecording)
    }

    func upload(_ files: [URL], uploader: String?) async -> [CLIUploadResult] {
        await live.upload(files, uploader: uploader)
    }

    func selectUploader(named name: String) -> Bool {
        live.selectUploader(named: name)
    }

    func uploaders() -> [CLIUploaderInfo] {
        live.uploaders()
    }

    func history(limit: Int) -> [CLIHistoryEntry] {
        live.history(limit: limit)
    }

    func open(_ target: AutomationOpenTarget) {
        switch target {
        case .history:
            opened.append("history")
            live.open(.history)
        case let .settings(pane):
            opened.append(["settings", pane].compactMap { $0 }.joined(separator: ":"))
            live.open(.settings(pane))
        case .editor:
            opened.append("editor")
        }
    }

    func openCallback(_ url: URL) {
        lastCallback = url
    }
}
