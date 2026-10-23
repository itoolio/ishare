import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class SystemContrastObserver: ObservableObject {
    static let shared = SystemContrastObserver()

    @Published private(set) var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
    }

    static var currentContrast: MenuContrast {
        MenuContrast.resolve(userPreference: Defaults[.highContrastMenu], systemIncreaseContrast: shared.increaseContrast)
    }
}

private struct MenuContrastKey: EnvironmentKey {
    static let defaultValue = MenuContrast.standard
}

private struct MenuMetricsKey: EnvironmentKey {
    static let defaultValue = MenuDensity.comfortable.metrics
}

extension EnvironmentValues {
    var menuContrast: MenuContrast {
        get { self[MenuContrastKey.self] }
        set { self[MenuContrastKey.self] = newValue }
    }

    var menuMetrics: MenuMetrics {
        get { self[MenuMetricsKey.self] }
        set { self[MenuMetricsKey.self] = newValue }
    }
}

private struct WindowAppearanceSetter: NSViewRepresentable {
    let theme: MenuTheme

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        apply(to: view)
    }

    private func apply(to view: NSView) {
        let appearance = theme.appearance
        DispatchQueue.main.async {
            guard let window = view.window, window.appearance?.name != appearance?.name else { return }
            window.appearance = appearance
        }
    }
}

private struct MenuAppearanceModifier: ViewModifier {
    let appliesToWindow: Bool
    @Default(.menuTheme) private var theme
    @Default(.highContrastMenu) private var highContrast
    @Default(.menuDensity) private var density
    @ObservedObject private var system = SystemContrastObserver.shared

    func body(content: Content) -> some View {
        let contrast = MenuContrast.resolve(userPreference: highContrast, systemIncreaseContrast: system.increaseContrast)
        content
            .environment(\.menuContrast, contrast)
            .environment(\.menuMetrics, density.metrics)
            .background {
                if appliesToWindow {
                    WindowAppearanceSetter(theme: theme)
                        .frame(width: 0, height: 0)
                }
            }
    }
}

extension View {
    func menuAppearance(appliesToWindow: Bool = true) -> some View {
        modifier(MenuAppearanceModifier(appliesToWindow: appliesToWindow))
    }
}

extension Font.Weight {
    func emphasized(_ contrast: MenuContrast) -> Font.Weight {
        guard contrast.isHigh else { return self }
        switch self {
        case .regular: return .medium
        case .medium: return .semibold
        case .semibold: return .bold
        default: return self
        }
    }
}
