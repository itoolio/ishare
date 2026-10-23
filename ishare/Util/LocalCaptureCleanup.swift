import Defaults
import Foundation

struct LocalCaptureCleanupPlan: Sendable {
    var directories: [URL]
    var prefixes: [String]
    var cutoff: Date
    var protectedPaths: Set<String>
}

enum LocalCaptureCleanup {
    static let interval: TimeInterval = 86400
    static let mediaExtensions = HistoryItemKind.imageExtensions.union(HistoryItemKind.videoExtensions)

    @MainActor private static var timer: Timer?

    static func captureDate(ofFileNamed name: String, prefixes: [String]) -> Date? {
        let fileExtension = (name as NSString).pathExtension
        guard mediaExtensions.contains(fileExtension), fileExtension == fileExtension.lowercased() else { return nil }
        let stem = String(name.dropLast(fileExtension.count + 1))
        for prefix in Set(prefixes.map(namePrefix)) {
            guard stem.hasPrefix(prefix + "-") else { continue }
            let rest = stem.dropFirst(prefix.count + 1)
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let remainder = rest.dropFirst(digits.count)
            guard (9 ... 11).contains(digits.count), remainder.isEmpty || remainder.hasPrefix("-"),
                  let seconds = TimeInterval(String(digits))
            else { continue }
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    static func namePrefix(_ prefix: String) -> String {
        let sanitized = CaptureFileName.sanitize(prefix)
        return sanitized.isEmpty ? "ishare" : sanitized
    }

    static func candidates(for plan: LocalCaptureCleanupPlan, fileManager: FileManager = .default) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for directory in plan.directories {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
            for url in contents {
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard !seen.contains(path), isExpired(url, plan: plan) else { continue }
                seen.insert(path)
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func isExpired(_ url: URL, plan: LocalCaptureCleanupPlan) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let captured = captureDate(ofFileNamed: url.lastPathComponent, prefixes: plan.prefixes)
        else { return false }
        if plan.protectedPaths.contains(url.standardizedFileURL.resolvingSymlinksInPath().path) {
            return false
        }
        let lastTouched = max(captured, values.contentModificationDate ?? captured)
        return lastTouched < plan.cutoff
    }

    static func protectedPaths(in history: [HistoryItem]) -> Set<String> {
        Set(history.compactMap { item in
            guard item.remoteURL != nil, let url = item.localFileURL else { return nil }
            return url.standardizedFileURL.resolvingSymlinksInPath().path
        })
    }

    @discardableResult
    static func moveToTrash(_ urls: [URL], fileManager: FileManager = .default) -> Int {
        urls.reduce(0) { count, url in
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                return count + 1
            } catch {
                Log.app.error("Couldn't move \(url.lastPathComponent, privacy: .public) to the Trash: \(error.localizedDescription, privacy: .public)")
                return count
            }
        }
    }

    @MainActor static func currentPlan(now: Date = Date()) -> LocalCaptureCleanupPlan? {
        guard let maximumAge = Defaults[.localCaptureRetention].maximumAge else { return nil }
        let directories = [SaveLocation.directory(for: .captures), SaveLocation.directory(for: .recordings)]
        return LocalCaptureCleanupPlan(
            directories: directories,
            prefixes: [Defaults[.captureFileName], Defaults[.recordingFileName]],
            cutoff: now.addingTimeInterval(-maximumAge),
            protectedPaths: Defaults[.keepUploadedLocalCaptures] ? protectedPaths(in: Defaults[.uploadHistory]) : []
        )
    }

    @MainActor static func runNow() {
        guard let plan = currentPlan() else { return }
        Task.detached(priority: .utility) {
            let expired = candidates(for: plan)
            guard !expired.isEmpty else { return }
            let moved = moveToTrash(expired)
            Log.app.info("Moved \(moved) old local captures to the Trash")
        }
    }

    @MainActor static func start() {
        runNow()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in runNow() }
        }
        timer?.tolerance = 3600
    }
}
