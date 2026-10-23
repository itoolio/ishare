import AppKit
import Defaults
import SwiftUI
import UserNotifications

struct MenuLayoutSettingsSection: View {
    @Default(.menuSectionOrder) private var order
    @Default(.hiddenMenuSections) private var hidden
    @Default(.menuDensity) private var density

    private var layout: MenuLayout {
        MenuLayout(order: order, hidden: hidden)
    }

    var body: some View {
        Section {
            Picker(Self.density.title.localized(), selection: $density) {
                ForEach(MenuDensity.allCases) { Text($0.title.localized()).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.menu.density")
            .settingsEntry(Self.density)
            ForEach(Array(layout.order.enumerated()), id: \.element) { index, section in
                row(section, index: index)
            }
            Button("Restore Default Layout".localized()) {
                MenuLayout.current = MenuLayout()
            }
            .disabled(layout == MenuLayout())
            .accessibilityIdentifier("settings.menu.reset")
            .settingsEntry(Self.layout)
        } header: {
            Text(Self.layout.title.localized())
        } footer: {
            Text("Choose which sections the menu shows and in which order.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ section: MenuSection, index: Int) -> some View {
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { layout.isVisible(section) },
                    set: { MenuLayout.current = layout.setting(section, visible: $0) }
                )
            ) {
                Label(section.title.localized(), systemImage: section.symbol)
            }
            .accessibilityIdentifier("settings.menu.section.\(section.rawValue)")
            Spacer()
            Button {
                MenuLayout.current = layout.moving(section, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move Up".localized())
            .accessibilityLabel(String(format: "Move %@ Up".localized(), section.title.localized()))
            .accessibilityIdentifier("settings.menu.section.\(section.rawValue).up")
            Button {
                MenuLayout.current = layout.moving(section, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == layout.order.count - 1)
            .help("Move Down".localized())
            .accessibilityLabel(String(format: "Move %@ Down".localized(), section.title.localized()))
            .accessibilityIdentifier("settings.menu.section.\(section.rawValue).down")
        }
        .buttonStyle(.borderless)
    }
}

struct AppearanceSettingsSection: View {
    @Default(.menuTheme) private var theme
    @Default(.highContrastMenu) private var highContrast
    @ObservedObject private var system = SystemContrastObserver.shared

    var body: some View {
        Section(Self.appearance.title.localized()) {
            Picker("Menu theme".localized(), selection: $theme) {
                ForEach(MenuTheme.allCases) { Text($0.title.localized()).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance.theme")
            .settingsEntry(Self.appearance)
            Toggle(isOn: $highContrast) {
                Text(Self.highContrast.title.localized())
                if system.increaseContrast {
                    Text("“Increase contrast” is turned on in Accessibility settings, so the menu already uses high contrast.".localized())
                }
            }
            .accessibilityIdentifier("settings.appearance.highContrast")
            .settingsEntry(Self.highContrast)
            MenuPreview()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }
}

struct MenuPreview: View {
    static let scale: CGFloat = 0.46
    @Default(.menuTheme) private var theme

    private var schemes: [ColorScheme] {
        switch theme {
        case .system: [.light, .dark]
        case .light: [.light]
        case .dark: [.dark]
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(schemes, id: \.self) { scheme in
                MenuPreviewTile(scheme: scheme, scale: Self.scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menu preview".localized())
        .accessibilityIdentifier("settings.appearance.preview")
    }
}

private struct MenuPreviewTile: View {
    let scheme: ColorScheme
    let scale: CGFloat
    @State private var height: CGFloat = 480

    var body: some View {
        MainMenuView(isPreview: true)
            .fixedSize(horizontal: false, vertical: true)
            .background(MenuMaterialBackground(scheme: scheme))
            .environment(\.colorScheme, scheme)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                height = $0
            }
            .allowsHitTesting(false)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 360 * scale, height: height * scale, alignment: .topLeading)
    }
}

struct MenuMaterialBackground: NSViewRepresentable {
    let scheme: ColorScheme

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }
}

struct ToastPlacementSettings: View {
    @Default(.toastCorner) private var corner
    @Default(.toastScreen) private var screen

    var body: some View {
        Picker(Self.placement.title.localized(), selection: $corner) {
            ForEach(ToastCorner.allCases) { Text($0.title.localized()).tag($0) }
        }
        .accessibilityIdentifier("settings.toast.corner")
        .settingsEntry(Self.placement)
        Picker("Screen".localized(), selection: $screen) {
            ForEach(ToastScreenChoice.allCases) { Text($0.title.localized()).tag($0) }
        }
        .accessibilityIdentifier("settings.toast.screen")
    }
}

struct ResultPresentationSettings: View {
    @Default(.resultPresentation) private var presentation
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Picker(Self.presentation.title.localized(), selection: $presentation) {
            ForEach(ResultPresentation.allCases) { Text($0.title.localized()).tag($0) }
        }
        .accessibilityIdentifier("settings.toast.presentation")
        .settingsEntry(Self.presentation)
        .onChange(of: presentation) { _, choice in
            guard choice.postsNotification else { return }
            Task { @MainActor in
                _ = await ResultNotifier.shared.requestAuthorization()
                status = await ResultNotifier.shared.authorizationStatus()
            }
        }
        .task {
            guard presentation.postsNotification else { return }
            status = await ResultNotifier.shared.authorizationStatus()
        }
        if presentation.postsNotification, status == .denied {
            LabeledContent {
                Button("Open Notification Settings…".localized()) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
                .accessibilityIdentifier("settings.toast.notificationSettings")
            } label: {
                Text("Notifications are turned off for ishare, so results are shown as toasts.".localized())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension MenuLayoutSettingsSection: SettingsSearchable {
    static let density = SettingsSearchEntry("Density", pane: .general, keywords: ["Compact", "Comfortable"], anchor: SettingsAnchor.menuDensity)
    static let layout = SettingsSearchEntry(
        "Menu", pane: .general, keywords: ["Sections", "Restore Default Layout", "Favorites", "Reorder"], anchor: SettingsAnchor.menuLayout
    )
    static let searchEntries = [density, layout]
}

extension AppearanceSettingsSection: SettingsSearchable {
    static let appearance = SettingsSearchEntry(
        "Appearance", pane: .general, keywords: ["Menu theme", "Dark", "Light", "Menu preview"], anchor: SettingsAnchor.appearance
    )
    static let highContrast = SettingsSearchEntry("High contrast menu", pane: .general, keywords: ["Contrast"], anchor: SettingsAnchor.highContrast)
    static let searchEntries = [appearance, highContrast]
}

extension ToastPlacementSettings: SettingsSearchable {
    static let placement = SettingsSearchEntry("Position", pane: .general, keywords: ["Corner", "Screen"], anchor: SettingsAnchor.toastPlacement)
    static let searchEntries = [placement]
}

extension ResultPresentationSettings: SettingsSearchable {
    static let presentation = SettingsSearchEntry(
        "Show results as", pane: .general, keywords: ["Notification", "Notification Center"], anchor: SettingsAnchor.resultPresentation
    )
    static let searchEntries = [presentation]
}
