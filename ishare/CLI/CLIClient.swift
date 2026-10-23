import Foundation

struct CLIClient: Sendable {
    let mailbox: CLIMailbox
    let launch: @Sendable (URL) async throws -> Void
    var pollInterval: Duration = .milliseconds(50)
    var makeID: @Sendable () -> UUID = { UUID() }

    func send(_ command: CLICommand, timeout: TimeInterval) async throws -> CLIResponse {
        let request = CLIRequest(id: makeID(), command: command)
        try mailbox.write(request)
        do {
            try await launch(CLIAppGroup.requestURL(for: request.id))
        } catch {
            mailbox.removeRequest(request.id)
            throw CLIProtocolError.launchFailed(String(describing: error))
        }
        return try await waitForResponse(to: request.id, timeout: timeout)
    }

    func waitForResponse(to id: UUID, timeout: TimeInterval) async throws -> CLIResponse {
        let deadline = ContinuousClock.now + .milliseconds(Int(timeout * 1000))
        while ContinuousClock.now < deadline {
            if let response = mailbox.takeResponse(for: id) {
                return response
            }
            try await Task.sleep(for: pollInterval)
        }
        mailbox.removeRequest(id)
        throw CLIProtocolError.timedOut(timeout)
    }
}
