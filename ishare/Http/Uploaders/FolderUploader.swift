import Defaults
import Foundation
import ishareCore

enum LocalDestinationError: LocalizedError, Equatable {
    case missingFolder(String)
    case folderUnavailable(String)
    case invalidPublicURL
    case photosAccessDenied
    case photosSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingFolder(name):
            String(format: "Choose a folder for “%@” in Settings > Uploaders.".localized(), name)
        case let .folderUnavailable(name):
            String(format: "ishare can't write to the folder of “%@”. Choose the folder again in Settings > Uploaders.".localized(), name)
        case .invalidPublicURL:
            "The public URL template did not produce a valid URL".localized()
        case .photosAccessDenied:
            "ishare doesn't have access to Photos. Allow it in System Settings > Privacy & Security > Photos.".localized()
        case let .photosSaveFailed(detail):
            detail
        }
    }
}

@MainActor
enum LocalFolderAccess {
    static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func bookmark(for id: UUID) -> Data? {
        Defaults[.localFolderBookmarks][id.uuidString]
    }

    static func setBookmark(_ data: Data?, for id: UUID) {
        Defaults[.localFolderBookmarks][id.uuidString] = data
    }

    static func hasBookmark(for id: UUID) -> Bool {
        bookmark(for: id) != nil
    }

    static func folderURL(for uploader: CustomUploader) throws -> URL {
        if let data = bookmark(for: uploader.id), let url = resolve(data, for: uploader.id) {
            return url
        }
        guard let url = uploader.folder?.folderURL else { throw LocalDestinationError.missingFolder(uploader.name) }
        return url
    }

    private static func resolve(_ data: Data, for id: UUID) -> URL? {
        var isStale = false
        let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale))
        guard let url else { return nil }
        if isStale {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let refreshed = makeBookmark(for: url) {
                setBookmark(refreshed, for: id)
            }
        }
        return url
    }
}

enum FolderCopier {
    static func copy(_ source: URL, into root: URL, subfolder: String) throws -> (fileURL: URL, relativePath: String) {
        try withAccess(to: root) {
            let manager = FileManager.default
            let directory = subfolder.isEmpty ? root : root.appending(path: subfolder, directoryHint: .isDirectory)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = UploadFileName.lowercasingExtension(of: source)
            let target = FolderPaths.uniqueURL(for: fileName, in: directory) { manager.fileExists(atPath: $0.path) }
            try manager.copyItem(at: source, to: target)
            let relativePath = subfolder.isEmpty ? target.lastPathComponent : "\(subfolder)/\(target.lastPathComponent)"
            return (target, relativePath)
        }
    }

    static func remove(_ relativePath: String, in root: URL, usingTrash: Bool = true) throws {
        let cleaned = FolderPaths.sanitized(relativePath)
        guard !cleaned.isEmpty else { return }
        try withAccess(to: root) {
            let target = root.appending(path: cleaned, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: target.path) else { return }
            if usingTrash, (try? FileManager.default.trashItem(at: target, resultingItemURL: nil)) != nil {
                return
            }
            try FileManager.default.removeItem(at: target)
        }
    }

    private static func withAccess<T>(to root: URL, _ body: () throws -> T) throws -> T {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

struct FolderUploader: Uploader {
    let uploader: CustomUploader
    var now: @Sendable () -> Date = { Date() }
    var movesDeletedFilesToTrash = true

    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome {
        let issues = UploaderValidator.issues(for: uploader)
        guard issues.isEmpty, let destination = uploader.folder else { throw UploadFailure.invalidSpecification(issues) }
        let root = try LocalFolderAccess.folderURL(for: uploader)
        let subfolder = try FolderPaths.subfolder(destination.subfolderTemplate, fileName: fileURL.lastPathComponent, date: now())
        let name = uploader.name
        let copied: (fileURL: URL, relativePath: String)
        do {
            copied = try await Task.detached(priority: .userInitiated) {
                try FolderCopier.copy(fileURL, into: root, subfolder: subfolder)
            }.value
        } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
            throw LocalDestinationError.folderUnavailable(name)
        }
        progress(1)
        guard let resultURL = try FolderPaths.resultURL(for: destination, fileURL: copied.fileURL, relativePath: copied.relativePath) else {
            throw LocalDestinationError.invalidPublicURL
        }
        return UploadOutcome(
            url: resultURL, deletionURL: nil, uploaderID: uploader.id, s3Key: nil, localIdentifier: copied.relativePath
        )
    }

    func delete(_ item: HistoryItem) async throws {
        guard let relativePath = item.localIdentifier else { return }
        let root = try LocalFolderAccess.folderURL(for: uploader)
        try FolderCopier.remove(relativePath, in: root, usingTrash: movesDeletedFilesToTrash)
    }
}
