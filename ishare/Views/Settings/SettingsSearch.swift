import Combine
import SwiftUI

@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    struct AnchorRequest: Equatable {
        let anchor: String
        let token = UUID()
    }

    @Published var pane: SettingsPane?
    @Published var anchorRequest: AnchorRequest?
    @Published private(set) var highlightedAnchor: String?
    private var highlightTask: Task<Void, Never>?

    func reveal(_ anchor: String, in pane: SettingsPane? = nil) {
        if let pane {
            self.pane = pane
        }
        anchorRequest = AnchorRequest(anchor: anchor)
    }

    func highlight(_ anchor: String, duration: Duration = .seconds(1.6)) {
        highlightTask?.cancel()
        highlightedAnchor = anchor
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            highlightedAnchor = nil
        }
    }
}

enum SettingsAnchor {
    static let language = "general.language"
    static let launchAtLogin = "general.launchAtLogin"
    static let aussieMode = "general.aussieMode"
    static let menuBarIcon = "general.menuBarIcon"
    static let menuLayout = "general.menuLayout"
    static let menuDensity = "general.menuDensity"
    static let appearance = "general.appearance"
    static let highContrast = "general.highContrast"
    static let clipboard = "general.clipboard"
    static let toastTimeout = "general.toastTimeout"
    static let toastPlacement = "general.toastPlacement"
    static let resultPresentation = "general.resultPresentation"
    static let sounds = "general.sounds"
    static let history = "general.history"
    static let clearHistory = "general.clearHistory"
}

struct SettingsSearchEntry: Sendable {
    let pane: SettingsPane
    let keywords: [String]
    let anchor: String?

    init(pane: SettingsPane, keywords: [String], anchor: String? = nil) {
        self.pane = pane
        self.keywords = keywords
        self.anchor = anchor
    }
}

struct SettingsSearchMatch: Equatable, Sendable {
    let pane: SettingsPane
    let keyword: String?
    let anchor: String?

    init(pane: SettingsPane, keyword: String?, anchor: String? = nil) {
        self.pane = pane
        self.keyword = keyword
        self.anchor = anchor
    }
}

@MainActor
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = [
        SettingsSearchEntry(pane: .general, keywords: ["Language"], anchor: SettingsAnchor.language),
        SettingsSearchEntry(pane: .general, keywords: ["Launch at login", "Startup"], anchor: SettingsAnchor.launchAtLogin),
        SettingsSearchEntry(pane: .general, keywords: ["Land down under"], anchor: SettingsAnchor.aussieMode),
        SettingsSearchEntry(pane: .general, keywords: ["Menu Bar Icon", "Icon"], anchor: SettingsAnchor.menuBarIcon),
        SettingsSearchEntry(pane: .general, keywords: ["Clipboard", "Copy image to clipboard instead of URL"], anchor: SettingsAnchor.clipboard),
        SettingsSearchEntry(pane: .general, keywords: ["Toast", "Toast Timeout"], anchor: SettingsAnchor.toastTimeout),
        SettingsSearchEntry(pane: .general, keywords: ["Density", "Compact", "Comfortable"], anchor: SettingsAnchor.menuDensity),
        SettingsSearchEntry(pane: .general, keywords: ["Menu", "Sections", "Restore Default Layout", "Favorites", "Reorder"], anchor: SettingsAnchor.menuLayout),
        SettingsSearchEntry(pane: .general, keywords: ["Appearance", "Menu theme", "Dark", "Light", "Menu preview"], anchor: SettingsAnchor.appearance),
        SettingsSearchEntry(pane: .general, keywords: ["High contrast menu", "Contrast"], anchor: SettingsAnchor.highContrast),
        SettingsSearchEntry(pane: .general, keywords: ["Position", "Corner", "Screen"], anchor: SettingsAnchor.toastPlacement),
        SettingsSearchEntry(pane: .general, keywords: ["Show results as", "Notification", "Notification Center"], anchor: SettingsAnchor.resultPresentation),
        SettingsSearchEntry(pane: .general, keywords: [
            "Sounds", "Sound", "Capture sound", "Upload complete sound", "Mute", "Beep",
        ], anchor: SettingsAnchor.sounds),
        SettingsSearchEntry(pane: .general, keywords: [
            "History", "Keep up to", "Remove uploads older than", "Limit", "Retention",
        ], anchor: SettingsAnchor.history),
        SettingsSearchEntry(pane: .general, keywords: ["Clear History"], anchor: SettingsAnchor.clearHistory),
        SettingsSearchEntry(pane: .capture, keywords: [
            "Screenshot", "Format", "PNG", "JPG", "HEIC", "WebP", "TIFF", "File prefix", "Image path", "Folder",
            "Show pointer in screenshots", "Pointer", "Cursor", "Include window shadow", "Shadow",
            "Show magnifier while selecting", "Magnifier", "Open editor after capture", "Editor",
            "Scrolling Capture", "Scroll automatically", "Permissions", "Screen recording",
        ]),
        SettingsSearchEntry(pane: .recording, keywords: [
            "Video", "Resolution", "Frame rate", "FPS", "MP4", "MOV", "HEVC", "HDR",
            "Record audio", "Audio", "Record microphone", "Microphone", "Record pointer", "Record clicks",
            "Excluded applications", "GIF", "GIF frame rate", "Compress large recordings before upload", "Compression",
            "Video path",
        ]),
        SettingsSearchEntry(pane: .uploaders, keywords: [
            "Upload", "Uploader", "Destination", "Imgur", "Custom uploader", "Server", "S3", "R2", "ISCU", "Import", "Export",
            "Assistant", "Apple Intelligence", "Delete", "Deletion URL", "Headers",
        ]),
        SettingsSearchEntry(pane: .capture, keywords: [
            "Privacy", "Hide the menu bar in screenshots", "Menu bar", "Blurred applications", "Blur",
            "Background", "Add a background to screenshots", "Beautify", "Padding", "Corner radius", "Drop shadow",
            "Gradient", "Measure", "Ruler", "Last region",
        ]),
        SettingsSearchEntry(pane: .capture, keywords: [
            "Capture delay", "Self-timer", "Timer", "Countdown", "Copy links from QR codes", "QR code", "Barcode",
            "Redact sensitive text before uploading", "Redaction", "Redact", "Also redact the saved file", "Email addresses",
            "API keys and tokens", "Credit card numbers", "IP addresses", "Phone numbers", "Interval Capture", "Interval",
            "Burst", "Time-lapse", "Also make a GIF", "App Profiles", "Profile", "Name files after the window title", "Window title",
            "Capture Text", "Text recognition", "OCR",
            "Capture and Translate", "Translate", "Translation", "Translate to", "System Language", "Translate & Describe",
            "Capture and Ask", "Apple Intelligence", "Generate alt text for uploads", "Alt text",
        ]),
        SettingsSearchEntry(pane: .recording, keywords: [
            "Clicks & Keystrokes", "Show keystrokes", "Keystrokes", "Clicks", "Webcam", "Show webcam", "Camera",
            "Input level", "Trim recordings before saving", "Trim", "GIF size", "Meter",
        ]),
        SettingsSearchEntry(pane: .recording, keywords: ["Captions", "Generate captions", "Subtitles", "SRT", "Transcription", "Speech", "Burn into the video", "Markers", "Chapters", "Export"]),
        SettingsSearchEntry(pane: .recording, keywords: [
            "Audio source", "All system audio", "Only selected apps", "App audio", "Notes", "Teleprompter", "Script",
            "Instant replay", "Replay", "Buffer", "Keep the last",
        ]),
        SettingsSearchEntry(pane: .uploaders, keywords: [
            "Also upload to", "Copy URL after upload", "Open URL in browser after upload", "Watch Folder", "Folder",
            "Upload Queue", "Retry", "Expiring links", "Presigned", "ShareX", "SXCU", "Test Upload", "Method",
        ]),
        SettingsSearchEntry(pane: .advanced, keywords: [
            "Backup", "Export Settings", "Import Settings", "Include upload history", "Include S3 secret access keys",
        ]),
        SettingsSearchEntry(pane: .keybinds, keywords: [
            "Keybinds", "Keyboard", "Shortcut", "Hotkey", "Reset All Keybinds", "Force upload", "Modifier",
        ]),
        SettingsSearchEntry(pane: .keybinds, keywords: KeybindSettingsView.groups.flatMap { [$0.0] + $0.1.map(\.0) }),
        SettingsSearchEntry(pane: .advanced, keywords: [
            "Advanced", "Imgur Client ID", "Client ID",
        ]),
        SettingsSearchEntry(pane: .uploaders, keywords: ["Upload Presets", "Preset", "URL Shortener", "Shorten", "Short link", "is.gd", "v.gd"]),
    ]

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":…")))
    }

    static func matches(
        for query: String,
        entries: [SettingsSearchEntry] = entries,
        localize: (String) -> String = { $0.localized() }
    ) -> [SettingsSearchMatch] {
        let needle = normalized(query)
        guard !needle.isEmpty else {
            return SettingsPane.allCases.map { SettingsSearchMatch(pane: $0, keyword: nil) }
        }
        return SettingsPane.allCases.compactMap { pane in
            if contains(pane.title, needle, localize: localize) {
                return SettingsSearchMatch(pane: pane, keyword: nil)
            }
            for entry in entries where entry.pane == pane {
                if let keyword = entry.keywords.first(where: { contains($0, needle, localize: localize) }) {
                    return SettingsSearchMatch(pane: pane, keyword: keyword, anchor: entry.anchor)
                }
            }
            return nil
        }
    }


    private static func contains(_ candidate: String, _ needle: String, localize: (String) -> String) -> Bool {
        normalized(candidate).contains(needle) || normalized(localize(candidate)).contains(needle)
    }
}

struct SettingsSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Settings".localized(), text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("settings.search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear".localized())
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}
