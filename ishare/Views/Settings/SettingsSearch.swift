import Combine
import SwiftUI

@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()

    @Published var pane: SettingsPane?
}

struct SettingsSearchEntry: Sendable {
    let pane: SettingsPane
    let keywords: [String]
}

struct SettingsSearchMatch: Equatable, Sendable {
    let pane: SettingsPane
    let keyword: String?
}

@MainActor
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = [
        SettingsSearchEntry(pane: .general, keywords: [
            "Language", "Launch at login", "Startup", "Land down under", "Menu Bar Icon", "Icon",
            "Clipboard", "Copy image to clipboard instead of URL", "Toast", "Toast Timeout", "Notification",
        ]),
        SettingsSearchEntry(pane: .general, keywords: [
            "Sounds", "Sound", "Capture sound", "Upload complete sound", "Mute", "Beep",
        ]),
        SettingsSearchEntry(pane: .general, keywords: [
            "History", "Keep up to", "Remove uploads older than", "Clear History", "Limit", "Retention",
        ]),
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
        SettingsSearchEntry(pane: .recording, keywords: [
            "Clicks & Keystrokes", "Show keystrokes", "Keystrokes", "Clicks", "Webcam", "Show webcam", "Camera",
            "Input level", "Trim recordings before saving", "Trim", "GIF size", "Meter",
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
            let keywords = entries.filter { $0.pane == pane }.flatMap(\.keywords)
            guard let keyword = keywords.first(where: { contains($0, needle, localize: localize) }) else { return nil }
            return SettingsSearchMatch(pane: pane, keyword: keyword)
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
