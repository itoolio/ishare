import Foundation

enum AutomationOpenTarget: Equatable, Sendable {
    case history
    case settings(String?)
    case editor
}

enum URLSchemeCommand: Equatable, Sendable {
    case capture(CLICaptureMode)
    case record(CLIRecordAction, gif: Bool, region: Bool)
    case upload([URL])
    case selectUploader(String)
    case open(AutomationOpenTarget)
    case commandLine(UUID)
}

struct XCallback: Equatable, Sendable {
    var success: URL?
    var error: URL?
    var cancel: URL?

    static let parameterNames = ["x-success", "x-error", "x-cancel", "x-source"]
    static let forbiddenSchemes: Set<String> = ["http", "https", "file", "javascript", "data", "ishare", "about", "blob", "ftp"]

    var isEmpty: Bool {
        success == nil && error == nil && cancel == nil
    }

    static func validated(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return nil }
        return forbiddenSchemes.contains(scheme) ? nil : url
    }

    static func appending(_ items: [URLQueryItem], to url: URL) -> URL {
        guard !items.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? url
    }

    func successURL(link: String?) -> URL? {
        success.map { XCallback.appending(link.map { [URLQueryItem(name: "link", value: $0)] } ?? [], to: $0) }
    }

    func errorURL(code: Int, message: String) -> URL? {
        error.map { XCallback.appending([URLQueryItem(name: "errorCode", value: String(code)), URLQueryItem(name: "errorMessage", value: message)], to: $0) }
    }
}

struct URLSchemeRequest: Equatable, Sendable {
    let command: URLSchemeCommand
    var callback = XCallback()
}

enum URLSchemeError: Error, Equatable, Sendable {
    case unsupportedScheme(String)
    case unknownAction(String)
    case missingParameter(String)
    case invalidValue(parameter: String, value: String)
    case unreadablePath(String)
    case tooManyFiles(Int)
    case invalidCallback(String)

    var code: Int {
        switch self {
        case .unsupportedScheme: 1
        case .unknownAction: 2
        case .missingParameter: 3
        case .invalidValue: 4
        case .unreadablePath: 5
        case .tooManyFiles: 6
        case .invalidCallback: 7
        }
    }

    var message: String {
        switch self {
        case let .unsupportedScheme(scheme): "Unsupported URL scheme \(scheme)"
        case let .unknownAction(action): "Unknown action \(action)"
        case let .missingParameter(name): "Missing parameter \(name)"
        case let .invalidValue(parameter, value): "Invalid value \(value) for \(parameter)"
        case let .unreadablePath(path): "ishare can't read \(path)"
        case let .tooManyFiles(count): "Too many files (\(count))"
        case let .invalidCallback(name): "Callback \(name) must use an app URL scheme"
        }
    }
}

struct URLSchemeFileAccess: Sendable {
    var isReadableFile: @Sendable (String) -> Bool

    static let live = URLSchemeFileAccess { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: path)
    }
}

enum URLSchemeParser {
    static let scheme = "ishare"
    static let maximumFiles = 50

    static func parse(_ url: URL, fileAccess: URLSchemeFileAccess = .live) -> Result<URLSchemeRequest, URLSchemeError> {
        guard url.scheme?.lowercased() == scheme else { return .failure(.unsupportedScheme(url.scheme ?? "")) }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let callback: XCallback
        switch callbacks(from: items) {
        case let .success(value): callback = value
        case let .failure(error): return .failure(error)
        }
        var segments = ([components?.host ?? ""] + (components?.path ?? "").split(separator: "/").map(String.init))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        if segments.first == "x-callback-url" {
            segments.removeFirst()
        }
        return command(segments: segments, items: items, fileAccess: fileAccess).map { URLSchemeRequest(command: $0, callback: callback) }
    }

    static func callbacks(from items: [URLQueryItem]) -> Result<XCallback, URLSchemeError> {
        var callback = XCallback()
        for (name, keyPath) in [("x-success", \XCallback.success), ("x-error", \XCallback.error), ("x-cancel", \XCallback.cancel)] {
            guard let raw = value(name, in: items) else { continue }
            guard let url = XCallback.validated(raw) else { return .failure(.invalidCallback(name)) }
            callback[keyPath: keyPath] = url
        }
        return .success(callback)
    }

    static func value(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name.lowercased() == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func flag(_ name: String, in items: [URLQueryItem]) -> Bool {
        guard let item = items.first(where: { $0.name.lowercased() == name }) else { return false }
        return !["0", "false", "no"].contains(item.value?.lowercased() ?? "1")
    }

    private static func command(segments: [String], items: [URLQueryItem], fileAccess: URLSchemeFileAccess) -> Result<URLSchemeCommand, URLSchemeError> {
        guard let action = segments.first else { return .failure(.unknownAction("")) }
        let argument = segments.dropFirst().first
        switch action {
        case "capture":
            let name = argument ?? value("type", in: items)?.lowercased() ?? CLICaptureMode.region.rawValue
            guard let mode = CLICaptureMode(rawValue: name) else { return .failure(.invalidValue(parameter: "capture", value: name)) }
            return .success(.capture(mode))
        case "record":
            let name = argument ?? CLIRecordAction.toggle.rawValue
            guard let recordAction = CLIRecordAction(rawValue: name) else { return .failure(.invalidValue(parameter: "record", value: name)) }
            return .success(.record(recordAction, gif: flag("gif", in: items), region: flag("region", in: items)))
        case "upload":
            return uploadCommand(items: items, fileAccess: fileAccess)
        case "uploader":
            guard argument == "select" else { return .failure(.unknownAction("uploader/\(argument ?? "")")) }
            guard let name = value("name", in: items)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return .failure(.missingParameter("name"))
            }
            return .success(.selectUploader(name))
        case "open":
            switch argument {
            case "history": return .success(.open(.history))
            case "settings": return .success(.open(.settings(value("pane", in: items)?.lowercased())))
            case "editor": return .success(.open(.editor))
            default: return .failure(.invalidValue(parameter: "open", value: argument ?? ""))
            }
        case "cli":
            guard let raw = value("id", in: items) else { return .failure(.missingParameter("id")) }
            guard let id = UUID(uuidString: raw) else { return .failure(.invalidValue(parameter: "id", value: raw)) }
            return .success(.commandLine(id))
        default:
            return .failure(.unknownAction(action))
        }
    }

    private static func uploadCommand(items: [URLQueryItem], fileAccess: URLSchemeFileAccess) -> Result<URLSchemeCommand, URLSchemeError> {
        let paths = items.filter { $0.name.lowercased() == "path" }.compactMap(\.value)
        let legacy = items.filter { $0.name.lowercased() == "file" }.compactMap(\.value).compactMap(legacyPath)
        let all = paths + legacy
        guard !all.isEmpty else { return .failure(.missingParameter("path")) }
        guard all.count <= maximumFiles else { return .failure(.tooManyFiles(all.count)) }
        var urls: [URL] = []
        for path in all {
            switch validatedFile(path, fileAccess: fileAccess) {
            case let .success(url): urls.append(url)
            case let .failure(error): return .failure(error)
            }
        }
        return .success(.upload(urls))
    }

    static func legacyPath(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        if let url = URL(string: decoded), url.isFileURL {
            return url.path
        }
        return decoded.hasPrefix("/") ? decoded : nil
    }

    static func validatedFile(_ path: String, fileAccess: URLSchemeFileAccess) -> Result<URL, URLSchemeError> {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.contains("\0") else { return .failure(.unreadablePath(path)) }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        guard fileAccess.isReadableFile(url.path) else { return .failure(.unreadablePath(path)) }
        return .success(url)
    }
}
