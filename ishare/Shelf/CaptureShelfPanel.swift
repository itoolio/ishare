import AppKit
import Defaults
import SwiftUI

@MainActor
final class CaptureShelfPanel: NSPanel, NSWindowDelegate {
    static let identifier = "ishare-capture-shelf"

    private var isPositioning = false
    private var snapTask: Task<Void, Never>?
    private var screenKey: String?

    init(rootView: some View) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: CaptureShelfGeometry.width, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        title = "Capture Shelf".localized()
        setAccessibilityIdentifier(Self.identifier)
        setAccessibilityRole(.window)
        sharingType = .none
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        delegate = self
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func present(itemCount: Int) {
        let screen = isVisible ? (self.screen ?? NSScreen.underMouse) : NSScreen.underMouse
        guard let screen else { return }
        screenKey = Self.key(for: screen)
        let placement = screenKey.flatMap { Defaults[.captureShelfPlacements][$0] } ?? .standard
        let target = frame(itemCount: itemCount, placement: placement, on: screen)
        if isVisible {
            move(to: target, animated: !Self.reducesMotion)
            return
        }
        alphaValue = 0
        let start = Self.reducesMotion ? target : target.offsetBy(dx: placement.edge == .leading ? -24 : 24, dy: 0)
        position(start)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.reducesMotion ? 0.12 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            if !Self.reducesMotion {
                animator().setFrame(target, display: true)
            }
        }
    }

    func resize(itemCount: Int) {
        guard isVisible, let screen = screen ?? NSScreen.underMouse else { return }
        let placement = CaptureShelfGeometry.placement(for: frame, in: screen.visibleFrame)
        move(to: frame(itemCount: itemCount, placement: placement, on: screen), animated: !Self.reducesMotion)
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.reducesMotion ? 0.1 : 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
            }
        }
    }

    private func frame(itemCount: Int, placement: CaptureShelfPlacement, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let size = CGSize(width: CaptureShelfGeometry.width, height: CaptureShelfGeometry.contentHeight(itemCount: itemCount, in: visible))
        return CaptureShelfGeometry.frame(size: size, placement: placement, in: visible)
    }

    private func position(_ target: CGRect) {
        isPositioning = true
        setFrame(target, display: true)
        isPositioning = false
    }

    private func move(to target: CGRect, animated: Bool) {
        guard animated else {
            position(target)
            return
        }
        isPositioning = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isPositioning = false
            }
        }
    }

    func windowDidMove(_: Notification) {
        guard !isPositioning, isVisible else { return }
        snapTask?.cancel()
        snapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else {
                if !Task.isCancelled { self?.windowDidMove(Notification(name: NSWindow.didMoveNotification)) }
                return
            }
            self?.snapToEdge()
        }
    }

    private func snapToEdge() {
        guard let screen = screen ?? NSScreen.underMouse else { return }
        let key = Self.key(for: screen)
        let placement = CaptureShelfGeometry.placement(for: frame, in: screen.visibleFrame)
        Defaults[.captureShelfPlacements][key] = placement
        screenKey = key
        move(to: CaptureShelfGeometry.frame(size: frame.size, placement: placement, in: screen.visibleFrame), animated: !Self.reducesMotion)
    }

    static func key(for screen: NSScreen) -> String {
        let uuid = screen.displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }.flatMap { CFUUIDCreateString(nil, $0) as String? }
        return CaptureShelfGeometry.screenKey(displayUUID: uuid, localizedName: screen.localizedName, frame: screen.frame)
    }
}
