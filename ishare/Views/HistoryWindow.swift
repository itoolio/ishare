import AppKit
import Quartz
import SwiftUI

@MainActor
class WindowHolder: Sendable {
    static let shared = WindowHolder()
    var historyWindowController: HistoryWindowController?
}

@MainActor
class HistoryWindowController: NSWindowController {
    convenience init(contentView: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.contentMinSize = NSSize(width: 600, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.center()
        self.init(window: window)
        installSpaceMonitor()
    }

    private var spaceMonitor: Any?

    private func installSpaceMonitor() {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, HistoryQuickLook.shouldToggle(on: event, in: window) else { return event }
            NotificationCenter.default.post(name: HistoryQuickLook.toggleRequest, object: nil)
            return nil
        }
    }

    override func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { HistoryQuickLook.shared.begin(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { HistoryQuickLook.shared.end(panel) }
    }
}

@MainActor
func openHistoryWindow(uploadHistory _: [HistoryItem]) {
    if WindowHolder.shared.historyWindowController == nil {
        let hostingController = NSHostingController(rootView: HistoryGridView())
        hostingController.sizingOptions = []
        let windowController = HistoryWindowController(contentView: hostingController.view)
        windowController.contentViewController = hostingController
        windowController.window?.title = "History".localized()
        windowController.window?.setContentSize(NSSize(width: 780, height: 520))
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        WindowHolder.shared.historyWindowController = windowController
    } else {
        WindowHolder.shared.historyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
