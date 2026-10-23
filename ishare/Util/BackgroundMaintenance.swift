import Foundation

@MainActor
enum BackgroundMaintenance {
    static func start() {
        guard !ScreenshotMode.isActive, !RuntimeEnvironment.isRunningTests else { return }
        DiagnosticsCollector.shared.start()
        LocalCaptureCleanup.start()
        WidgetSnapshotWriter.start()
    }
}
