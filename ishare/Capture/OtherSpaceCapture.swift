import AppKit
import BezelNotification
import ishareCore
import ScreenCaptureKit

@MainActor
enum OtherSpaceCapture {
    static func prompt() async {
        guard ScreenshotEngine.ensurePermission(), let content = try? await allWindowsContent() else { return }
        let names = Dictionary(content.applications.map { ($0.processID, $0.applicationName) }, uniquingKeysWith: { first, _ in first })
        let windows = OtherSpaceWindows.windows(
            in: content.windows.map(ScreenshotEngine.windowDescriptor), names: names,
            displaySizes: content.displays.map { CGSize(width: $0.width, height: $0.height) }, ownPID: ProcessInfo.processInfo.processIdentifier)
        guard !windows.isEmpty else {
            BezelNotification.show(messageText: "No windows on other Spaces".localized(), icon: ToastIcon)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Capture from Another Space".localized()
        alert.informativeText = "Captures a window or full-screen app on another Space without switching to it. Minimized windows can’t be captured.".localized()
        let picker = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 360, height: 26))
        for window in windows { picker.addItem(withTitle: window.menuTitle) }
        alert.accessoryView = picker
        alert.addButton(withTitle: "Capture".localized())
        alert.addButton(withTitle: "Cancel".localized())
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        await capture(windowID: windows[max(0, picker.indexOfSelectedItem)].id)
    }

    static func capture(windowID: CGWindowID, options: CaptureOptions = .standard) async {
        guard let content = try? await allWindowsContent(), let window = content.windows.first(where: { $0.windowID == windowID }) else {
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
            return
        }
        let bundleID = window.owningApplication?.bundleIdentifier
        let settings = CaptureSettings.current(for: bundleID)
        do {
            let image = try await ScreenshotEngine.captureWindow(window, includesShadow: settings.includesWindowShadow)
            let appName = window.owningApplication?.applicationName ?? "window"
            let scale = max(1, (CGFloat(image.width) / max(1, window.frame.width)).rounded())
            let source = CaptureSource(bundleIdentifier: bundleID, appName: appName)
            await CaptureSession.deliverCapture(CapturedImage(image: image, suffix: appName, isWindow: true, pointScale: scale, source: source), options: options)
        } catch {
            Log.capture.error("Capturing a window on another Space failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
        }
    }

    private static func allWindowsContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    }
}
