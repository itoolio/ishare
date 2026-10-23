import AppKit
import SwiftUI

@MainActor
struct MenuActions {
    static let captureTypes: [CaptureType] = [.REGION, .WINDOW, .SCREEN, .SCROLLING]

    static var showsDonate: Bool {
        #if GITHUB_RELEASE
            !ScreenshotMode.isActive
        #else
            false
        #endif
    }

    let menu: MenuController

    func dismiss() {
        menu.dismiss()
    }

    func run(_ action: @escaping @MainActor () async -> Void) {
        menu.perform(afterDismissing: action)
    }

    func triggerCapture(_ index: Int) {
        guard Self.captureTypes.indices.contains(index) else { return }
        let type = Self.captureTypes[index]
        run { await CaptureSession.captureImage(type) }
    }

    func toggleRecording(gif: Bool, region: Bool = false) {
        run { CaptureSession.toggleRecording(gif: gif, region: region) }
    }

    func stopRecording() {
        CaptureSession.stopRecording()
        dismiss()
    }

    func editImage() {
        run { await ImageEditor.chooseAndEdit() }
    }

    func uploadClipboard() {
        run { await AppState.uploadPasteboard() }
    }

    func openHistory(_ history: [HistoryItem]) {
        dismiss()
        openHistoryWindow(uploadHistory: history)
    }

    func openDonation() {
        dismiss()
        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/castdrian")!)
    }

    func openSettings(_ openSettings: OpenSettingsAction) {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    func showDestinationMenu(from anchor: ViewAnchor) {
        AppKitMenuPresenter.popUp(MenuAppKitMenus.destinationMenu(), from: anchor)
    }

    func showOverflowMenu(from anchor: ViewAnchor, openWindow: OpenWindowAction) {
        let overflow = MenuAppKitMenus.overflowMenu(
            openOnboarding: { [menu] in
                menu.dismiss()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: Onboarding.windowID)
            },
            openCommandPalette: { [menu] in menu.showsCommandPalette = true }
        )
        AppKitMenuPresenter.popUp(overflow, from: anchor)
    }

    func showRecentLinksMenu(history: [HistoryItem], from anchor: ViewAnchor) {
        guard let submenu = MenuAppKitMenus.recentLinksItem(history: history).submenu else { return }
        AppKitMenuPresenter.popUp(submenu, from: anchor)
    }
}
