import Foundation

enum FolderArchiveError: LocalizedError {
    case failed

    var errorDescription: String? {
        "The folder couldn’t be zipped".localized()
    }
}

enum FolderArchive {
    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
    }

    static func zipped(_ folder: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let destinationFolder = FileManager.default.temporaryDirectory.appending(path: "ishare-zip-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let destination = destinationFolder.appending(path: folder.lastPathComponent + ".zip")
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zipURL in
                do {
                    try FileManager.default.copyItem(at: zipURL, to: destination)
                } catch {
                    copyError = error
                }
            }
            if let error = coordinatorError ?? copyError { throw error }
            guard FileManager.default.fileExists(atPath: destination.path) else { throw FolderArchiveError.failed }
            return destination
        }.value
    }

    static func discard(_ archive: URL) {
        try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
    }
}
