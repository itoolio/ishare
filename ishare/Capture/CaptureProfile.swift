import Defaults
import Foundation

struct CaptureProfile: Codable, Hashable, Identifiable, Sendable, Defaults.Serializable {
    var id = UUID()
    var bundleIdentifier: String
    var appName: String
    var isEnabled = true
    var addsBackground: Bool?
    var blursPrivateApps: Bool?
    var includesWindowShadow: Bool?
    var fileNamePrefix: String?
}

struct CaptureSettings: Hashable, Sendable {
    var addsBackground: Bool
    var blursPrivateApps: Bool
    var includesWindowShadow: Bool
    var fileNamePrefix: String

    func applying(_ profile: CaptureProfile?) -> CaptureSettings {
        guard let profile, profile.isEnabled else { return self }
        var result = self
        result.addsBackground = profile.addsBackground ?? addsBackground
        result.blursPrivateApps = profile.blursPrivateApps ?? blursPrivateApps
        result.includesWindowShadow = profile.includesWindowShadow ?? includesWindowShadow
        if let prefix = profile.fileNamePrefix?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty {
            result.fileNamePrefix = prefix
        }
        return result
    }
}

enum CaptureProfileMatcher {
    static func profile(for bundleIdentifier: String?, in profiles: [CaptureProfile]) -> CaptureProfile? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return profiles.first { $0.isEnabled && $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }

    static func settings(for bundleIdentifier: String?, global: CaptureSettings, profiles: [CaptureProfile]) -> CaptureSettings {
        global.applying(profile(for: bundleIdentifier, in: profiles))
    }
}

extension CaptureSettings {
    @MainActor static var global: CaptureSettings {
        CaptureSettings(
            addsBackground: Defaults[.beautifyEnabled],
            blursPrivateApps: true,
            includesWindowShadow: Defaults[.windowShadow],
            fileNamePrefix: Defaults[.captureFileName]
        )
    }

    @MainActor static func current(for bundleIdentifier: String?) -> CaptureSettings {
        CaptureProfileMatcher.settings(for: bundleIdentifier, global: global, profiles: Defaults[.captureProfiles])
    }
}

enum WindowTitleName {
    static let maximumLength = 60

    static func component(fromTitle title: String?, appName: String?) -> String? {
        guard var title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        title = strippingAppName(from: title, appName: appName)
        let sanitized = CaptureFileName.sanitize(title)
            .replacing(/\s+/, with: "-")
            .replacing(/-{2,}/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-.").union(.whitespaces))
        let truncated = String(sanitized.prefix(maximumLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return truncated.isEmpty ? nil : truncated
    }

    static func strippingAppName(from title: String, appName: String?) -> String {
        guard let appName = appName?.trimmingCharacters(in: .whitespaces), !appName.isEmpty else { return title }
        for separator in [" - ", " — ", " – ", " | "] {
            let suffix = separator + appName
            if title.count > suffix.count, title.lowercased().hasSuffix(suffix.lowercased()) {
                return String(title.dropLast(suffix.count))
            }
        }
        return title
    }

    static func fileName(title: String?, appName: String?, fallbackPrefix: String, fallbackSuffix: String?, ext: String, date: Date = .init()) -> String {
        guard let component = component(fromTitle: title, appName: appName) else {
            return CaptureFileName.make(prefix: fallbackPrefix, suffix: fallbackSuffix, ext: ext, date: date)
        }
        return "\(component)-\(Int(date.timeIntervalSince1970)).\(ext.lowercased())"
    }
}
