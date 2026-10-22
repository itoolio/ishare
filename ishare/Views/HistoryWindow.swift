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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.center()
        window.contentView = contentView
        self.init(window: window)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }
}

@MainActor
func openHistoryWindow(uploadHistory _: [HistoryItem]) {
    if WindowHolder.shared.historyWindowController == nil {
        let historyView = HistoryGridView()
        let hostingController = NSHostingController(rootView: historyView)
        let windowController = HistoryWindowController(contentView: hostingController.view)
        windowController.window?.title = "History".localized()

        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        WindowHolder.shared.historyWindowController = windowController
    } else {
        WindowHolder.shared.historyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
