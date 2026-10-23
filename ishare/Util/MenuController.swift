import AppKit
import Combine

@MainActor
final class MenuController: ObservableObject {
    static var shared: MenuController { AppModel.shared.menu }

    @Published var isPresented = false
    @Published var showsCommandPalette = false
    var openSettingsAction: (() -> Void)?

    func dismiss() {
        isPresented = false
        showsCommandPalette = false
    }

    func toggle() {
        NSApp.activate(ignoringOtherApps: true)
        if isPresented {
            showsCommandPalette = false
        }
        isPresented.toggle()
    }

    func openCommandPalette() {
        NSApp.activate(ignoringOtherApps: true)
        showsCommandPalette = true
        isPresented = true
    }

    func perform(afterDismissing action: @escaping @MainActor () async -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            await action()
        }
    }

    func openSettings(pane: SettingsPane? = nil) {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        if let pane {
            SettingsNavigator.shared.pane = pane
        }
        openSettingsAction?()
    }

    func showAboutPanel() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(Calendar.current.component(.year, from: Date())) ADRIAN CASTRO"
        ])
    }
}
