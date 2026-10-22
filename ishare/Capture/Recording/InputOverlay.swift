@preconcurrency import AppKit
import SwiftUI

struct RawKeyEvent: Sendable {
    let keyCode: Int
    let characters: String?
    let baseCharacters: String?
    let modifiers: KeystrokeModifiers
    let isRepeat: Bool

    init?(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .keyDown else { return nil }
        keyCode = Int(nsEvent.keyCode)
        characters = nsEvent.characters
        baseCharacters = nsEvent.characters(byApplyingModifiers: [])
        modifiers = KeystrokeModifiers(nsEvent.modifierFlags)
        isRepeat = nsEvent.isARepeat
    }
}

extension KeystrokeModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeystrokeModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

enum InputMonitoringPermission {
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    static func request() {
        guard !CGRequestListenEventAccess() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class InputEventMonitor {
    var onClick: ((CGPoint) -> Void)?
    var onKey: ((RawKeyEvent) -> Void)?

    private var mouseMonitors: [Any] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func startClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onClick?(NSEvent.mouseLocation) }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.onClick?(NSEvent.mouseLocation) }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    @discardableResult
    func startKeys() -> Bool {
        guard InputMonitoringPermission.isGranted, eventTap == nil else { return eventTap != nil }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: inputEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.capture.error("Couldn't create the keystroke event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func reenableTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    fileprivate func receive(_ event: RawKeyEvent) {
        onKey?(event)
    }
}

private func inputEventTapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<InputEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { monitor.reenableTap() }
    case .keyDown:
        if let keyEvent = RawKeyEvent(event) {
            MainActor.assumeIsolated { monitor.receive(keyEvent) }
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class InputOverlayModel: ObservableObject {
    struct Ripple: Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    @Published var ripples: [Ripple] = []
    @Published var keystrokeText: String?
    let keystrokeAnchor: CGRect

    init(keystrokeAnchor: CGRect) {
        self.keystrokeAnchor = keystrokeAnchor
    }
}

struct RecordingArea {
    let screen: NSScreen
    let rect: CGRect

    static func fullScreen(_ screen: NSScreen) -> RecordingArea {
        RecordingArea(screen: screen, rect: screen.frame)
    }

    static func region(_ screenRect: CGRect, on screen: NSScreen) -> RecordingArea {
        let global = CGRect(x: screen.frame.minX + screenRect.minX, y: screen.frame.maxY - screenRect.maxY, width: screenRect.width, height: screenRect.height)
        return RecordingArea(screen: screen, rect: global)
    }
}

enum OverlayGeometry {
    static func localPoint(_ globalPoint: CGPoint, in windowFrame: CGRect) -> CGPoint {
        CGPoint(x: globalPoint.x - windowFrame.minX, y: windowFrame.maxY - globalPoint.y)
    }

    static func localRect(_ globalRect: CGRect, in windowFrame: CGRect) -> CGRect {
        CGRect(x: globalRect.minX - windowFrame.minX, y: windowFrame.maxY - globalRect.maxY, width: globalRect.width, height: globalRect.height)
    }
}

@MainActor
final class InputOverlayController {
    private static let rippleLifetime: Duration = .milliseconds(700)
    private static let keystrokeLifetime: TimeInterval = 1.6

    private var overlays: [(window: NSPanel, model: InputOverlayModel)] = []
    private let monitor = InputEventMonitor()
    private var ticker = KeystrokeTicker()
    private var hideTask: Task<Void, Never>?
    private var shortcutsOnly = true

    private(set) var drawsClicks = false

    var windowIDs: [CGWindowID] {
        overlays.map { CGWindowID($0.window.windowNumber) }
    }

    func start(areas: [RecordingArea], showsClicks: Bool, showsKeystrokes: Bool, shortcutsOnly: Bool) {
        stop()
        guard showsClicks || showsKeystrokes, !areas.isEmpty else { return }
        self.shortcutsOnly = shortcutsOnly
        overlays = areas.map(makeOverlay)
        overlays.forEach { $0.window.orderFrontRegardless() }

        if showsClicks {
            monitor.onClick = { [weak self] in self?.showRipple(at: $0) }
            monitor.startClicks()
            drawsClicks = true
        }
        if showsKeystrokes {
            monitor.onKey = { [weak self] in self?.showKey($0) }
            if !monitor.startKeys() {
                Log.capture.info("Keystrokes are hidden because Input Monitoring isn't allowed")
            }
        }
    }

    func stop() {
        monitor.stop()
        monitor.onClick = nil
        monitor.onKey = nil
        hideTask?.cancel()
        hideTask = nil
        ticker = KeystrokeTicker()
        drawsClicks = false
        overlays.forEach { $0.window.orderOut(nil) }
        overlays.removeAll()
    }

    private func makeOverlay(for area: RecordingArea) -> (window: NSPanel, model: InputOverlayModel) {
        let frame = area.screen.frame
        let model = InputOverlayModel(keystrokeAnchor: OverlayGeometry.localRect(area.rect, in: frame))
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .recordingOverlay
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: InputOverlayView(model: model))
        panel.setFrame(frame, display: false)
        return (panel, model)
    }

    private func showRipple(at globalPoint: CGPoint) {
        guard let overlay = overlays.first(where: { $0.window.frame.contains(globalPoint) }) else { return }
        let ripple = InputOverlayModel.Ripple(point: OverlayGeometry.localPoint(globalPoint, in: overlay.window.frame))
        overlay.model.ripples.append(ripple)
        Task { @MainActor [weak model = overlay.model] in
            try? await Task.sleep(for: Self.rippleLifetime)
            model?.ripples.removeAll { $0.id == ripple.id }
        }
    }

    private func showKey(_ event: RawKeyEvent) {
        guard !event.isRepeat,
              let keystroke = KeystrokeFormatter.keystroke(
                  keyCode: event.keyCode,
                  characters: event.characters,
                  baseCharacters: event.baseCharacters,
                  modifiers: event.modifiers,
                  shortcutsOnly: shortcutsOnly
              )
        else { return }
        ticker.register(keystroke, at: Date())
        let text = ticker.text
        withAnimation(.easeOut(duration: 0.12)) {
            overlays.forEach { $0.model.keystrokeText = text }
        }
        scheduleKeystrokeHide()
    }

    private func scheduleKeystrokeHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.keystrokeLifetime))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.overlays.forEach { $0.model.keystrokeText = nil }
            }
        }
    }
}

extension NSWindow.Level {
    static let recordingOverlay = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
    static let recordingBubble = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) - 1)
}

struct InputOverlayView: View {
    @ObservedObject var model: InputOverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.ripples) { ripple in
                ClickRipple()
                    .position(ripple.point)
            }
            if let text = model.keystrokeText {
                KeystrokeBadge(text: text)
                    .position(x: model.keystrokeAnchor.midX, y: max(model.keystrokeAnchor.minY + 40, model.keystrokeAnchor.maxY - 64))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct ClickRipple: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(Color.yellow.opacity(0.28))
            .overlay(Circle().strokeBorder(Color.yellow, lineWidth: 3))
            .frame(width: 46, height: 46)
            .scaleEffect(expanded ? 1.5 : 0.45)
            .opacity(expanded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { expanded = true }
            }
    }
}

struct KeystrokeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.72))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }
            .fixedSize()
    }
}
