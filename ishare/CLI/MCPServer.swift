import Foundation

struct MCPServer: Sendable {
    static let protocolVersion = "2025-06-18"
    static let fallbackVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18"]

    typealias Send = @Sendable (CLICommand, TimeInterval) async throws -> CLIResponse

    let version: String
    let send: Send

    func handle(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8), let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"], let method = message["method"] as? String else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = requested.flatMap { Self.fallbackVersions.contains($0) ? $0 : nil } ?? Self.protocolVersion
            return Self.result(id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "ishare", "version": self.version],
                "instructions": "Take screenshots, capture app windows, upload files and read the upload history of ishare on this Mac.",
            ])
        case "ping":
            return Self.result(id, [:])
        case "tools/list":
            return Self.result(id, ["tools": MCPTools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else { return Self.error(id, code: -32602, message: "Missing tool name") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return Self.result(id, await call(name, arguments: arguments))
        default:
            return Self.error(id, code: -32601, message: "Method not found: \(method)")
        }
    }

    func call(_ name: String, arguments: [String: Any]) async -> [String: Any] {
        let command: CLICommand
        do {
            command = try MCPTools.command(for: name, arguments: arguments)
        } catch {
            return Self.toolResult(text: error.description, isError: true)
        }
        do {
            let timeout = command.isInteractive ? CLIArguments.interactiveTimeout : CLIArguments.defaultTimeout
            let response = try await send(command, timeout)
            return Self.toolResult(text: CLIOutput.json(for: response), isError: !response.success)
        } catch let error as CLIProtocolError {
            return Self.toolResult(text: error.description, isError: true)
        } catch {
            return Self.toolResult(text: error.localizedDescription, isError: true)
        }
    }

    static func toolResult(text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    static func result(_ id: Any, _ result: [String: Any]) -> String? {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static func error(_ id: Any, code: Int, message: String) -> String? {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    static func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

extension CLICommand {
    var isInteractive: Bool {
        switch self {
        case .capture, .captureApp, .record: true
        default: false
        }
    }
}

struct MCPToolError: Error, CustomStringConvertible {
    let description: String
}

enum MCPTools {
    static var definitions: [[String: Any]] {
        [
            tool(
                "capture", "Take a screenshot with ishare. Region, window, scrolling and menu captures wait for the person at the Mac to choose what to capture.",
                properties: [
                    "mode": ["type": "string", "enum": CLICaptureMode.allCases.map(\.rawValue), "description": "What to capture"],
                    "upload": ["type": "boolean", "description": "Upload the capture and return its link"],
                ], required: ["mode"]),
            tool(
                "capture_app", "Capture every window of an app without asking, or of the frontmost app when no name is given.",
                properties: [
                    "app": ["type": "string", "description": "App name or bundle identifier"],
                    "contact_sheet": ["type": "boolean", "description": "Combine the windows into one image"],
                    "upload": ["type": "boolean", "description": "Upload the captures and return their links"],
                ]),
            tool(
                "upload", "Upload files with ishare and return their links.",
                properties: [
                    "paths": ["type": "array", "items": ["type": "string"], "description": "Absolute file paths"],
                    "uploader": ["type": "string", "description": "Name of the uploader to use instead of the active one"],
                ], required: ["paths"]),
            tool("list_uploaders", "List the uploaders configured in ishare and which one is active.", properties: [:]),
            tool(
                "recent_uploads", "List recent uploads from the ishare history, newest first.",
                properties: ["limit": ["type": "integer", "minimum": 1, "maximum": 500, "description": "How many uploads to return (20 by default)"]]),
            tool(
                "record", "Start, stop, pause or resume a screen recording.",
                properties: ["action": ["type": "string", "enum": CLIRecordAction.allCases.map(\.rawValue)]], required: ["action"]),
        ]
    }

    static func tool(_ name: String, _ description: String, properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    static func command(for name: String, arguments: [String: Any]) throws(MCPToolError) -> CLICommand {
        switch name {
        case "capture":
            guard let raw = arguments["mode"] as? String, let mode = CLICaptureMode(rawValue: raw.lowercased()) else {
                throw MCPToolError(description: "mode must be one of \(CLICaptureMode.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return .capture(mode: mode, upload: arguments["upload"] as? Bool ?? false)
        case "capture_app":
            let app = (arguments["app"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            return .captureApp(app: app, contactSheet: arguments["contact_sheet"] as? Bool ?? false, upload: arguments["upload"] as? Bool ?? false)
        case "upload":
            guard let paths = arguments["paths"] as? [String], !paths.isEmpty else { throw MCPToolError(description: "paths needs at least one file") }
            guard paths.allSatisfy({ $0.hasPrefix("/") || $0.hasPrefix("~") }) else { throw MCPToolError(description: "paths must be absolute") }
            return .upload(files: paths.map { NSString(string: $0).expandingTildeInPath }, uploader: arguments["uploader"] as? String)
        case "list_uploaders":
            return .listUploaders
        case "recent_uploads":
            let limit = (arguments["limit"] as? Int).map { min(max($0, 1), 500) } ?? 20
            return .history(limit: limit)
        case "record":
            guard let raw = arguments["action"] as? String, let action = CLIRecordAction(rawValue: raw.lowercased()) else {
                throw MCPToolError(description: "action must be one of \(CLIRecordAction.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return .record(action)
        default:
            throw MCPToolError(description: "Unknown tool \(name)")
        }
    }
}
