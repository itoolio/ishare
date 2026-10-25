import Defaults
import Foundation
import ishareCore

extension Defaults.Keys {
    static let capturePath = Key<String>("capturePath", default: "~/Pictures/", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileType = Key<FileType>("captureFileType", default: .PNG, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureFileName = Key<String>("captureFileName", default: "ishare", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let screenshotShowsCursor = Key<Bool>("screenshotShowsCursor", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let windowShadow = Key<Bool>("windowShadow", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let showMagnifier = Key<Bool>("showMagnifier", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let showSelectionGuides = Key<Bool>("showSelectionGuides", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let showLastRegionOutline = Key<Bool>("showLastRegionOutline", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let scrollingAutoScroll = Key<Bool>("scrollingAutoScroll", default: ScrollingCapture.autoScrollsByDefault, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let capturePathBookmark = Key<Data?>("capturePathBookmark", default: nil, suite: .ishare)
    static let ignoredBundleIdentifiers = Key<[String]>("ignoredApps", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let hideMenuBarInCaptures = Key<Bool>("hideMenuBarInCaptures", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let blurredBundleIdentifiers = Key<[String]>("blurredBundleIdentifiers", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyEnabled = Key<Bool>("beautifyEnabled", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyWindowsOnly = Key<Bool>("beautifyWindowsOnly", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyPadding = Key<Double>("beautifyPadding", default: 48, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyCornerRadius = Key<Double>("beautifyCornerRadius", default: 12, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyShadow = Key<Bool>("beautifyShadow", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyBackground = Key<BeautifyBackground>("beautifyBackground", default: .ocean, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifySolidColor = Key<String>("beautifySolidColor", default: "#1E1E2E", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyFrame = Key<DeviceFrame>("beautifyFrame", default: .none, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyFrameAppearance = Key<DeviceFrameAppearance>("beautifyFrameAppearance", default: .light, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyFrameFit = Key<DeviceFrameFit>("beautifyFrameFit", default: .letterbox, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let beautifyFrameTitle = Key<String>("beautifyFrameTitle", default: "", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let editorSmartShapes = Key<Bool>("editorSmartShapes", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let lastCaptureRegions = Key<LastRegions>("lastCaptureRegions", default: LastRegions(), suite: .ishare)
    static let captureDelay = Key<CaptureDelay>("captureDelay", default: .off, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let copyLinksFromCodes = Key<Bool>("copyLinksFromCodes", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let redactBeforeUpload = Key<Bool>("redactBeforeUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let redactSavedFile = Key<Bool>("redactSavedFile", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let redactionCategories = Key<Set<RedactionCategory>>(
        "redactionCategories", default: Set(RedactionCategory.allCases), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let intervalCaptureInterval = Key<CaptureInterval>("intervalCaptureInterval", default: .two, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let intervalCaptureStopMode = Key<IntervalStopMode>("intervalCaptureStopMode", default: .frameCount, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let intervalCaptureFrameCount = Key<Int>("intervalCaptureFrameCount", default: 10, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let intervalCaptureDuration = Key<Int>("intervalCaptureDuration", default: 60, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let intervalCaptureMakesGIF = Key<Bool>("intervalCaptureMakesGIF", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let captureProfiles = Key<[CaptureProfile]>("captureProfiles", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let translationTargetLanguage = Key<String>("translationTargetLanguage", default: "", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let generateAltText = Key<Bool>("generateAltText", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let selectionConstraint = Key<SelectionConstraint>("selectionConstraint", default: .free, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let customSelectionSize = Key<FixedSelectionSize?>("customSelectionSize", default: nil, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let freezeScreenWhileSelecting = Key<Bool>("freezeScreenWhileSelecting", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let multiRegionResult = Key<MultiRegionResult>("multiRegionResult", default: .combined, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let menuCaptureIncludesParentWindow = Key<Bool>(
        "menuCaptureIncludesParentWindow", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let nameFilesAfterWindowTitle = Key<Bool>("nameFilesAfterWindowTitle", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
}

extension SelectionConstraint: @retroactive Defaults.Serializable {}
extension FixedSelectionSize: @retroactive Defaults.Serializable {}
extension MultiRegionResult: @retroactive Defaults.Serializable {}
