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
                Picker("Language".localized(), selection: Binding(
                    get: { language },
                    set: { if $0 != language { pendingLanguage = .some($0) } }
                )) {
                    Text("System Default".localized()).tag(LanguageTypes?.none)
                    Divider()
                    ForEach(LanguageTypes.allCases, id: \.self) { language in
                        Text(language.name).tag(LanguageTypes?.some(language))
                    }
                }
                LaunchAtLogin.Toggle {
                    Text("Launch at login".localized())
                }
                Toggle("Land down under".localized(), isOn: $aussieMode)
            }
            Section("Menu Bar Icon".localized()) {
                Picker("Menu Bar Icon".localized(), selection: $menubarIcon) {
                    Image(.menubar).tag(MenuBarIcon.DEFAULT)
                    Image(nsImage: AppIcon).tag(MenuBarIcon.APPICON)
                    Image(systemName: "photo.on.rectangle.angled").tag(MenuBarIcon.SYSTEM)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            MenuLayoutSettingsSection()
            AppearanceSettingsSection()
            Section("Clipboard".localized()) {
                Toggle("Copy image to clipboard instead of URL".localized(), isOn: $copyImageToClipboard)
            }
            Section("Toast".localized()) {
                LabeledContent(String(format: "Toast Timeout: %d seconds".localized(), Int(toastTimeout))) {
                    Slider(value: $toastTimeout, in: 1 ... 10, step: 1)
                        .frame(width: 220)
                }
                ToastPlacementSettings()
                ResultPresentationSettings()
            }
            SoundSettingsSection()
            HistorySettingsSection()
        }
        .formStyle(.grouped)
        .alert("Language Change".localized(), isPresented: Binding(
            get: { pendingLanguage != nil },
            set: { if !$0 { pendingLanguage = nil } }
        )) {
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
