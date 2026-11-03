import AppKit
import Defaults
import ishareCore

@MainActor
enum PresentationHold {
    private static var held = HeldResults<HeldToast>()
    private static var watcher: Task<Void, Never>?
    static let pollInterval: Duration = .seconds(3)

    struct HeldToast: Sendable {
        let model: ToastModel
        let minimumTimeout: Double
    }

    static var isPresenting: Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = FocusedWindowSampler.onScreenWindows().map { window in
            var described = window
            described.ownerBundleID = window.ownerPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            return described
        }
        let displays = NSScreen.screens.compactMap(\.displayID).map(CGDisplayBounds)
        return PresentationDetector.isPresenting(windows: windows, displays: displays, ownPID: ownPID)
    }

    static func holdsIfPresenting(_ model: ToastModel, minimumTimeout: Double) -> Bool {
        guard Defaults[.holdResultsWhilePresenting], !ScreenshotMode.isActive, isPresenting else { return false }
        held.hold(HeldToast(model: model, minimumTimeout: minimumTimeout))
        watchUntilPresentationEnds()
        return true
    }

    private static func watchUntilPresentationEnds() {
        guard watcher == nil else { return }
        watcher = Task { @MainActor in
            while !Task.isCancelled, isPresenting {
                try? await Task.sleep(for: pollInterval)
            }
            watcher = nil
            for toast in held.release() {
                Task { @MainActor in await ToastController.show(model: toast.model, minimumTimeout: toast.minimumTimeout) }
            }
        }
    }
}
