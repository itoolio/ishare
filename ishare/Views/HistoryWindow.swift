import AppKit
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
