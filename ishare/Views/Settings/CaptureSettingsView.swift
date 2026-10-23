import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct CaptureSettingsView: View {
    @Default(.captureFileType) var fileType
    @Default(.screenshotShowsCursor) var showsCursor
    @Default(.windowShadow) var windowShadow
    @Default(.showMagnifier) var showMagnifier
    @Default(.showSelectionGuides) var showSelectionGuides
    @Default(.showLastRegionOutline) var showLastRegionOutline
    @Default(.openEditorAfterCapture) var openEditorAfterCapture
    @Default(.editorSmartShapes) var editorSmartShapes
    @Default(.scrollingAutoScroll) var scrollingAutoScroll
    @Default(.nameFilesAfterWindowTitle) var nameFilesAfterWindowTitle
    @State private var screenAccess = CGPreflightScreenCaptureAccess()
    @State private var eventAccess = CGPreflightPostEventAccess()

    var body: some View {
        Form {
            Section("Files".localized()) {
                Picker("Format:".localized(), selection: $fileType) {
                    ForEach(FileType.allCases) { Text($0.rawValue.uppercased()).tag($0) }
                }
                PrefixRow(key: .captureFileName)
                Toggle("Name files after the window title".localized(), isOn: $nameFilesAfterWindowTitle)
                FolderRow(title: "Image path:", kind: .captures)
            }
            Section("Capture".localized()) {
                Toggle("Show pointer in screenshots".localized(), isOn: $showsCursor)
                Toggle("Include window shadow".localized(), isOn: $windowShadow)
                Toggle("Show magnifier while selecting".localized(), isOn: $showMagnifier)
                Toggle("Show crosshair guides while selecting".localized(), isOn: $showSelectionGuides)
                Toggle("Outline the last region while selecting".localized(), isOn: $showLastRegionOutline)
                Toggle("Open editor after capture".localized(), isOn: $openEditorAfterCapture)
                Toggle("Snap editor shapes to detected elements".localized(), isOn: $editorSmartShapes)
            }
            CaptureExtrasSettings()
            CaptureToolsSettings()
            Section {
                Toggle(
                    "Scroll automatically".localized(),
                    isOn: Binding(
                        get: { scrollingAutoScroll },
                        set: { enabled in
                            scrollingAutoScroll = enabled
                            if enabled, !ScrollingCapture.hasPostEventAccess {
                                PermissionGuide.show(.accessibility)
                            }
                        }
                    ))
                if scrollingAutoScroll {
                    PermissionRow(title: "Scrolling permission", granted: eventAccess) {
                        PermissionGuide.show(.accessibility)
                    }
                }
            } header: {
                Text("Scrolling Capture".localized())
            } footer: {
                Text(
                    "With automatic scrolling, ishare scrolls the area you selected by sending scroll events to it, so long pages are captured without scrolling by hand. macOS lists this permission under Accessibility. ishare asks for it only when you turn this on and uses it for nothing else. Without it, you scroll yourself and ishare captures as you go."
                        .localized()
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section("Permissions".localized()) {
                PermissionRow(title: "Screen recording", granted: screenAccess) {
                    PermissionGuide.show(.screenRecording)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            screenAccess = CGPreflightScreenCaptureAccess()
            eventAccess = CGPreflightPostEventAccess()
        }
    }
}

extension CaptureSettingsView: SettingsSearchable {
    static let searchEntries: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            "Screenshot", pane: .capture,
            keywords: [
                "Format", "PNG", "JPG", "HEIC", "WebP", "TIFF", "File prefix", "Image path", "Folder", "Show pointer in screenshots",
                "Pointer", "Cursor", "Include window shadow", "Shadow", "Show magnifier while selecting", "Magnifier",
                "Show crosshair guides while selecting", "Crosshair", "Guides", "Outline the last region while selecting",
                "Open editor after capture", "Editor", "Snap editor shapes to detected elements", "Smart shapes", "Snapping", "Scrolling Capture", "Scroll automatically",
                "Permissions", "Screen recording",
            ]),
        SettingsSearchEntry(
            "Privacy", pane: .capture,
            keywords: [
                "Hide the menu bar in screenshots", "Menu bar", "Blurred applications", "Blur", "Background", "Add a background to screenshots",
                "Beautify", "Padding", "Corner radius", "Drop shadow", "Gradient", "Measure", "Ruler", "Last region",
                "Frame", "Device frame", "Mockup", "Laptop", "Desktop Display", "Phone", "Browser Window", "Frame appearance",
                "Screen fit", "Letterbox", "Crop to Fill", "Address bar text",
            ]),
        SettingsSearchEntry(
            "Capture delay", pane: .capture,
            keywords: [
                "Self-timer", "Timer", "Countdown", "Copy links from QR codes", "QR code", "Barcode", "Redact sensitive text before uploading",
                "Redaction", "Redact", "Also redact the saved file", "Email addresses", "API keys and tokens", "Credit card numbers",
                "IP addresses", "Phone numbers", "Interval Capture", "Interval", "Burst", "Time-lapse", "Also make a GIF",
                "App Profiles", "Profile", "Name files after the window title", "Window title", "Capture Text", "Text recognition",
                "OCR", "Capture and Translate", "Translate", "Translation", "Translate to", "System Language", "Translate & Describe",
                "Capture and Ask", "Apple Intelligence", "Generate alt text for uploads", "Alt text",
            ]),
    ]
}
