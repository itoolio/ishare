import AppKit
import Defaults
import Foundation
import ishareCore

enum AutomationError: Error, Equatable, Sendable {
    case cancelled
    case failed(String)

    var message: String {
        switch self {
        case .cancelled: "Cancelled"
        case let .failed(message): message
        }
    }
}

@MainActor
protocol AutomationActions: AnyObject {
    func capture(_ mode: CLICaptureMode, upload: Bool) async -> Result<CLICaptureResult, AutomationError>
    func captureWithAfterCaptureSteps(_ mode: CLICaptureMode) async -> String?
    func record(_ action: CLIRecordAction, gif: Bool, region: Bool) async -> Bool
    func upload(_ files: [URL], uploader: String?) async -> [CLIUploadResult]
    func selectUploader(named name: String) -> Bool
    func uploaders() -> [CLIUploaderInfo]
    func history(limit: Int) -> [CLIHistoryEntry]
    func open(_ target: AutomationOpenTarget)
    func openCallback(_ url: URL)
}

extension CLICaptureMode {
    var captureType: CaptureType {
        switch self {
        case .region: .REGION
        case .window: .WINDOW
        case .screen: .SCREEN
        case .scrolling: .SCROLLING
        case .menu: .MENU
        }
    }
}

@MainActor
private final class CapturedFile {
    var url: URL?
}

@MainActor
final class LiveAutomationActions: AutomationActions {
    static let shared = LiveAutomationActions()

    func capture(_ mode: CLICaptureMode, upload: Bool) async -> Result<CLICaptureResult, AutomationError> {
        let captured = CapturedFile()
        await CaptureSession.captureImage(mode.captureType, options: CaptureOptions(resultHandler: { captured.url = $0 }))
        guard let fileURL = captured.url else { return .failure(.cancelled) }
        guard upload else { return .success(CLICaptureResult(file: fileURL.path)) }
        let result = await UploadCoordinator.upload(fileURL: fileURL, localFileURL: fileURL)
        presentToast(for: fileURL)
        switch result {
        case let .success(outcome):
            return .success(CLICaptureResult(file: fileURL.path, link: outcome.deliveredURL?.absoluteString))
        case let .failure(error):
            return .failure(.failed(error.localizedDescription))
        }
    }

    func captureWithAfterCaptureSteps(_ mode: CLICaptureMode) async -> String? {
        let before = Defaults[.uploadHistory].first
        await CaptureSession.captureImage(mode.captureType)
        let latest = Defaults[.uploadHistory].first
        guard let latest, latest != before else { return nil }
        return latest.preferredURL?.absoluteString
    }

    func record(_ action: CLIRecordAction, gif: Bool, region: Bool) async -> Bool {
        let isRecording = CaptureSession.isRecording
        switch action {
        case .start where !isRecording, .toggle where !isRecording:
            CaptureSession.toggleRecording(gif: gif, region: region)
            return true
        case .stop where isRecording, .toggle where isRecording:
            CaptureSession.stopRecording()
            return false
        default:
            return isRecording
        }
    }

    func upload(_ files: [URL], uploader: String?) async -> [CLIUploadResult] {
        var target: UploadTarget?
        if let uploader {
            guard let resolved = AutomationUploaders.target(named: uploader) else {
                return files.map { CLIUploadResult(file: $0.path, error: String(format: "No uploader named “%@”".localized(), uploader)) }
            }
            target = resolved
        }
        var results: [CLIUploadResult] = []
        for file in files {
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            Log.app.info("Automation upload of \(file.path, privacy: .public)")
            switch await UploadCoordinator.upload(fileURL: file, target: target, localFileURL: file) {
            case let .success(outcome):
                results.append(CLIUploadResult(file: file.path, link: outcome.deliveredURL?.absoluteString ?? outcome.url.absoluteString))
                presentToast(for: file)
            case let .failure(error):
                results.append(CLIUploadResult(file: file.path, error: error.localizedDescription))
            }
        }
        return results
    }

    func selectUploader(named name: String) -> Bool {
        guard let destination = AutomationUploaders.destination(named: name) else { return false }
        UploadDestinationSwitcher.select(destination)
        return true
    }

    func uploaders() -> [CLIUploaderInfo] {
        AutomationUploaders.list()
    }

    func history(limit: Int) -> [CLIHistoryEntry] {
        let uploaders = CustomUploader.allCases
        return Defaults[.uploadHistory].prefix(max(0, limit)).map { item in
            CLIHistoryEntry(
                link: item.fileUrl, shortLink: item.shortUrl, title: item.fileName, date: item.date,
                uploader: item.uploaderName(among: uploaders), altText: item.altText, deletionLink: item.deletionUrl,
                localPath: item.existingLocalFileURL?.path
            )
        }
    }

    func open(_ target: AutomationOpenTarget) {
        switch target {
        case .history:
            NSApp.activate(ignoringOtherApps: true)
            openHistoryWindow(uploadHistory: Defaults[.uploadHistory])
        case let .settings(pane):
            MenuController.shared.openSettings(pane: pane.flatMap(SettingsPane.init(rawValue:)))
        case .editor:
            Task { @MainActor in await ImageEditor.chooseAndEdit() }
        }
    }

    func openCallback(_ url: URL) {
        Log.app.info("Opening x-callback \(url.scheme ?? "", privacy: .public)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    private func presentToast(for fileURL: URL) {
        Task { @MainActor in
            await showToast(fileURL: fileURL)
        }
    }
}

@MainActor
enum AutomationUploaders {
    static let localNetworkNames: Set<String> = ["local network", "localnetwork", "lan", "local"]

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func destination(named name: String, destinations: [UploadDestination] = UploadDestinationSwitcher.destinations) -> UploadDestination? {
        let needle = normalized(name)
        return destinations.first { normalized(UploadDestinationSwitcher.title(for: $0)) == needle || UploadDestinationSwitcher.identifier(for: $0) == needle }
    }

    static func target(named name: String) -> UploadTarget? {
        if localNetworkNames.contains(normalized(name)) || normalized(name) == normalized("Local Network".localized()) {
            return .localNetwork
        }
        return destination(named: name).flatMap(UploadCoordinator.target(for:))
    }

    static func list() -> [CLIUploaderInfo] {
        let current = UploadDestinationSwitcher.current
        let uploaders = CustomUploader.allCases
        let configured = UploadDestinationSwitcher.destinations.map { destination in
            let kind: String =
                switch destination {
                case let .custom(id): uploaders.first { $0.id == id }?.kind.rawValue ?? "custom"
                case .localNetwork: "localNetwork"
                case .builtIn: "imgur"
                }
            return CLIUploaderInfo(
                id: UploadDestinationSwitcher.identifier(for: destination), name: UploadDestinationSwitcher.title(for: destination),
                kind: kind, selected: destination == current
            )
        }
        return configured + [CLIUploaderInfo(id: "localnetwork", name: LocalNetworkUploader.displayName, kind: "localNetwork", selected: false)]
    }
}

enum URLSchemeOutcome: Equatable, Sendable {
    case rejected(URLSchemeError)
    case completed(link: String?)
    case failed(AutomationError)
}

@MainActor
final class URLSchemeRouter {
    static let shared = URLSchemeRouter(actions: LiveAutomationActions.shared, commandLine: CommandLineServer.shared)

    let actions: any AutomationActions
    let commandLine: CommandLineServer
    var fileAccess: URLSchemeFileAccess = .live

    init(actions: any AutomationActions, commandLine: CommandLineServer) {
        self.actions = actions
        self.commandLine = commandLine
    }

    @discardableResult
    func handle(_ url: URL) async -> URLSchemeOutcome {
        Log.app.info("Handling URL action \(Self.redacted(url), privacy: .public)")
        switch URLSchemeParser.parse(url, fileAccess: fileAccess) {
        case let .failure(error):
            Log.app.error("Rejected URL action: \(error.message, privacy: .public)")
            if case let .success(callback) = URLSchemeParser.callbacks(from: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []),
                let errorURL = callback.errorURL(code: error.code, message: error.message)
            {
                actions.openCallback(errorURL)
            }
            return .rejected(error)
        case let .success(request):
            let outcome = await perform(request.command)
            switch outcome {
            case let .success(link):
                if let successURL = request.callback.successURL(link: link) {
                    actions.openCallback(successURL)
                }
                return .completed(link: link)
            case let .failure(error):
                Log.app.error("URL action failed: \(error.message, privacy: .public)")
                if error == .cancelled, let cancel = request.callback.cancel {
                    actions.openCallback(cancel)
                } else if let errorURL = request.callback.errorURL(code: 100, message: error.message) {
                    actions.openCallback(errorURL)
                }
                return .failed(error)
            }
        }
    }

    func perform(_ command: URLSchemeCommand) async -> Result<String?, AutomationError> {
        switch command {
        case let .capture(mode):
            return .success(await actions.captureWithAfterCaptureSteps(mode))
        case let .record(action, gif, region):
            _ = await actions.record(action, gif: gif, region: region)
            return .success(nil)
        case let .upload(files):
            let results = await actions.upload(files, uploader: nil)
            if let failure = results.first(where: { $0.error != nil }), results.allSatisfy({ $0.link == nil }) {
                return .failure(.failed(failure.error ?? ""))
            }
            let links = results.compactMap(\.link)
            return .success(links.isEmpty ? nil : links.joined(separator: "\n"))
        case let .selectUploader(name):
            return actions.selectUploader(named: name) ? .success(nil) : .failure(.failed(String(format: "No uploader named “%@”".localized(), name)))
        case let .open(target):
            actions.open(target)
            return .success(nil)
        case let .commandLine(id):
            await commandLine.handle(id)
            return .success(nil)
        }
    }

    nonisolated static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.scheme ?? "" }
        components.queryItems = components.queryItems?.map { item in
            XCallback.parameterNames.contains(item.name.lowercased()) ? URLQueryItem(name: item.name, value: "…") : item
        }
        return components.string ?? ""
    }
}
