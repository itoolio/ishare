import Defaults
import Foundation
import ishareCore

enum UploadOrigin: Sendable {
    case capture
    case imported

    @TaskLocal static var current: UploadOrigin = .capture
}

struct PreparedUpload: Sendable {
    let fileURL: URL
    var originalBytes: Int?
    var optimizedBytes: Int?
    var strippedMetadata = false
    let workingDirectory: URL?

    var savedBytes: Int? {
        guard let originalBytes, let optimizedBytes, optimizedBytes < originalBytes else { return nil }
        return originalBytes - optimizedBytes
    }

    func discard() {
        if let workingDirectory {
            try? FileManager.default.removeItem(at: workingDirectory)
        }
    }
}

struct UploadPreparationPolicy: Equatable, Sendable {
    var stripsMetadata: Bool
    var optimization: ImageOptimizationSettings

    var isNoop: Bool { !stripsMetadata && !optimization.enabled }

    @MainActor static func current(for target: UploadTarget, origin: UploadOrigin = UploadOrigin.current) -> UploadPreparationPolicy {
        let global = ImageOptimizationSettings(
            enabled: Defaults[.optimizeImagesBeforeUpload], format: Defaults[.imageOptimizationFormat], quality: Defaults[.imageConversionQuality]
        )
        let override: ImageOptimizationOverride? = if case let .custom(uploader) = target { uploader.imageOptimization } else { nil }
        return UploadPreparationPolicy(
            stripsMetadata: stripsMetadata(origin: origin, always: Defaults[.stripImageMetadata], imported: Defaults[.stripImportedImageMetadata]),
            optimization: .resolved(global: global, override: override)
        )
    }

    static func stripsMetadata(origin: UploadOrigin, always: Bool, imported: Bool) -> Bool {
        always || (origin == .imported && imported)
    }
}

enum UploadPreparation {
    static func prepare(_ fileURL: URL, policy: UploadPreparationPolicy) async -> PreparedUpload {
        guard !policy.isNoop, MimeType.isImageOrVideo(fileURL) else {
            return PreparedUpload(fileURL: fileURL, workingDirectory: nil)
        }
        return await Task.detached(priority: .userInitiated) {
            prepareSynchronously(fileURL, policy: policy)
        }.value
    }

    static func prepareSynchronously(_ fileURL: URL, policy: UploadPreparationPolicy) -> PreparedUpload {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-upload-\(UUID().uuidString)", directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return PreparedUpload(fileURL: fileURL, workingDirectory: nil)
        }
        var current = fileURL
        var stripped = false
        if policy.stripsMetadata {
            let scrubDirectory = directory.appending(path: "clean", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: scrubDirectory, withIntermediateDirectories: true)
            if let clean = MetadataScrubber.scrubbed(current, in: scrubDirectory) {
                current = clean
                stripped = true
            }
        }
        var prepared = PreparedUpload(fileURL: current, strippedMetadata: stripped, workingDirectory: directory)
        if policy.optimization.enabled {
            let optimizedDirectory = directory.appending(path: "optimized", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: optimizedDirectory, withIntermediateDirectories: true)
            if let result = ImageOptimizer.optimize(current, settings: policy.optimization, in: optimizedDirectory) {
                prepared = PreparedUpload(
                    fileURL: result.url, originalBytes: ImageOptimizer.fileSize(fileURL), optimizedBytes: result.optimizedBytes,
                    strippedMetadata: stripped, workingDirectory: directory
                )
            }
        }
        if prepared.fileURL == fileURL {
            prepared.discard()
            return PreparedUpload(fileURL: fileURL, workingDirectory: nil)
        }
        return prepared
    }
}
