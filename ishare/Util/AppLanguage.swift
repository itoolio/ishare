import AppKit
import Defaults
import Foundation

enum LanguageTypes: String, CaseIterable, Defaults.Serializable {
    case english = "en"
    case aussie = "en-AU"
    case arabic = "ar"
    case chinese = "zh-CN"
    case french = "fr"
    case german = "de"
    case hindi = "hi"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case turkish = "tr"
    case ukrainian = "uk"

    var name: String {
        switch self {
        case .english: "English"
        case .aussie: "English (Australia)"
        case .arabic: "عربي"
        case .chinese: "中文"
        case .french: "Français"
        case .german: "Deutsch"
        case .hindi: "हिन्दी"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .spanish: "Español"
        case .turkish: "Türkçe"
        case .ukrainian: "Українська"
        }
    }
}

enum AppLanguage {
    static let preferenceKey = "AppleLanguages"

    static func override(in defaults: UserDefaults = .standard) -> LanguageTypes? {
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        let codes = domain?[preferenceKey] as? [String]
        return codes?.first.flatMap(LanguageTypes.init(rawValue:))
    }

    static func set(_ language: LanguageTypes?, in defaults: UserDefaults = .standard) {
        if let language {
            defaults.set([language.rawValue], forKey: preferenceKey)
        } else {
            defaults.removeObject(forKey: preferenceKey)
        }
        Defaults[.aussieMode] = language == .aussie
    }

    @MainActor static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

extension String {
    func localized() -> String {
        NSLocalizedString(self, comment: "")
    }
}
