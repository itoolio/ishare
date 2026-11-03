import CoreGraphics
import Defaults
import Foundation
import ishareCore
@preconcurrency import ScreenCaptureKit

@MainActor
enum SelectionPrefetch {
    private static var startedAt: Double?
    private static var contentTask: Task<SCShareableContent?, Never>?
    private static var task: Task<[CGDirectDisplayID: CGImage], Never>?

    static var isWanted: Bool {
        Defaults[.freezeScreenWhileSelecting] && Defaults[.captureDelay] == .off && ScreenshotEngine.hasPermission
            && !ScreenshotMode.usesFixtureCapture
    }

    static func begin(includingBackdrops: Bool = true) {
        guard ScreenshotEngine.hasPermission, !ScreenshotMode.usesFixtureCapture,
            !SelectionPrefetchPolicy.isUsable(startedAt: startedAt, now: ProcessInfo.processInfo.systemUptime)
        else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        let content = Task { @MainActor in try? await ScreenshotEngine.shareableContent() }
        contentTask = content
        task = includingBackdrops && isWanted
            ? Task { @MainActor in
                guard let content = await content.value else { return [:] }
                return await ScreenshotEngine.backdrops(for: content)
            }
            : nil
    }

    static func takeContent() async -> SCShareableContent? {
        defer { contentTask = nil }
        guard let contentTask, SelectionPrefetchPolicy.isUsable(startedAt: startedAt, now: ProcessInfo.processInfo.systemUptime) else { return nil }
        return await contentTask.value
    }

    static func take() async -> [CGDirectDisplayID: CGImage]? {
        defer {
            startedAt = nil
            task = nil
            contentTask = nil
        }
        guard let task, SelectionPrefetchPolicy.isUsable(startedAt: startedAt, now: ProcessInfo.processInfo.systemUptime) else { return nil }
        return await task.value
    }
}
