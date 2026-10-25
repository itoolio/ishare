import Defaults
import Foundation
import ishareCore
import KeyboardShortcuts

indirect enum ArchiveValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([ArchiveValue])
    case dictionary([String: ArchiveValue])

    init?(propertyList value: Any) {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            self = .bool(number.boolValue)
        case let number as NSNumber where CFNumberIsFloatType(number):
            self = .double(number.doubleValue)
        case let number as NSNumber:
            self = .int(number.intValue)
        case let string as String:
            self = .string(string)
        case let data as Data:
            self = .data(data)
        case let date as Date:
            self = .date(date)
        case let array as [Any]:
            let values = array.compactMap(ArchiveValue.init(propertyList:))
            guard values.count == array.count else { return nil }
            self = .array(values)
        case let dictionary as [String: Any]:
            let values = dictionary.compactMapValues(ArchiveValue.init(propertyList:))
            guard values.count == dictionary.count else { return nil }
            self = .dictionary(values)
        default:
            return nil
        }
    }

    var propertyList: Any {
        switch self {
        case let .bool(value): value
        case let .int(value): value
        case let .double(value): value
        case let .string(value): value
        case let .data(value): value
        case let .date(value): value
        case let .array(values): values.map(\.propertyList)
        case let .dictionary(values): values.mapValues(\.propertyList)
        }
    }
}

struct ShortcutEntry: Codable, Equatable, Sendable {
    var shortcut: KeyboardShortcuts.Shortcut?
}

struct SettingsArchive: Codable, Equatable {
    static let fileExtension = "ishare-settings"
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var appVersion: String?
    var preferences: [String: ArchiveValue]
    var uploaders: [CustomUploader]
    var shortcuts: [String: ShortcutEntry]
    var history: [HistoryItem]?
    var includesSecrets: Bool

    struct Summary: Equatable {
        let preferences: Int
        let uploaders: Int
        let shortcuts: Int
        let history: Int?
        let includesSecrets: Bool
    }

    var summary: Summary {
        Summary(
            preferences: preferences.count, uploaders: uploaders.count, shortcuts: shortcuts.count,
            history: history?.count, includesSecrets: includesSecrets
        )
    }

    static func == (lhs: SettingsArchive, rhs: SettingsArchive) -> Bool {
        lhs.version == rhs.version && lhs.preferences == rhs.preferences && lhs.shortcuts == rhs.shortcuts
            && lhs.uploaders.map(\.id) == rhs.uploaders.map(\.id) && lhs.history == rhs.history && lhs.includesSecrets == rhs.includesSecrets
    }
}

enum SettingsArchiveError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupportedVersion(Int)
    case invalidUploader(String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(detail): "The settings file couldn't be read (\(detail))"
        case let .unsupportedVersion(version): "The settings file was made by a newer version of ishare (format \(version))"
        case let .invalidUploader(name): "The uploader “\(name)” in the settings file is invalid"
        }
    }
}

@MainActor
struct ShortcutStore {
    var names: @MainActor () -> [String]
    var get: @MainActor (String) -> KeyboardShortcuts.Shortcut?
    var set: @MainActor (KeyboardShortcuts.Shortcut?, String) -> Void

    static let prefix = "KeyboardShortcuts_"

    static let live = ShortcutStore(
        names: {
            UserDefaults.standard.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .sorted()
        },
        get: { KeyboardShortcuts.getShortcut(for: .init($0)) },
        set: { shortcut, name in KeyboardShortcuts.setShortcut(shortcut, for: .init(name)) }
    )
}

@MainActor
enum SettingsTransfer {
    static let preferenceKeys: [Defaults.Keys] = [
        .copyToClipboard, .openInFinder, .saveToDisk, .uploadMedia, .builtInShare, .openEditorAfterCapture, .forceUploadModifier,
        .capturePath, .captureFileType, .captureFileName, .screenshotShowsCursor, .windowShadow, .showMagnifier, .showSelectionGuides, .showLastRegionOutline,
        .scrollingAutoScroll, .ignoredBundleIdentifiers,
        .toastTimeout, .menuBarIcon, .aussieMode, .copyImageToClipboard, .menuRecordsGIF,
        .recordingPath, .recordingFileName, .recordMP4, .useHEVC, .useHDR, .recordAudio, .recordMic, .recordPointer, .recordClicks,
        .recordingResolution, .recordingFrameRate, .gifFrameRate, .compressBeforeUpload, .compressionThresholdMB, .compressionPreset,
        .imgurClientId, .activeCustomUploader, .uploadType, .uploadDestination,
        .copyURLAfterUpload, .openURLAfterUpload, .additionalUploadDestinations, .destinationChooserModifier, .watchFolderFilter,
        .hideMenuBarInCaptures, .blurredBundleIdentifiers, .beautifyEnabled, .beautifyWindowsOnly, .beautifyPadding, .beautifyCornerRadius,
        .beautifyShadow, .beautifyBackground, .beautifySolidColor, .showKeystrokes, .keystrokesShortcutsOnly, .showWebcam,
        .webcamSize, .webcamCorner, .trimBeforeSaving, .gifMaxSize, .historyLimit, .historyRetention,
        .captureSound, .uploadCompleteSound, .captureDelay, .copyLinksFromCodes, .redactBeforeUpload, .redactSavedFile,
        .redactionCategories, .intervalCaptureInterval, .intervalCaptureStopMode, .intervalCaptureFrameCount, .intervalCaptureDuration, .intervalCaptureMakesGIF,
        .captureProfiles, .nameFilesAfterWindowTitle, .generateCaptions, .captionOutput, .urlShortener, .uploadPresets,
        .editorShowsLayers, .menuSectionOrder, .hiddenMenuSections, .menuDensity, .menuTheme, .highContrastMenu,
        .toastCorner, .toastScreen, .resultPresentation,
        .recordingAudioSource, .recordingAudioBundleIDs, .instantReplayDuration, .instantReplayResolution, .instantReplayFrameRate, .recordingNotesFontSize,
        .recordingNotesScrollSpeed, .recordingNotesOpacity, .translationTargetLanguage, .generateAltText, .linkOptionPreferences, .menuFavorites,
        .showsWhatsNew, .autoZoomEnabled, .autoZoomLevel, .autoZoomEaseDuration, .autoZoomHoldTime, .autoZoomFollowsPointer, .autoZoomOnTyping,
        .pointerSmoothing, .pointerScale, .clickRipples, .clickRippleColor, .hidesIdlePointer, .pointerIdleSeconds,
        .liveDrawingTool, .liveDrawingColor, .liveDrawingFadeDelay, .recordingMaxMinutes, .recordingMaxMegabytes, .recordingLowDiskWarningMB,
        .beautifyFrame, .beautifyFrameAppearance, .beautifyFrameFit, .beautifyFrameTitle, .editorSmartShapes,
        .showQRCodeAfterUpload, .localShareExpiry, .localShareMaxDownloads, .historySyncEnabled,
        .optimizeImagesBeforeUpload, .imageOptimizationFormat, .imageConversionQuality, .stripImageMetadata,
        .stripImportedImageMetadata, .uploadWebhooks, .recordingPresets,
    ]

    static var preferenceNames: Set<String> {
        Set(preferenceKeys.map(\.name))
    }

    static func uploadersKey(in defaults: UserDefaults) -> Defaults.Key<Set<CustomUploader>?> {
        defaults === UserDefaults.ishare ? .savedCustomUploaders : Defaults.Key("savedCustomUploaders", suite: defaults)
    }

    static func historyKey(in defaults: UserDefaults) -> Defaults.Key<[HistoryItem]> {
        defaults === UserDefaults.ishare ? .uploadHistory : Defaults.Key("uploadHistory", default: [], suite: defaults)
    }

    static func makeArchive(
        includeHistory: Bool, includeSecrets: Bool, defaults: UserDefaults = .ishare, shortcuts: ShortcutStore = .live,
        date: Date = .init()
    ) -> SettingsArchive {
        let preferences = preferenceNames.reduce(into: [String: ArchiveValue]()) { result, name in
            if let raw = defaults.object(forKey: name), let value = ArchiveValue(propertyList: raw) {
                result[name] = value
            }
        }
        let uploaders = (Defaults[uploadersKey(in: defaults)] ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { UploaderSecrets.exporting(S3SecretStore.exporting($0, includeSecret: includeSecrets), includeSecrets: includeSecrets) }
        let shortcutEntries = shortcuts.names().reduce(into: [String: ShortcutEntry]()) { result, name in
            result[name] = ShortcutEntry(shortcut: shortcuts.get(name))
        }
        return SettingsArchive(
            version: SettingsArchive.currentVersion, exportedAt: date,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            preferences: preferences, uploaders: uploaders, shortcuts: shortcutEntries,
            history: includeHistory ? Defaults[historyKey(in: defaults)] : nil, includesSecrets: includeSecrets
        )
    }

    static func encode(_ archive: SettingsArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> SettingsArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        let archive: SettingsArchive
        do {
            archive = try decoder.decode(SettingsArchive.self, from: data)
        } catch {
            throw SettingsArchiveError.unreadable(error.localizedDescription)
        }
        guard archive.version <= SettingsArchive.currentVersion else {
            throw SettingsArchiveError.unsupportedVersion(archive.version)
        }
        if let invalid = archive.uploaders.first(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw SettingsArchiveError.invalidUploader(invalid.id.uuidString)
        }
        return archive
    }

    static func apply(_ archive: SettingsArchive, to defaults: UserDefaults = .ishare, shortcuts: ShortcutStore = .live) {
        let allowed = preferenceNames
        for (name, value) in archive.preferences where allowed.contains(name) {
            defaults.set(value.propertyList, forKey: name)
        }
        UploaderStore.merge(archive.uploaders, key: uploadersKey(in: defaults))
        for (name, entry) in archive.shortcuts {
            shortcuts.set(entry.shortcut, name)
        }
        if let history = archive.history {
            let key = historyKey(in: defaults)
            let existing = Set(Defaults[key])
            Defaults[key] = Array((history.filter { !existing.contains($0) } + Defaults[key]).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(50))
        }
    }
}
