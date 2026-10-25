import Defaults
import Foundation
import ishareCore

extension Defaults.Keys {
    static let imgurClientId = Key<String>("imgurClientId", default: "867afe9433c0a53", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let activeCustomUploader = Key<UUID?>("activeCustomUploader", default: nil, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let savedCustomUploaders = Key<Set<CustomUploader>?>("savedCustomUploaders", suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let savedLocalUploaders = Key<Set<CustomUploader>>("savedLocalUploaders", default: [], suite: .ishare)
    static let uploadType = Key<UploadType>("uploadType", default: .IMGUR, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadDestination = Key<UploadDestination>("uploadDestination", default: .builtIn(.IMGUR), suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let copyURLAfterUpload = Key<Bool>("copyURLAfterUpload", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let openURLAfterUpload = Key<Bool>("openURLAfterUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let additionalUploadDestinations = Key<[UploadDestination]>("additionalUploadDestinations", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let destinationChooserModifier = Key<ForceUploadModifier?>("destinationChooserModifier", suite: .ishare)
    static let watchFolderEnabled = Key<Bool>("watchFolderEnabled", default: false, suite: .ishare)
    static let watchFolderPath = Key<String>("watchFolderPath", default: "", suite: .ishare)
    static let watchFolderBookmark = Key<Data?>("watchFolderBookmark", default: nil, suite: .ishare)
    static let watchFolderFilter = Key<WatchFolderFilter>("watchFolderFilter", default: .images, suite: .ishare)
    static let watchFolderProcessed = Key<[String]>("watchFolderProcessed", default: [], suite: .ishare)
    static let urlShortener = Key<URLShortenerConfiguration>("urlShortener", default: .none, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadPresets = Key<[UploadPreset]>("uploadPresets", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let linkOptionPreferences = Key<[String: LinkOptionPreferences]>("linkOptionPreferences", default: [:], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let localFolderBookmarks = Key<[String: Data]>("localFolderBookmarks", default: [:], suite: .ishare)
    static let optimizeImagesBeforeUpload = Key<Bool>("optimizeImagesBeforeUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let imageOptimizationFormat = Key<ImageOptimizationFormat>("imageOptimizationFormat", default: .lossless, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let imageConversionQuality = Key<Double>("imageConversionQuality", default: 0.85, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let stripImageMetadata = Key<Bool>("stripImageMetadata", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let stripImportedImageMetadata = Key<Bool>("stripImportedImageMetadata", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadWebhooks = Key<[UploadWebhook]>("uploadWebhooks", default: [], suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploadersLastSyncedAt = Key<Date?>("uploadersLastSyncedAt", default: nil, suite: .ishare)
    static let showQRCodeAfterUpload = Key<Bool>("showQRCodeAfterUpload", default: false, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let localShareExpiry = Key<LocalShareExpiry>("localShareExpiry", default: .oneHour, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let localShareMaxDownloads = Key<Int?>("localShareMaxDownloads", default: nil, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let keepsExpiredUploadsInHistory = Key<Bool>("keepsExpiredUploadsInHistory", default: true, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let duplicateUploadPolicy = Key<DuplicatePolicy>("duplicateUploadPolicy", default: .ask, suite: .ishare, iCloud: SettingsStorage.syncsToCloud)
    static let uploaderHealthCheckFrequency = Key<HealthCheckFrequency>(
        "uploaderHealthCheckFrequency", default: .off, suite: .ishare, iCloud: SettingsStorage.syncsToCloud
    )
    static let uploadHashIndex = Key<DuplicateIndex>("uploadHashIndex", default: DuplicateIndex(), suite: .ishare)
    static let uploaderHealthRecords = Key<[String: HealthCheckRecord]>("uploaderHealthRecords", default: [:], suite: .ishare)
    static let uploaderHealthLastCheck = Key<Date?>("uploaderHealthLastCheck", default: nil, suite: .ishare)
    static let lastUploadLinks = Key<[String: String]>("lastUploadLinks", default: [:], suite: .ishare)
    static let uploadExpiryLastRun = Key<Date?>("uploadExpiryLastRun", default: nil, suite: .ishare)
}

extension LocalShareExpiry: Defaults.Serializable {}
extension DuplicatePolicy: Defaults.Serializable {}
extension HealthCheckFrequency: Defaults.Serializable {}
extension DuplicateIndex: Defaults.Serializable {}
extension HealthCheckRecord: Defaults.Serializable {}
