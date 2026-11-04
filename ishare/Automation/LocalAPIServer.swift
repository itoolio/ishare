import Defaults
import Foundation
import ishareCore
import Network

@MainActor
enum LocalAPIRouter {
    static func reply(to request: LocalAPIRequest, token: String, server: CommandLineServer) async -> Data {
        guard request.isAuthorized(token: token) else {
            return LocalAPIRequest.response(status: 401, body: Data(#"{"success":false,"error":"Missing or wrong token"}"#.utf8))
        }
        guard let name = request.toolName else {
            return LocalAPIRequest.response(status: 404, body: Data(#"{"success":false,"error":"Unknown path"}"#.utf8))
        }
        guard request.method == "GET" || request.method == "POST" else {
            return LocalAPIRequest.response(status: 405, body: Data(#"{"success":false,"error":"Use GET or POST"}"#.utf8))
        }
        let command: CLICommand
        do {
            command = try MCPTools.command(for: name, arguments: arguments(of: request))
        } catch {
            let status = MCPTools.definitions.contains { $0["name"] as? String == name } ? 400 : 404
            return LocalAPIRequest.response(status: status, body: Data(CLIOutput.json(for: .failure(UUID(), error.description)).utf8))
        }
        let response = await server.response(to: CLIRequest(id: UUID(), command: command))
        return LocalAPIRequest.response(status: response.success ? 200 : 422, body: Data(CLIOutput.json(for: response).utf8))
    }

    static let booleanKeys: Set<String> = ["upload", "contact_sheet"]

    static func arguments(of request: LocalAPIRequest) -> [String: Any] {
        if request.method == "POST", !request.body.isEmpty, let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
            return object
        }
        var arguments: [String: Any] = [:]
        for (key, value) in request.query {
            if booleanKeys.contains(key) {
                arguments[key] = ["1", "true", "yes"].contains(value.lowercased())
            } else {
                arguments[key] = Int(value) ?? value
            }
        }
        if let path = request.query["path"] {
            arguments["paths"] = [path]
        }
        return arguments
    }
}

final class LocalAPIServer: @unchecked Sendable {
    @MainActor static let shared = LocalAPIServer()

    private let queue = DispatchQueue(label: "dev.adrian.ishare.LocalAPI")
    private var listener: NWListener?

    @MainActor func refresh() {
        stop()
        guard Defaults[.localAPIEnabled], !ScreenshotMode.isActive else { return }
        if Defaults[.localAPIToken].isEmpty {
            Defaults[.localAPIToken] = LocalAPIRequest.makeToken()
        }
        start(port: UInt16(clamping: Defaults[.localAPIPort]))
    }

    @MainActor func activate() {
        refresh()
        Task { @MainActor in
            for await _ in Defaults.updates([.localAPIEnabled, .localAPIPort, .localAPIToken], initial: false) {
                refresh()
            }
        }
    }

    var boundPort: UInt16? {
        listener?.port?.rawValue
    }

    func start(port: UInt16) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        guard let listener = try? NWListener(using: parameters) else {
            Log.app.error("The local API couldn't listen on port \(port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                Log.app.error("The local API stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        Log.app.info("Local API listening on 127.0.0.1:\(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
        queue.asyncAfter(deadline: .now() + 30) { [weak connection] in connection?.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch LocalAPIRequest.parse(buffer) {
            case .incomplete where error == nil && !isComplete:
                self?.receive(on: connection, buffer: buffer)
            case let .complete(request):
                Task { @MainActor in
                    let reply = await LocalAPIRouter.reply(to: request, token: Defaults[.localAPIToken], server: CommandLineServer.shared)
                    connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
                }
            default:
                connection.send(content: LocalAPIRequest.response(status: 400, body: Data()), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
