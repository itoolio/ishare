import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @State private var language = AppLanguage.override()
    @State private var pendingLanguage: LanguageTypes??
    @Default(.menuBarIcon) var menubarIcon
    @Default(.toastTimeout) var toastTimeout
    @Default(.aussieMode) var aussieMode
    @Default(.copyImageToClipboard) var copyImageToClipboard

    var body: some View {
        Form {
            Section {
                Picker(
                    Self.language.title.localized(),
                    selection: Binding(
                        get: { language },
                        set: { if $0 != language { pendingLanguage = .some($0) } }
                    )
                ) {
                    Text("System Default".localized()).tag(LanguageTypes?.none)
                    Divider()
                    ForEach(LanguageTypes.allCases, id: \.self) { language in
                        Text(language.name).tag(LanguageTypes?.some(language))
                    }
                }
                .settingsEntry(Self.language)
                LaunchAtLogin.Toggle {
                    Text(Self.launchAtLogin.title.localized())
                }
                .settingsEntry(Self.launchAtLogin)
                Toggle(Self.aussieMode.title.localized(), isOn: $aussieMode)
                    .settingsEntry(Self.aussieMode)
            }
            Section(Self.menuBarIcon.title.localized()) {
                Picker(Self.menuBarIcon.title.localized(), selection: $menubarIcon) {
                    Image(.menubar).tag(MenuBarIcon.DEFAULT)
                    Image(nsImage: AppIcon).tag(MenuBarIcon.APPICON)
                    Image(systemName: "photo.on.rectangle.angled").tag(MenuBarIcon.SYSTEM)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .settingsEntry(Self.menuBarIcon)
            }
            MenuLayoutSettingsSection()
            AppearanceSettingsSection()
            Section(Self.clipboard.title.localized()) {
                Toggle("Copy image to clipboard instead of URL".localized(), isOn: $copyImageToClipboard)
                    .settingsEntry(Self.clipboard)
            }
            Section(Self.toast.title.localized()) {
                LabeledContent(String(format: "Toast Timeout: %d seconds".localized(), Int(toastTimeout))) {
                    Slider(value: $toastTimeout, in: 1 ... 10, step: 1)
                        .frame(width: 220)
                }
                .settingsEntry(Self.toast)
                ToastPlacementSettings()
                ResultPresentationSettings()
            }
            SoundSettingsSection()
            HistorySettingsSection()
        }
        .settingsPaneStyle()
        .alert(
            "Language Change".localized(),
            isPresented: Binding(
                get: { pendingLanguage != nil },
                set: { if !$0 { pendingLanguage = nil } }
            )
        ) {
            Button("Restart Now".localized(), role: .destructive) {
                guard let choice = pendingLanguage else { return }
                AppLanguage.set(choice)
                language = choice
                AppLanguage.relaunch()
            }
            Button("Cancel".localized(), role: .cancel) {}
        } message: {
            Text("ishare restarts to apply the new language.".localized())
        }
    }
}

extension GeneralSettingsView: SettingsSearchable {
    static let language = SettingsSearchEntry("Language", pane: .general, anchor: SettingsAnchor.language)
    static let launchAtLogin = SettingsSearchEntry("Launch at login", pane: .general, keywords: ["Startup"], anchor: SettingsAnchor.launchAtLogin)
    static let aussieMode = SettingsSearchEntry("Land down under", pane: .general, anchor: SettingsAnchor.aussieMode)
    static let menuBarIcon = SettingsSearchEntry("Menu Bar Icon", pane: .general, keywords: ["Icon"], anchor: SettingsAnchor.menuBarIcon)
    static let clipboard = SettingsSearchEntry(
        "Clipboard", pane: .general, keywords: ["Copy image to clipboard instead of URL"], anchor: SettingsAnchor.clipboard
    )
    static let toast = SettingsSearchEntry("Toast", pane: .general, keywords: ["Toast Timeout"], anchor: SettingsAnchor.toastTimeout)

    static var searchEntries: [SettingsSearchEntry] {
        [language, launchAtLogin, aussieMode, menuBarIcon, clipboard, toast]
            + MenuLayoutSettingsSection.searchEntries
            + AppearanceSettingsSection.searchEntries
            + ToastPlacementSettings.searchEntries
            + ResultPresentationSettings.searchEntries
            + SoundSettingsSection.searchEntries
            + HistorySettingsSection.searchEntries
    }
}
