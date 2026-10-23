import AppKit
import SwiftUI

@MainActor
enum MenuActions {
    static let captureTypes: [CaptureType] = [.REGION, .WINDOW, .SCREEN, .SCROLLING]

    static var showsDonate: Bool {
        #if GITHUB_RELEASE
            !ScreenshotMode.isActive
        #else
            false
        #endif
    }

    static func dismiss() {
        MenuController.shared.dismiss()
    }

    static func run(_ action: @escaping @MainActor () async -> Void) {
        MenuController.shared.perform(afterDismissing: action)
    }

    static func triggerCapture(_ index: Int) {
        guard captureTypes.indices.contains(index) else { return }
        let type = captureTypes[index]
        run { await CaptureSession.captureImage(type) }
    }

    static func toggleRecording(gif: Bool, region: Bool = false) {
        run { CaptureSession.toggleRecording(gif: gif, region: region) }
    }

    static func stopRecording() {
        CaptureSession.stopRecording()
        dismiss()
    }

    static func editImage() {
        run { await ImageEditor.chooseAndEdit() }
    }

    static func uploadClipboard() {
        run { await AppState.uploadPasteboard() }
    }

    static func openHistory(_ history: [HistoryItem]) {
        dismiss()
        openHistoryWindow(uploadHistory: history)
    }

    static func openDonation() {
        dismiss()
        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/castdrian")!)
    }

    static func openSettings(_ openSettings: OpenSettingsAction) {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    static func showDestinationMenu(from anchor: ViewAnchor) {
        AppKitMenuPresenter.popUp(MenuAppKitMenus.destinationMenu(), from: anchor)
    }

    static func showOverflowMenu(from anchor: ViewAnchor, openWindow: OpenWindowAction) {
        let overflow = MenuAppKitMenus.overflowMenu(
            openOnboarding: {
                MenuController.shared.dismiss()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: Onboarding.windowID)
            },
            openCommandPalette: { MenuController.shared.showsCommandPalette = true }
        )
        AppKitMenuPresenter.popUp(overflow, from: anchor)
    }

    static func showRecentLinksMenu(history: [HistoryItem], from anchor: ViewAnchor) {
        guard let submenu = MenuAppKitMenus.recentLinksItem(history: history).submenu else { return }
        AppKitMenuPresenter.popUp(submenu, from: anchor)
    }
}
