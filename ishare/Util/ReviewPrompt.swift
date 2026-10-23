import AppKit
import Defaults
import Foundation
#if APP_STORE
import StoreKit
#endif

struct ReviewPromptState: Codable, Equatable, Sendable, Defaults.Serializable {
    var installDate: Date?
    var successesSincePrompt = 0
    var lastFailure: Date?
    var lastPrompt: Date?
}

struct ReviewPromptPolicy: Sendable {
    static let day: TimeInterval = 24 * 60 * 60

    var requiredSuccesses = 10
    var cooldown: TimeInterval = 90 * day
    var installGracePeriod: TimeInterval = 3 * day
    var failureGracePeriod: TimeInterval = 3 * day

    func recording(succeeded: Bool, in state: ReviewPromptState, now: Date, installedAt: Date? = nil) -> ReviewPromptState {
        var state = state
        if state.installDate == nil {
            state.installDate = min(installedAt ?? now, now)
        }
        if succeeded {
            state.successesSincePrompt += 1
        } else {
            state.lastFailure = now
        }
        return state
    }

    func isEligible(_ state: ReviewPromptState, now: Date) -> Bool {
        guard state.successesSincePrompt >= requiredSuccesses,
              let installDate = state.installDate,
              now.timeIntervalSince(installDate) >= installGracePeriod
        else { return false }
        if let lastFailure = state.lastFailure, now.timeIntervalSince(lastFailure) < failureGracePeriod {
            return false
        }
        if let lastPrompt = state.lastPrompt, now.timeIntervalSince(lastPrompt) < cooldown {
            return false
        }
        return true
    }

    func prompted(_ state: ReviewPromptState, now: Date) -> ReviewPromptState {
        var state = state
        state.lastPrompt = now
        state.successesSincePrompt = 0
        return state
    }
}

struct ReviewPromptMoment: Equatable, Sendable {
    var isRecording = false
    var isUploading = false
    var hasModalWindow = false
    var hasSheet = false
    var hasFloatingPanel = false

    var isCalm: Bool {
        !isRecording && !isUploading && !hasModalWindow && !hasSheet && !hasFloatingPanel
    }
}

@MainActor
enum ReviewPrompt {
    static var policy = ReviewPromptPolicy()
    static var clock: () -> Date = Date.init

    static var isSupported: Bool {
        #if APP_STORE
        !ScreenshotMode.isActive && !RuntimeEnvironment.isRunningTests
        #else
        false
        #endif
    }

    static func uploadFinished(succeeded: Bool) {
        guard isSupported else { return }
        let now = clock()
        let state = policy.recording(succeeded: succeeded, in: Defaults[.reviewPromptState], now: now, installedAt: oldestHistoryDate)
        Defaults[.reviewPromptState] = state
        guard succeeded, policy.isEligible(state, now: now) else { return }
        ReviewPromptPresenter.scheduleWhenCalm()
    }

    static var oldestHistoryDate: Date? {
        Defaults[.uploadHistory].compactMap(\.date).min()
    }

    static func currentMoment() -> ReviewPromptMoment {
        let visible = NSApp.windows.filter(\.isVisible)
        return ReviewPromptMoment(
            isRecording: CaptureSession.isRecording,
            isUploading: UploadManager.shared.isUploading,
            hasModalWindow: NSApp.modalWindow != nil,
            hasSheet: visible.contains { $0.attachedSheet != nil || $0.isSheet },
            hasFloatingPanel: visible.contains { $0.level >= .floating && !isStatusBarWindow($0) }
        )
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBar")
    }
}

@MainActor
enum ReviewPromptPresenter {
    static let settleDelay: Duration = .seconds(3)
    static let retryInterval: Duration = .seconds(5)
    static let maximumAttempts = 24
    private static var pending: Task<Void, Never>?
    private static var hostWindow: NSWindow?

    static func scheduleWhenCalm() {
        guard pending == nil else { return }
        pending = Task { @MainActor in
            defer { pending = nil }
            try? await Task.sleep(for: .seconds(Defaults[.toastTimeout]) + settleDelay)
            for _ in 0 ..< maximumAttempts {
                guard !Task.isCancelled else { return }
                if ReviewPrompt.currentMoment().isCalm {
                    present()
                    return
                }
                try? await Task.sleep(for: retryInterval)
            }
        }
    }

    private static func present() {
        let now = ReviewPrompt.clock()
        let state = Defaults[.reviewPromptState]
        guard ReviewPrompt.policy.isEligible(state, now: now) else { return }
        Defaults[.reviewPromptState] = ReviewPrompt.policy.prompted(state, now: now)
        #if APP_STORE
        Log.upload.info("Requesting an App Store review")
        AppStore.requestReview(in: hostViewController())
        #endif
    }

    private static func hostViewController() -> NSViewController {
        if let controller = NSApp.keyWindow?.contentViewController {
            return controller
        }
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.midX, y: screen.frame.midY))
        }
        window.orderFrontRegardless()
        hostWindow = window
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            hostWindow?.close()
            hostWindow = nil
        }
        return controller
    }
}
