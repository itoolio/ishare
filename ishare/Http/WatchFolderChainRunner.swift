import AppKit
import BezelNotification
import Defaults
import ishareCore

@MainActor
enum WatchFolderChainRunner {
    struct Outcome: Equatable {
        var finalURL: URL?
        var link: String?
        var failure: String?
    }

    static var counter: Int {
        get { Defaults[.watchFolderCounter] }
        set { Defaults[.watchFolderCounter] = newValue }
    }

    static func run(_ actions: [WatchFolderAction], on original: URL, markProcessed: (URL) -> Void = { _ in }) async -> Outcome {
        let workspace = FileManager.default.temporaryDirectory.appending(path: "ishare-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        var source = original
        var working = original
        var outcome = Outcome(finalURL: original)
        for action in actions {
            switch action.kind {
            case .rename:
                counter += 1
                let name = WatchFolderChain.renamed(action.template, original: source, date: Date(), counter: counter)
                let destination = WatchFolderChainRunner.uniqueURL(in: source.deletingLastPathComponent(), named: name)
                markProcessed(destination)
                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                } catch {
                    return failed(outcome, "Renaming failed: %@", error)
                }
                if working == source { working = destination }
                source = destination
                outcome.finalURL = destination
            case .convert:
                guard let image = ImageEncoder.loadImage(at: working), let type = FileType(rawValue: action.format.lowercased()) ?? (action.format == "jpg" ? .JPG : nil) else {
                    return failed(outcome, "Converting failed: %@", nil)
                }
                let converted = workspace.appending(path: working.deletingPathExtension().lastPathComponent + "." + type.rawValue)
                do {
                    try ImageEncoder.write(image, as: type, to: converted)
                } catch {
                    return failed(outcome, "Converting failed: %@", error)
                }
                working = converted
            case .optimize:
                let settings = ImageOptimizationSettings(enabled: true, format: Defaults[.imageOptimizationFormat], quality: Defaults[.imageConversionQuality])
                if let optimized = ImageOptimizer.optimize(working, settings: settings, in: workspace) {
                    working = optimized.url
                }
            case .stripMetadata:
                if let scrubbed = MetadataScrubber.scrubbed(working, in: workspace) {
                    working = scrubbed
                }
            case .upload:
                let target = action.uploader.flatMap(AutomationUploaders.target(named:))
                let result = await UploadOrigin.$current.withValue(.imported) {
                    await UploadCoordinator.upload(fileURL: working, target: target, localFileURL: source)
                }
                switch result {
                case let .success(upload):
                    outcome.link = upload.historyURL ?? upload.url.absoluteString
                case let .failure(error):
                    return failed(outcome, "Uploading failed: %@", error)
                }
            case .copyLink:
                guard let link = outcome.link else { continue }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            case .moveToFolder:
                guard let folder = resolveFolder(for: action) else { return failed(outcome, "Moving failed: %@", nil) }
                let scoped = folder.startAccessingSecurityScopedResource()
                defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                let destination = WatchFolderChainRunner.uniqueURL(in: folder, named: source.lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                    outcome.finalURL = destination
                } catch {
                    return failed(outcome, "Moving failed: %@", error)
                }
            case .moveToTrash:
                do {
                    try FileManager.default.trashItem(at: source, resultingItemURL: nil)
                    outcome.finalURL = nil
                } catch {
                    return failed(outcome, "Moving to the Trash failed: %@", error)
                }
            }
        }
        return outcome
    }

    private static func failed(_ outcome: Outcome, _ format: String, _ error: Error?) -> Outcome {
        var result = outcome
        let message = String(format: format.localized(), error?.localizedDescription ?? "")
        result.failure = message
        Log.upload.error("Watch folder action failed: \(message, privacy: .public)")
        BezelNotification.show(messageText: message, icon: ToastIcon)
        return result
    }

    static func uniqueURL(in directory: URL, named name: String) -> URL {
        let candidate = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 2 ... 999 {
            let numbered = directory.appending(path: ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)")
            if !FileManager.default.fileExists(atPath: numbered.path) { return numbered }
        }
        return directory.appending(path: "\(base)-\(UUID().uuidString).\(ext)")
    }

    private static func resolveFolder(for action: WatchFolderAction) -> URL? {
        if let bookmark = action.folderBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return action.folderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
