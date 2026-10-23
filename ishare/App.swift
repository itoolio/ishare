import Defaults
import MenuBarExtraAccess
import SwiftUI

#if GITHUB_RELEASE
    import Sparkle

    @MainActor
    final class SparkleUpdater: NSObject {
        let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        @MainActor func checkForUpdates() {
            updaterController.checkForUpdates(nil)
        }
    }
#endif

@main
struct ishare: App {
    @Default(.menuBarIcon) var menubarIcon
    @StateObject private var menu = MenuController.shared
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MainMenuView()
        } label: {
            switch menubarIcon {
            case .DEFAULT: Image(.menubar)
            case .APPICON: Image(nsImage: AppIcon)
            case .SYSTEM: Image(systemName: "photo.on.rectangle.angled")
            }
        }
        .menuBarExtraAccess(isPresented: $menu.isPresented) { statusItem in
            StatusItemController.shared.attach(statusItem)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
        Window("Welcome to ishare".localized(), id: Onboarding.windowID) {
            OnboardingView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(Onboarding.shouldPresentAtLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let sharedInstance = AppDelegate()
    static var shared: AppDelegate { sharedInstance }

    let screenRecorder = ScreenRecorder()

    #if GITHUB_RELEASE
        private let updater = SparkleUpdater()
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        if !ScreenshotMode.isActive {
            Migrations.run()
        }
        SaveLocation.activateAll()
        if !ScreenshotMode.isActive {
            applyHistoryLimits()
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        ScreenshotMode.prepareIfNeeded()
        BackgroundMaintenance.start()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        false
    }

    @objc func uploadFiles(_ pasteboard: NSPasteboard, userData _: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let payload = ExternalUpload.payload(from: pasteboard) else {
            error.pointee = "No files to upload".localized() as NSString
            return
        }
        Task { @MainActor in
            await ExternalUpload.upload(payload)
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                importIscu(url)
            } else {
                handle(url)
            }
        }
    }

    private func handle(_ url: URL) {
        Log.app.info("Handling \(url.absoluteString, privacy: .public)")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host() {
        case "upload":
            guard let value = items.first(where: { $0.name == "file" })?.value,
                  let decoded = value.removingPercentEncoding,
                  let fileURL = URL(string: decoded)
            else { return }
            Task { @MainActor in
                await UploadCoordinator.upload(fileURL: fileURL)
                await showToast(fileURL: fileURL)
            }
        case "capture":
            let type = items.first(where: { $0.name == "type" })?.value.flatMap { CaptureType(rawValue: $0.uppercased()) } ?? .REGION
            Task { @MainActor in
                await CaptureSession.captureImage(type)
            }
        case "record":
            let gif = items.contains { $0.name == "gif" && $0.value != "0" }
            let region = items.contains { $0.name == "region" && $0.value != "0" }
            CaptureSession.toggleRecording(gif: gif, region: region)
        default:
            break
        }
    }

    func stopRecording() {
        CaptureSession.stopRecording()
    }

    func checkForUpdates() {
        #if GITHUB_RELEASE
            updater.checkForUpdates()
        #endif
    }
}
