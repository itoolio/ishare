import AppKit
import Foundation

@MainActor
enum BackgroundMaintenance {
    private static var wakeObserver: (any NSObjectProtocol)?

    static func start() {
        guard !ScreenshotMode.isActive, !RuntimeEnvironment.isRunningTests else { return }
        DiagnosticsCollector.shared.start()
        LocalCaptureCleanup.start()
        WidgetSnapshotWriter.start()
        UploadExpiryService.start()
        UploaderHealthCheck.start()
        observeWake()
    }

    private static func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                UploadExpiryService.systemDidWake()
                UploaderHealthCheck.systemDidWake()
            }
        }
    }
}
