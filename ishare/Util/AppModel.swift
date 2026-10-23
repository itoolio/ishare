import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let recorder: ScreenRecorder
    let menu: MenuController
    let settings: SettingsNavigator
    let uploads: UploadManager
    private(set) lazy var uploadQueue = UploadQueue.live()
    private var forwarders: [AnyCancellable] = []

    init(
        recorder: ScreenRecorder = ScreenRecorder(),
        menu: MenuController = MenuController(),
        settings: SettingsNavigator = SettingsNavigator(),
        uploads: UploadManager = UploadManager()
    ) {
        self.recorder = recorder
        self.menu = menu
        self.settings = settings
        self.uploads = uploads
        forwarders = [
            recorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            menu.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
        ]
    }

    var menuActions: MenuActions { MenuActions(menu: menu) }
}

extension View {
    func appModel(_ model: AppModel = .shared) -> some View {
        environmentObject(model)
    }
}
