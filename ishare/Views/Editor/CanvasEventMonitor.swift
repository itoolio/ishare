import AppKit
import SwiftUI

struct CanvasEventMonitor: NSViewRepresentable {
    var onScroll: (CGVector, CGPoint, NSEvent.ModifierFlags) -> Void
    var onSpace: (Bool) -> Bool
    var onContextMenu: (CGPoint) -> NSMenu? = { _ in nil }

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        view.onSpace = onSpace
        view.onContextMenu = onContextMenu
        return view
    }

    func updateNSView(_ view: MonitorView, context _: Context) {
        view.onScroll = onScroll
        view.onSpace = onSpace
        view.onContextMenu = onContextMenu
    }

    static func dismantleNSView(_ view: MonitorView, coordinator _: ()) {
        view.removeMonitors()
    }

    final class MonitorView: NSView {
        static let spaceKeyCode: UInt16 = 49

        var onScroll: ((CGVector, CGPoint, NSEvent.ModifierFlags) -> Void)?
        var onSpace: ((Bool) -> Bool)?
        var onContextMenu: ((CGPoint) -> NSMenu?)?
        private var monitors: [Any] = []

        override var isFlipped: Bool { true }

        override func hitTest(_: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitors()
            guard window != nil else { return }
            if let scroll = NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel,
                handler: { [weak self] event in
                    self?.handleScroll(event) ?? event
                })
            {
                monitors.append(scroll)
            }
            if let keys = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp],
                handler: { [weak self] event in
                    self?.handleKey(event) ?? event
                })
            {
                monitors.append(keys)
            }
            if let rightClicks = NSEvent.addLocalMonitorForEvents(
                matching: .rightMouseDown,
                handler: { [weak self] event in
                    self?.handleRightClick(event) ?? event
                })
            {
                monitors.append(rightClicks)
            }
        }

        func removeMonitors() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            onScroll?(CGVector(dx: event.scrollingDeltaX * multiplier, dy: event.scrollingDeltaY * multiplier), location, event.modifierFlags)
            return nil
        }

        private func handleRightClick(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location), let menu = onContextMenu?(location) else { return event }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return nil
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, event.keyCode == Self.spaceKeyCode,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
                !(window?.firstResponder is NSText)
            else { return event }
            let handled = onSpace?(event.type == .keyDown) ?? false
            return handled ? nil : event
        }
    }
}
