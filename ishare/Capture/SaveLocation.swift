import Defaults
import Foundation

@MainActor
enum SaveLocation {
    enum Kind {
        case captures
        case recordings

        var pathKey: Defaults.Key<String> {
            switch self {
            case .captures: .capturePath
            case .recordings: .recordingPath
            }
        }

        var bookmarkKey: Defaults.Key<Data?> {
            switch self {
            case .captures: .capturePathBookmark
            case .recordings: .recordingPathBookmark
            }
        }
    }

    private static var accessed: [URL] = []

    static func directory(for kind: Kind) -> URL {
        let path = NSString(string: Defaults[kind.pathKey]).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileURL(for kind: Kind, fileName: String) -> URL {
        directory(for: kind).appending(path: fileName, directoryHint: .notDirectory)
    }

    static func choose(_ url: URL, for kind: Kind) {
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        Defaults[kind.bookmarkKey] = bookmark
        var path = url.path(percentEncoded: false)
        if !path.hasSuffix("/") {
            path += "/"
        }
        Defaults[kind.pathKey] = path
        activate(kind)
    }

    static func activateAll() {
        activate(.captures)
        activate(.recordings)
    }

    static func activate(_ kind: Kind) {
        guard let bookmark = Defaults[kind.bookmarkKey] else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return
        }
        if url.startAccessingSecurityScopedResource() {
            accessed.append(url)
        }
        if isStale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            Defaults[kind.bookmarkKey] = refreshed
        }
    }
}

enum CaptureFileName {
    static func make(prefix: String, suffix: String?, ext: String, date: Date = .init()) -> String {
        let timestamp = Int(date.timeIntervalSince1970)
        let sanitizedSuffix = suffix.map(sanitize).flatMap { $0.isEmpty ? nil : $0 }
        let base = [sanitize(prefix).isEmpty ? "ishare" : sanitize(prefix), String(timestamp), sanitizedSuffix].compactMap { $0 }.joined(separator: "-")
        return "\(base).\(ext.lowercased())"
    }

    static func sanitize(_ component: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return component
            .lowercased()
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
