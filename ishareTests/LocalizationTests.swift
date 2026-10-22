import Foundation
import Testing
@testable import ishare

struct LocalizationTests {
    static let languages = ["ar", "de", "es", "fr", "hi", "ja", "ko", "tr", "uk", "zh-CN"]

    struct Catalog {
        let strings: [String: [String: String]]

        init() throws {
            let data = try Fixtures.data("ishare/Localizable.xcstrings")
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let entries = try #require(json["strings"] as? [String: Any])
            var strings: [String: [String: String]] = [:]
            for (key, value) in entries {
                let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
                strings[key] = localizations.compactMapValues { localization in
                    ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                }
            }
            self.strings = strings
        }
    }

    static func sourceKeys() throws -> Set<String> {
        let root = Fixtures.url("ishare")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let pattern = /"((?:[^"\\]|\\.)*)"\.localized\(\)/
        var keys = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for match in source.matches(of: pattern) {
                keys.insert(String(match.output.1))
            }
        }
        return keys
    }

    @MainActor static var indirectKeys: Set<String> {
        var keys = Set<String>()
        keys.formUnion(SettingsPane.allCases.map(\.title))
        keys.formUnion(EditorTool.allCases.map(\.title))
        keys.formUnion(ScreenshotScene.allCases.flatMap { [$0.title, $0.subtitle] })
        keys.insert(RecordingResolution.native.title)
        keys.formUnion([PermissionKind.screenRecording, .accessibility].flatMap { [$0.title, $0.instructions] })
        keys.insert(CompressionPreset.medium.title)
        let issues: [UploaderIssue] = [
            .missingName, .invalidRequestURL, .missingResponseURL, .malformedTemplate(field: "response URL"),
            .emptyFileFormName, .missingS3Configuration, .invalidS3Endpoint, .missingS3Field("bucket"),
        ]
        keys.formUnion(issues.map(\.messageKey))
        keys.formUnion(["response URL", "deletion URL", "key", "public URL", "bucket", "region", "access key ID", "secret access key"])
        keys.formUnion(OnboardingStep.allCases.flatMap { [$0.title, $0.subtitle] })
        keys.formUnion(HistoryKindFilter.allCases.map(\.title))
        keys.formUnion([
            "Use Imgur", "Free anonymous image hosting, ready to go.",
            "Import .iscu File…", "Load a custom uploader shared by your server or a friend.",
            "Set Up an Uploader…", "Configure your own server or S3-compatible storage in Settings.",
            "Capture Region", "Capture Window", "Capture Screen", "Record Screen", "Open Main Menu", "Open History Window",
            "Copy", "Copy URL", "Open", "Edit", "Delete",
        ])
        return keys
    }

    @Test @MainActor func everyKeyIsTranslatedIntoEveryLanguage() throws {
        let catalog = try Catalog()
        let keys = try Self.sourceKeys().union(Self.indirectKeys)
        var missing: [String] = []
        for key in keys.sorted() {
            let translations = catalog.strings[key] ?? [:]
            for language in Self.languages where translations[language]?.isEmpty ?? true {
                missing.append("\(language): \(key)")
            }
        }
        #expect(missing.isEmpty, "Missing translations:\n\(missing.joined(separator: "\n"))")
    }

    @Test func translationsKeepFormatSpecifiersAndPlaceholders() throws {
        let catalog = try Catalog()
        let specifier = /%(?:\d+\$)?[@dfs]/
        let placeholder = /\{\{[^}]*\}\}/
        var mismatches: [String] = []
        for (key, translations) in catalog.strings {
            let expectedSpecifiers = key.matches(of: specifier).map { String($0.output) }.sorted()
            let expectedPlaceholders = key.matches(of: placeholder).map { String($0.output) }.sorted()
            for (language, value) in translations {
                let specifiers = value.matches(of: specifier).map { String($0.output) }.sorted()
                let placeholders = value.matches(of: placeholder).map { String($0.output) }.sorted()
                if specifiers != expectedSpecifiers || placeholders != expectedPlaceholders {
                    mismatches.append("\(language): \(key) → \(value)")
                }
            }
        }
        #expect(mismatches.isEmpty, "Mismatched tokens:\n\(mismatches.joined(separator: "\n"))")
    }

    @Test func germanUsesTheCorrectedSpelling() throws {
        let german = try Catalog().strings.values.compactMap { $0["de"] }
        for typo in ["Aufnhemen", "Fortmat", "gespeciherten", "Schliessen", "clicken"] {
            #expect(!german.contains { $0.contains(typo) }, "Found \(typo)")
        }
    }
}
