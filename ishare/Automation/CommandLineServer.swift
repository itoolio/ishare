import Foundation

@MainActor
final class CommandLineServer {
    static let shared: CommandLineServer =
        if AutomationTestMode.isActive {
            CommandLineServer(mailbox: AutomationTestMode.mailboxDirectory.map(CLIMailbox.init(directory:)), actions: AutomationTestActions.shared)
        } else {
            CommandLineServer(mailbox: CLIAppGroup.mailboxDirectory.map(CLIMailbox.init(directory:)), actions: LiveAutomationActions.shared)
        }

    let mailbox: CLIMailbox?
    weak var actions: (any AutomationActions)?
    var fileAccess: URLSchemeFileAccess = .live
    var postsNotifications = true
    private var inFlight: Set<UUID> = []

    init(mailbox: CLIMailbox?, actions: any AutomationActions) {
        self.mailbox = mailbox
        self.actions = actions
    }

    func handle(_ id: UUID) async {
        guard let mailbox else {
            Log.app.error("The command-line mailbox isn't available")
            return
        }
        guard inFlight.insert(id).inserted else { return }
        defer { inFlight.remove(id) }
        mailbox.removeStaleFiles()
        let request: CLIRequest
        do {
            request = try mailbox.takeRequest(id)
        } catch {
            Log.app.error("Rejected command-line request \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            reply(CLIResponse.failure(id, String(describing: error)), to: mailbox)
            return
        }
        Log.app.info("Running command-line request \(id.uuidString, privacy: .public)")
        reply(await response(to: request), to: mailbox)
    }

    func response(to request: CLIRequest) async -> CLIResponse {
        guard let actions else { return .failure(request.id, "ishare isn't ready") }
        var response = CLIResponse(id: request.id, success: true)
        switch request.command {
        case let .upload(files, uploader):
            var accepted: [URL] = []
            var rejected: [CLIUploadResult] = []
            for path in files.prefix(URLSchemeParser.maximumFiles) {
                switch URLSchemeParser.validatedFile(path, fileAccess: fileAccess) {
                case let .success(url): accepted.append(url)
                case let .failure(error): rejected.append(CLIUploadResult(file: path, error: error.message))
                }
            }
            let uploaded = accepted.isEmpty ? [] : await actions.upload(accepted, uploader: uploader)
            response.payload.uploads = uploaded + rejected
        case let .capture(mode, upload):
            switch await actions.capture(mode, upload: upload) {
            case let .success(result): response.payload.capture = result
            case let .failure(error): return .failure(request.id, error.message)
            }
        case let .record(action):
            let recording = await actions.record(action, gif: false, region: false)
            response.payload.recording = recording
            response.payload.message = recording ? "Recording" : "Not recording"
        case .listUploaders:
            response.payload.uploaders = actions.uploaders()
        case let .history(limit):
            response.payload.history = actions.history(limit: limit)
        }
        return response
    }

    private func reply(_ response: CLIResponse, to mailbox: CLIMailbox) {
        do {
            try mailbox.write(response)
        } catch {
            Log.app.error("Writing the command-line response failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if postsNotifications {
            DistributedNotificationCenter.default().postNotificationName(
                CLIAppGroup.notificationName, object: response.id.uuidString, userInfo: nil, deliverImmediately: true
            )
        }
    }
}
