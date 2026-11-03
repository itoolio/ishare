import AppKit
import BezelNotification
import Defaults
import ishareCore
import ScreenCaptureKit

@MainActor
enum AppWindowsCapture {
    static func prompt() async {
        guard ScreenshotEngine.ensurePermission(), let content = try? await ScreenshotEngine.shareableContent() else { return }
        let descriptors = content.windows.map(ScreenshotEngine.windowDescriptor)
        let names = Dictionary(content.applications.map { ($0.processID, $0.applicationName) }, uniquingKeysWith: { first, _ in first })
        let apps = AppWindowsPlan.apps(in: descriptors, names: names, ownPID: ProcessInfo.processInfo.processIdentifier)
        guard !apps.isEmpty else {
            BezelNotification.show(messageText: "No app windows to capture".localized(), icon: ToastIcon)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let alert = NSAlert()
        alert.messageText = "Capture App Windows".localized()
        alert.informativeText = "Captures every open window of the app.".localized()
        let picker = NSPopUpButton()
        for app in apps { picker.addItem(withTitle: app.appName) }
        if let index = apps.firstIndex(where: { $0.ownerPID == frontmost }) { picker.selectItem(at: index) }
        let result = NSPopUpButton()
        result.addItems(withTitles: [AppWindowsResult.separate.title, AppWindowsResult.contactSheet.title])
        result.selectItem(at: Defaults[.appWindowsResult] == .contactSheet ? 1 : 0)
        let stack = NSStackView(views: [picker, result])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = CGRect(x: 0, y: 0, width: 280, height: 56)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Capture".localized())
        alert.addButton(withTitle: "Cancel".localized())
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Defaults[.appWindowsResult] = result.indexOfSelectedItem == 1 ? .contactSheet : .separate
        await capture(pid: apps[max(0, picker.indexOfSelectedItem)].ownerPID, as: Defaults[.appWindowsResult])
    }

    static func capture(pid: Int32, as result: AppWindowsResult, options: CaptureOptions = .standard) async {
        guard let content = try? await ScreenshotEngine.shareableContent() else { return }
        let order = AppWindowsPlan.windows(of: pid, in: content.windows.map(ScreenshotEngine.windowDescriptor)).map(\.id)
        let windows = order.compactMap { id in content.windows.first { $0.windowID == id } }
        var images: [(CGImage, SCWindow)] = []
        for window in windows {
            let settings = CaptureSettings.current(for: window.owningApplication?.bundleIdentifier)
            if let image = try? await ScreenshotEngine.captureWindow(window, includesShadow: settings.includesWindowShadow) {
                images.append((image, window))
            }
        }
        guard !images.isEmpty else {
            BezelNotification.show(messageText: "No app windows to capture".localized(), icon: ToastIcon)
            return
        }
        let appName = windows.first?.owningApplication?.applicationName ?? "app"
        let source = CaptureSource(bundleIdentifier: windows.first?.owningApplication?.bundleIdentifier, appName: appName)
        switch result {
        case .separate:
            for (image, window) in images {
                let scale = max(1, (CGFloat(image.width) / max(1, window.frame.width)).rounded())
                await CaptureSession.deliverCapture(CapturedImage(image: image, suffix: appName, isWindow: true, pointScale: scale, source: source), options: options)
            }
        case .contactSheet:
            var settings = CombineSettings.load()
            settings.layout = .grid
            settings.columns = AppWindowsPlan.contactSheetColumns(for: images.count)
            guard let sheet = ImageCombiner.combine(images.map(\.0), style: settings.style(imageCount: images.count)) else { return }
            await CaptureSession.deliverCapture(CapturedImage(image: sheet, suffix: appName, isWindow: true, pointScale: 2, source: source), options: options)
        }
    }
}

extension AppWindowsResult {
    var title: String {
        switch self {
        case .separate: "Separate captures".localized()
        case .contactSheet: "One contact sheet".localized()
        }
    }
}
