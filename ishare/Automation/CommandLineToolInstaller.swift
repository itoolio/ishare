import Foundation

enum CommandLineToolState: Equatable {
    case missingTool
    case notInstalled
    case installed
    case linkedElsewhere(String)
}

enum CommandLineToolError: LocalizedError, Equatable {
    case missingTool
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingTool: "The command-line tool is missing from the app bundle.".localized()
        case .cancelled: "Installation was cancelled.".localized()
        case let .failed(reason): reason
        }
    }
}

enum CommandLineToolInstaller {
    static let linkPath = "/usr/local/bin/ishare"
    static let relativeToolPath = "Contents/Helpers/ishare"

    static func toolURL(in bundle: Bundle = .main) -> URL {
        bundle.bundleURL.appending(path: relativeToolPath)
    }

    static var canInstallDirectly: Bool {
        #if APP_STORE
            false
        #else
            true
        #endif
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func shellCommand(tool: URL = toolURL(), link: String = linkPath) -> String {
        let directory = (link as NSString).deletingLastPathComponent
        return "sudo mkdir -p \(shellQuoted(directory)) && sudo ln -sf \(shellQuoted(tool.path)) \(shellQuoted(link))"
    }

    static func administratorScript(tool: URL = toolURL(), link: String = linkPath) -> String {
        let directory = (link as NSString).deletingLastPathComponent
        let command = "/bin/mkdir -p \(shellQuoted(directory)) && /bin/ln -sf \(shellQuoted(tool.path)) \(shellQuoted(link))"
        return "do shell script \(appleScriptQuoted(command)) with administrator privileges"
    }

    static func state(tool: URL = toolURL(), link: String = linkPath, fileManager: FileManager = .default) -> CommandLineToolState {
        guard fileManager.fileExists(atPath: tool.path) else { return .missingTool }
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link) else {
            return fileManager.fileExists(atPath: link) ? .linkedElsewhere(link) : .notInstalled
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: link).deletingLastPathComponent()).standardizedFileURL.path
        return resolved == tool.standardizedFileURL.path ? .installed : .linkedElsewhere(resolved)
    }

    static func install(tool: URL = toolURL(), link: String = linkPath, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: tool.path) else { throw CommandLineToolError.missingTool }
        do {
            try linkDirectly(tool: tool, link: link, fileManager: fileManager)
            Log.app.info("Linked the command-line tool at \(link, privacy: .public)")
        } catch {
            Log.app.info("Linking without privileges failed, asking for an administrator: \(error.localizedDescription, privacy: .public)")
            try linkAsAdministrator(tool: tool, link: link)
        }
    }

    private static func linkDirectly(tool: URL, link: String, fileManager: FileManager) throws {
        let directory = (link as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        if (try? fileManager.destinationOfSymbolicLink(atPath: link)) != nil {
            try fileManager.removeItem(atPath: link)
        }
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: tool.path)
    }

    private static func linkAsAdministrator(tool: URL, link: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", administratorScript(tool: tool, link: link)]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if message.contains("-128") {
                throw CommandLineToolError.cancelled
            }
            throw CommandLineToolError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
