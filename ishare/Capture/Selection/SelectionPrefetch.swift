import CoreGraphics
import Defaults
import Foundation
import ishareCore

@MainActor
enum SelectionPrefetch {
    private static var startedAt: Double?
    private static var task: Task<[CGDirectDisplayID: CGImage], Never>?

    static var isWanted: Bool {
        Defaults[.freezeScreenWhileSelecting] && Defaults[.captureDelay] == .off && ScreenshotEngine.hasPermission
            && !ScreenshotMode.usesFixtureCapture
    }

    static func begin() {
        guard isWanted, !SelectionPrefetchPolicy.isUsable(startedAt: startedAt, now: ProcessInfo.processInfo.systemUptime) else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        task = Task { @MainActor in
            guard let content = try? await ScreenshotEngine.shareableContent() else { return [:] }
            return await ScreenshotEngine.backdrops(for: content)
        }
    }

    static func take() async -> [CGDirectDisplayID: CGImage]? {
        defer {
            startedAt = nil
            task = nil
        }
        guard let task, SelectionPrefetchPolicy.isUsable(startedAt: startedAt, now: ProcessInfo.processInfo.systemUptime) else { return nil }
        return await task.value
    }
}
