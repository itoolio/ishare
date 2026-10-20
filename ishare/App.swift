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
    @Default(.showMainMenu) var showMainMenu
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MainMenuView()
                .environmentObject(LocalizableManager.shared)
        } label: {
            switch menubarIcon {
            case .DEFAULT: Image(.menubar)
            case .APPICON: Image(nsImage: AppIcon)
            case .SYSTEM: Image(systemName: "photo.on.rectangle.angled")
            }
        }
        .menuBarExtraAccess(isPresented: $showMainMenu)
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView()
                .environmentObject(LocalizableManager.shared)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let sharedInstance = AppDelegate()
    static var shared: AppDelegate { sharedInstance }

    var recordGif = false
    var forceUploadRecording = false
    let screenRecorder = ScreenRecorder()

    #if GITHUB_RELEASE
        private let updater = SparkleUpdater()
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        if !ScreenshotMode.isActive {
            Migrations.run()
        }
        SaveLocation.activateAll()
        Defaults[.showMainMenu] = false
        ScreenshotMode.prepareIfNeeded()
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
                await captureScreen(type: type)
            }
        case "record":
            let gif = items.contains { $0.name == "gif" && $0.value != "0" }
            let region = items.contains { $0.name == "region" && $0.value != "0" }
            recordScreen(gif: gif, region: region)
        default:
            break
        }
    }

    func stopRecording() {
        let wasRecordingGif = recordGif
        let forceUpload = forceUploadRecording
        recordGif = false
        forceUploadRecording = false
        Task { @MainActor in
            ContentSharingPickerManager.shared.deactivatePicker()
            switch await screenRecorder.stop() {
            case let .success(url):
                postRecordingTasks(url, wasRecordingGif, forceUpload: forceUpload)
            case let .failure(error):
                NSLog("Error while stopping recording: %@", error.localizedDescription)
            }
        }
    }

    func checkForUpdates() {
        #if GITHUB_RELEASE
            updater.checkForUpdates()
        #endif
    }
}
