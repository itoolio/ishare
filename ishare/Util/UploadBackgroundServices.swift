import Foundation

@MainActor
enum UploadBackgroundServices {
    private static var isStarted = false

    static func start() {
        guard !isStarted, !RuntimeEnvironment.isRunningTests, !ScreenshotMode.isActive else { return }
        isStarted = true
        UploadQueue.shared.start()
        WatchFolderService.shared.start()
        UploaderSyncMonitor.shared.start()
    }
}
