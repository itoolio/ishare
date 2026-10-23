import AppKit
import Defaults

enum AfterCaptureStep: String, CaseIterable, Identifiable, Sendable {
    case openEditor
    case saveToDisk
    case copyToClipboard
    case openInFinder
    case airdrop
    case photos
    case messages
    case mail
    case upload

    enum Group: Sendable {
        case local
        case share
        case upload
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .openEditor: "Open Editor"
        case .saveToDisk: "Save to Disk"
        case .copyToClipboard: "Copy to Clipboard"
        case .openInFinder: "Open in Finder"
        case .airdrop: "AirDrop"
        case .photos: "Photos"
        case .messages: "Messages"
        case .mail: "Mail"
        case .upload: "Upload Media"
        }
    }

    var symbol: String {
        switch self {
        case .openEditor: "pencil.tip.crop.circle"
        case .saveToDisk: "internaldrive"
        case .copyToClipboard: "doc.on.clipboard"
        case .openInFinder: "folder"
        case .airdrop: "dot.radiowaves.left.and.right"
        case .photos: "photo.on.rectangle"
        case .messages: "message"
        case .mail: "envelope"
        case .upload: "icloud.and.arrow.up"
        }
    }

    var group: Group {
        switch self {
        case .openEditor, .saveToDisk, .copyToClipboard, .openInFinder: .local
        case .airdrop, .photos, .messages, .mail: .share
        case .upload: .upload
        }
    }

    var appBundleIdentifier: String? {
        switch self {
        case .photos: "com.apple.Photos"
        case .messages: "com.apple.MobileSMS"
        case .mail: "com.apple.Mail"
        default: nil
        }
    }

    var sharingService: NSSharingService.Name? {
        switch self {
        case .airdrop: .sendViaAirDrop
        case .photos: .addToIPhoto
        case .messages: .composeMessage
        case .mail: .composeEmail
        default: nil
        }
    }

    var dependsOn: AfterCaptureStep? {
        self == .openInFinder ? .saveToDisk : nil
    }

    @MainActor var isEnabled: Bool {
        get {
            switch self {
            case .openEditor: Defaults[.openEditorAfterCapture]
            case .saveToDisk: Defaults[.saveToDisk]
            case .copyToClipboard: Defaults[.copyToClipboard]
            case .openInFinder: Defaults[.openInFinder] && Defaults[.saveToDisk]
            case .airdrop: Defaults[.builtInShare].airdrop
            case .photos: Defaults[.builtInShare].photos
            case .messages: Defaults[.builtInShare].messages
            case .mail: Defaults[.builtInShare].mail
            case .upload: Defaults[.uploadMedia]
            }
        }
        nonmutating set {
            switch self {
            case .openEditor: Defaults[.openEditorAfterCapture] = newValue
            case .saveToDisk:
                Defaults[.saveToDisk] = newValue
                if !newValue { Defaults[.openInFinder] = false }
            case .copyToClipboard: Defaults[.copyToClipboard] = newValue
            case .openInFinder: Defaults[.openInFinder] = newValue
            case .airdrop: Defaults[.builtInShare].airdrop = newValue
            case .photos: Defaults[.builtInShare].photos = newValue
            case .messages: Defaults[.builtInShare].messages = newValue
            case .mail: Defaults[.builtInShare].mail = newValue
            case .upload: Defaults[.uploadMedia] = newValue
            }
        }
    }

    @MainActor static var enabledSteps: [AfterCaptureStep] {
        allCases.filter(\.isEnabled)
    }

    @MainActor static var summary: String {
        let titles = enabledSteps.map { $0.title.localized() }
        return titles.isEmpty ? "Nothing happens after a capture".localized() : titles.formatted(.list(type: .and))
    }
}
