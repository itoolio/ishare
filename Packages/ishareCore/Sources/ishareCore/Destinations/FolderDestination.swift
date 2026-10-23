import Foundation

public struct FolderDestination: Codable, Hashable, Sendable {
    public var path: String
    public var subfolderTemplate: String?
    public var publicURL: String?

    public init(path: String, subfolderTemplate: String? = nil, publicURL: String? = nil) {
        self.path = path
        self.subfolderTemplate = subfolderTemplate
        self.publicURL = publicURL
    }

    enum CodingKeys: String, CodingKey {
        case path
        case subfolderTemplate = "subfoldertemplate"
        case publicURL = "publicurl"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        path = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "path")) ?? ""
        subfolderTemplate = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "subfoldertemplate"))
        publicURL = try container.decodeDynamicIfPresent(String.self, forKey: .key(named: "publicurl"))
    }

    public var folderURL: URL? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }
}

public enum FolderPaths {
    public static func subfolder(_ template: String?, fileName: String, date: Date) throws -> String {
        guard let template = template?.trimmingCharacters(in: .whitespaces), !template.isEmpty else { return "" }
        let rendered = try S3KeyTemplate.render(template, context: S3KeyContext(fileName: fileName, date: date))
        return sanitized(rendered)
    }

    public static func sanitized(_ relativePath: String) -> String {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }

    public static func uniqueURL(for fileName: String, in directory: URL, exists: (URL) -> Bool) -> URL {
        let candidate = directory.appending(path: fileName, directoryHint: .notDirectory)
        guard exists(candidate) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let next = directory.appending(path: name, directoryHint: .notDirectory)
            if !exists(next) { return next }
            index += 1
        }
    }

    public static func resultURL(for destination: FolderDestination, fileURL: URL, relativePath: String) throws -> URL? {
        guard let template = destination.publicURL?.trimmingCharacters(in: .whitespaces), !template.isEmpty else {
            return fileURL
        }
        let fileName = (relativePath as NSString).lastPathComponent
        let subfolder = (relativePath as NSString).deletingLastPathComponent
        let rendered = try ResponseTemplate.render(template) { name in
            switch name.lowercased() {
            case "filename": S3Path.encodeSegment(fileName)
            case "rawfilename": fileName
            case "path": S3Path.encode(relativePath)
            case "rawpath": relativePath
            case "subfolder": S3Path.encode(subfolder)
            default: nil
            }
        }
        return URL(string: rendered)
    }
}
