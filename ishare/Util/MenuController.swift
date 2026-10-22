import AppKit
import Combine

@MainActor
final class MenuController: ObservableObject {
    static let shared = MenuController()

    @Published var isPresented = false

    func dismiss() {
        isPresented = false
    }

    func toggle() {
        NSApp.activate(ignoringOtherApps: true)
        isPresented.toggle()
    }

    func perform(afterDismissing action: @escaping @MainActor () async -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            await action()
        }
    }
}
