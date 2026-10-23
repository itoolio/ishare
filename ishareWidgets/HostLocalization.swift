import Foundation

enum HostLocalization {
    static let appBundle: Bundle = {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard appURL.pathExtension == "app", let bundle = Bundle(url: appURL) else { return .main }
        return bundle
    }()

    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(appBundle.bundleURL))
    }
}

extension String {
    func localized() -> String {
        HostLocalization.appBundle.localizedString(forKey: self, value: self, table: nil)
    }
}
