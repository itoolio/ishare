import Foundation

enum NewerSettingsSearch {
    static let snapping = SettingsSearchEntry("Snap the selection to window edges", pane: .capture, keywords: ["Snapping", "Edges", "Buttons"], anchor: "capture.snapping")
    static let pixelExact = SettingsSearchEntry("Select whole device pixels", pane: .capture, keywords: ["Pixel", "Retina", "Crisp"], anchor: "capture.pixelExact")
    static let childWindows = SettingsSearchEntry(
        "Include sheets, popovers and attached windows", pane: .capture, keywords: ["Sheets", "Popovers", "Child windows"], anchor: "capture.childWindows")
    static let redactionReview = SettingsSearchEntry(
        "Review blurred areas before copying or exporting", pane: .capture, keywords: ["Redaction", "Blur", "Review"], anchor: "capture.redactionReview")
    static let exportPresets = SettingsSearchEntry("Editor Export Presets", pane: .capture, keywords: ["Slack", "Docs", "JPEG", "Export"], anchor: "capture.exportPresets")
    static let followPointer = SettingsSearchEntry("Follow the Pointer", pane: .recording, keywords: ["Pan", "Recorded area"], anchor: "recording.followPointer")
    static let pointerHighlight = SettingsSearchEntry("Pointer highlight", pane: .recording, keywords: ["Halo", "Spotlight", "Magnifier"], anchor: "recording.pointerHighlight")
    static let webcamLayout = SettingsSearchEntry("Layout", pane: .recording, keywords: ["Webcam", "Side by side", "Full screen", "Background", "Blur"], anchor: "recording.webcamLayout")
    static let liveCaptions = SettingsSearchEntry("Show live captions while recording", pane: .recording, keywords: ["Captions", "Subtitles", "Speech"], anchor: "recording.liveCaptions")
    static let separateTracks = SettingsSearchEntry(
        "Also save separate tracks for editing", pane: .recording, keywords: ["Final Cut", "DaVinci", "Tracks"], anchor: "recording.separateTracks")
    static let countdown = SettingsSearchEntry("Count down before recording", pane: .recording, keywords: ["Countdown", "Chime"], anchor: "recording.countdown")
    static let notifications = SettingsSearchEntry(
        "Keep notification banners out of recordings", pane: .recording, keywords: ["Notifications", "Banners", "Do Not Disturb"], anchor: "recording.notifications")
    static let progressHUD = SettingsSearchEntry(
        "Show progress below the menu bar icon for long uploads", pane: .uploaders, keywords: ["Progress", "HUD"], anchor: "uploaders.progressHUD")
    static let watchFolders = SettingsSearchEntry("Watch Folders", pane: .uploaders, keywords: ["Watch", "Folder", "Undo Last Steps"], anchor: "uploaders.watchFolders")
    static let localAPI = SettingsSearchEntry("Local API", pane: .advanced, keywords: ["HTTP", "REST", "Token", "curl"], anchor: "advanced.localAPI")
    static let scriptHook = SettingsSearchEntry("Script Hook", pane: .advanced, keywords: ["Script", "Shell", "zsh", "Hook"], anchor: "advanced.scriptHook")
    static let compactMenu = SettingsSearchEntry("Compact menu", pane: .general, keywords: ["Small screens", "Compact"], anchor: "general.compactMenu")
    static let backgroundDot = SettingsSearchEntry(
        "Mark the menu bar icon while replays keep recording", pane: .general, keywords: ["Red dot", "Replay"], anchor: "general.backgroundDot")

    static let all = [
        snapping, pixelExact, childWindows, redactionReview, exportPresets, followPointer, pointerHighlight, webcamLayout, liveCaptions, separateTracks,
        countdown, notifications, progressHUD, watchFolders, localAPI, scriptHook, compactMenu, backgroundDot,
    ]

    static func entries(for pane: SettingsPane) -> [SettingsSearchEntry] {
        all.filter { $0.pane == pane }
    }
}
