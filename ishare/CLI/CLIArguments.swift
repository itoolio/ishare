import Foundation

struct CLIInvocation: Equatable, Sendable {
    let command: CLICommand
    var json = false
    var timeout: TimeInterval
}

enum CLIAction: Equatable, Sendable {
    case run(CLIInvocation)
    case help(String)
    case version
}

enum CLIArgumentError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case unknownOption(String)
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case missingArgument(String)
    case unexpectedArgument(String)

    var description: String {
        switch self {
        case .missingCommand: "Missing command."
        case let .unknownCommand(command): "Unknown command “\(command)”."
        case let .unknownOption(option): "Unknown option “\(option)”."
        case let .missingValue(option): "\(option) needs a value."
        case let .invalidValue(option, value): "“\(value)” isn't a valid value for \(option)."
        case let .missingArgument(name): "Missing \(name)."
        case let .unexpectedArgument(argument): "Unexpected argument “\(argument)”."
        }
    }
}

enum CLIArguments {
    static let defaultTimeout: TimeInterval = 120
    static let interactiveTimeout: TimeInterval = 600

    static let usage = """
        Usage: ishare <command> [options]

        Commands:
          upload <file…> [--uploader NAME]    Upload files and print their links
          capture region|window|screen|scrolling [--upload]
                                              Take a screenshot and print its file or link
          record start|stop|toggle|pause|resume [--preset NAME]
                                              Start, stop, pause or resume a screen recording
          uploaders list                      List the configured uploaders
          history [--limit N]                 Print recent uploads

        Options:
          --json                              Print machine-readable JSON
          --timeout SECONDS                   How long to wait for ishare (default 120, 600 for capture and record)
          -h, --help                          Show this help
          --version                           Show the version
        """

    static func parse(_ arguments: [String], workingDirectory: String = FileManager.default.currentDirectoryPath) throws(CLIArgumentError) -> CLIAction {
        var positional: [String] = []
        var json = false
        var timeout: TimeInterval?
        var uploader: String?
        var limit: Int?
        var upload = false
        var index = 0
        var optionsEnded = false

        func value(for option: String) throws(CLIArgumentError) -> String {
            index += 1
            guard index < arguments.count else { throw .missingValue(option) }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            if optionsEnded || !argument.hasPrefix("-") || argument == "-" {
                positional.append(argument)
                index += 1
                continue
            }
            let (name, inlineValue) = split(argument)
            func optionValue() throws(CLIArgumentError) -> String {
                if let inlineValue { return inlineValue }
                return try value(for: name)
            }
            switch name {
            case "--":
                optionsEnded = true
            case "-h", "--help":
                return .help(usage)
            case "--version":
                return .version
            case "--json":
                json = true
            case "--upload":
                upload = true
            case "--uploader", "-u":
                let raw = try optionValue()
                guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { throw .invalidValue(option: name, value: raw) }
                uploader = raw
            case "--limit", "-n":
                let raw = try optionValue()
                guard let number = Int(raw), number > 0 else { throw .invalidValue(option: name, value: raw) }
                limit = min(number, 500)
            case "--timeout":
                let raw = try optionValue()
                guard let seconds = TimeInterval(raw), seconds > 0 else { throw .invalidValue(option: name, value: raw) }
                timeout = seconds
            default:
                throw .unknownOption(argument)
            }
            index += 1
        }

        guard let commandName = positional.first else { throw .missingCommand }
        let rest = Array(positional.dropFirst())
        let command: CLICommand
        switch commandName {
        case "help":
            return .help(usage)
        case "upload":
            guard !rest.isEmpty else { throw .missingArgument("file") }
            command = .upload(files: rest.map { absolutePath($0, relativeTo: workingDirectory) }, uploader: uploader)
        case "capture":
            guard let modeName = rest.first else { throw .missingArgument("capture mode (region, window, screen or scrolling)") }
            guard let mode = CLICaptureMode(rawValue: modeName.lowercased()) else { throw .invalidValue(option: "capture", value: modeName) }
            try rejectExtra(rest.dropFirst())
            command = .capture(mode: mode, upload: upload)
        case "record":
            guard let actionName = rest.first else { throw .missingArgument("record action (start, stop, toggle, pause or resume)") }
            guard let action = CLIRecordAction(rawValue: actionName.lowercased()) else { throw .invalidValue(option: "record", value: actionName) }
            try rejectExtra(rest.dropFirst())
            command = .record(action)
        case "uploaders":
            guard let sub = rest.first else { throw .missingArgument("uploaders subcommand (list)") }
            guard sub == "list" else { throw .invalidValue(option: "uploaders", value: sub) }
            try rejectExtra(rest.dropFirst())
            command = .listUploaders
        case "history":
            try rejectExtra(rest[...])
            command = .history(limit: limit ?? 20)
        default:
            throw .unknownCommand(commandName)
        }
        if uploader != nil, !command.accepts(.uploader) { throw .unknownOption("--uploader") }
        if upload, !command.accepts(.upload) { throw .unknownOption("--upload") }
        if limit != nil, !command.accepts(.limit) { throw .unknownOption("--limit") }
        let defaultTimeout: TimeInterval =
            switch command {
            case .capture, .record: interactiveTimeout
            default: defaultTimeout
            }
        return .run(CLIInvocation(command: command, json: json, timeout: timeout ?? defaultTimeout))
    }

    static func absolutePath(_ path: String, relativeTo directory: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : (directory as NSString).appendingPathComponent(expanded)
        return (absolute as NSString).standardizingPath
    }

    private static func split(_ argument: String) -> (String, String?) {
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else { return (argument, nil) }
        return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))
    }

    private static func rejectExtra(_ arguments: ArraySlice<String>) throws(CLIArgumentError) {
        if let extra = arguments.first {
            throw .unexpectedArgument(extra)
        }
    }
}

enum CLICommandOption {
    case uploader
    case upload
    case limit
}

extension CLICommand {
    func accepts(_ option: CLICommandOption) -> Bool {
        switch (self, option) {
        case (.upload, .uploader), (.capture, .upload), (.history, .limit): true
        default: false
        }
    }
}

enum CLIOutput {
    static func text(for response: CLIResponse, command: CLICommand) -> String {
        guard response.success else { return "" }
        let payload = response.payload
        switch command {
        case .upload:
            return (payload.uploads ?? []).map { $0.link ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n")
        case .capture:
            return payload.capture?.link ?? payload.capture?.file ?? payload.message ?? ""
        case .record:
            return payload.message ?? ""
        case .listUploaders:
            return (payload.uploaders ?? []).map { ($0.selected ? "* " : "  ") + "\($0.name) (\($0.kind))" }.joined(separator: "\n")
        case .history:
            return (payload.history ?? []).map { entry in
                [entry.shortLink ?? entry.link ?? entry.localPath ?? "", entry.title].filter { !$0.isEmpty }.joined(separator: "\t")
            }.joined(separator: "\n")
        }
    }

    static func errors(for response: CLIResponse) -> [String] {
        var errors = response.error.map { [$0] } ?? []
        errors += (response.payload.uploads ?? []).compactMap { result in result.error.map { "\(result.file): \($0)" } }
        return errors
    }

    static func json(for response: CLIResponse) -> String {
        struct Envelope: Encodable {
            let success: Bool
            let error: String?
            let payload: CLIResponsePayload
        }
        let data = (try? CLICoding.encode(Envelope(success: response.success, error: response.error, payload: response.payload), pretty: true)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func exitCode(for response: CLIResponse) -> Int32 {
        guard response.success else { return 1 }
        return (response.payload.uploads ?? []).contains { $0.error != nil } ? 1 : 0
    }
}
