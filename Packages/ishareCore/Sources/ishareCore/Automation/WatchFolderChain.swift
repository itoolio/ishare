import Foundation

public struct WatchFolderAction: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case rename
        case convert
        case optimize
        case stripMetadata
        case upload
        case copyLink
        case moveToFolder
        case moveToTrash
    }

    public var id: UUID
    public var kind: Kind
    public var template: String
    public var format: String
    public var uploader: String?
    public var folderPath: String?
    public var folderBookmark: Data?

    public init(
        id: UUID = UUID(), kind: Kind, template: String = "{{date}}-{{name}}", format: String = "png", uploader: String? = nil, folderPath: String? = nil,
        folderBookmark: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.template = template
        self.format = format
        self.uploader = uploader
        self.folderPath = folderPath
        self.folderBookmark = folderBookmark
    }

    public var endsChain: Bool {
        kind == .moveToFolder || kind == .moveToTrash
    }
}

public enum WatchFolderChainIssue: Equatable, Sendable {
    case empty
    case copyLinkBeforeUpload
    case stepAfterMove
    case missingFolder
    case emptyTemplate
}

public enum WatchFolderChain {
    public static let defaultActions = [WatchFolderAction(kind: .upload)]
    public static let convertibleFormats = ["png", "jpg", "heic", "webp"]

    public static func issues(in actions: [WatchFolderAction]) -> [WatchFolderChainIssue] {
        guard !actions.isEmpty else { return [.empty] }
        var issues: [WatchFolderChainIssue] = []
        var uploaded = false
        for (index, action) in actions.enumerated() {
            switch action.kind {
            case .upload: uploaded = true
            case .copyLink where !uploaded: issues.append(.copyLinkBeforeUpload)
            case .moveToFolder where (action.folderPath ?? "").isEmpty: issues.append(.missingFolder)
            case .rename where action.template.trimmingCharacters(in: .whitespaces).isEmpty: issues.append(.emptyTemplate)
            default: break
            }
            if action.endsChain, index < actions.count - 1 {
                issues.append(.stepAfterMove)
            }
        }
        return issues
    }

    public static func renamed(_ template: String, original: URL, date: Date, counter: Int, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH-mm-ss"
        let time = formatter.string(from: date)
        let name = original.deletingPathExtension().lastPathComponent
        let base =
            template
            .replacingOccurrences(of: "{{date}}", with: day)
            .replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{counter}}", with: String(counter))
            .replacingOccurrences(of: "{{name}}", with: name)
        let cleaned = base.components(separatedBy: CharacterSet(charactersIn: "/:\\\0")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        let finalBase = cleaned.isEmpty ? name : cleaned
        return original.pathExtension.isEmpty ? finalBase : "\(finalBase).\(original.pathExtension)"
    }

    public static func migrated(uploadsFiles: Bool) -> [WatchFolderAction] {
        uploadsFiles ? defaultActions : []
    }
}
