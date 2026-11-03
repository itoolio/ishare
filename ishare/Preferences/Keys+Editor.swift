import Defaults
import Foundation
import ishareCore

extension Defaults.Keys {
    static let combineLayout = Key<CombineLayout>("combineLayout", default: .horizontal, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineAlignment = Key<CombineAlignment>("combineAlignment", default: .center, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineColumns = Key<Int>("combineColumns", default: 0, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineSpacing = Key<Double>("combineSpacing", default: 24, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combinePadding = Key<Double>("combinePadding", default: 32, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineCornerRadius = Key<Double>("combineCornerRadius", default: 12, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineShadow = Key<Bool>("combineShadow", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineBackground = Key<BeautifyBackground>("combineBackground", default: .transparent, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let editorToolStyles = Key<[String: AnnotationStyle]>("editorToolStyles", default: [:], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let reviewRedactionsBeforeExport = Key<Bool>("reviewRedactionsBeforeExport", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let exportPresets = Key<[ExportPreset]>("exportPresets", default: ExportPreset.builtIn, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let lastExportPresetID = Key<UUID?>("lastExportPresetID", default: nil, suite: .ishare)
    static let editorKindPreferences = Key<[String: EditorKindPreference]>("editorKindPreferences", default: [:], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let editorShowsGrid = Key<Bool>("editorShowsGrid", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let editorSnapsToGrid = Key<Bool>("editorSnapsToGrid", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let editorGridSpacing = Key<Int>("editorGridSpacing", default: 20, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let editorShowsRulers = Key<Bool>("editorShowsRulers", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let combineSolidColor = Key<String>("combineSolidColor", default: "#1F1F2E", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}
