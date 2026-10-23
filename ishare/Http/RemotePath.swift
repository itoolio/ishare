import Foundation

enum RemotePathError: LocalizedError, Equatable {
    case emptyPath
    case invalidPublicURL(String)

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            "The remote path template produced an empty path".localized()
        case let .invalidPublicURL(value):
            String(format: "The public URL template produced an invalid URL: %@".localized(), value)
        }
    }
}

enum RemotePath {
    static let defaultTemplate = "{{date}}/{{filename}}"

    static func render(_ template: String?, fileName: String, date: Date = .init(), uuid: UUID = .init()) throws -> String {
        let source = template?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? defaultTemplate
        let rendered = try S3KeyTemplate.render(source, context: S3KeyContext(fileName: UploadFileName.lowercasing(fileName), date: date, uuid: uuid))
        let path = FolderPaths.sanitized(rendered)
        guard !path.isEmpty else { throw RemotePathError.emptyPath }
        return path
    }

    static func directories(of path: String) -> [String] {
        let segments = path.split(separator: "/").map(String.init).dropLast()
        return segments.indices.map { segments[...$0].joined(separator: "/") }
    }

    static func joined(_ base: String, _ path: String) -> String {
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmedBase + "/" + path
    }

    static func publicURL(_ template: String?, path: String, fallback: URL?) throws -> URL? {
        guard let template = template?.trimmingCharacters(in: .whitespaces), !template.isEmpty else { return fallback }
        let fileName = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        let rendered = try ResponseTemplate.render(template) { name in
            switch name.lowercased() {
            case "path": S3Path.encode(path)
            case "rawpath": path
            case "filename": S3Path.encodeSegment(fileName)
            case "rawfilename": fileName
            case "directory", "subfolder": S3Path.encode(directory)
            default: nil
            }
        }
        guard let url = URL(string: rendered), url.scheme != nil else { throw RemotePathError.invalidPublicURL(rendered) }
        return url
    }
}

extension UploadFileName {
    static func lowercasing(_ fileName: String) -> String {
        lowercasingExtension(of: URL(fileURLWithPath: fileName))
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
