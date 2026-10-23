import AVFoundation
import BezelNotification
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct KeybindSettingsView: View {
    @Default(.forceUploadModifier) var forceUploadModifier

    static let groups: [(String, [(String, KeyboardShortcuts.Name)])] = [
        ("Capture", [
            ("Capture Region:", .captureRegion),
            ("Capture Window:", .captureWindow),
            ("Capture Screen:", .captureScreen),
            ("Scrolling Capture:", .captureScrolling),
            ("Capture Last Region:", .captureLastRegion),
            ("Capture Text:", .captureText),
            ("Interval Capture:", .intervalCapture),
            ("Capture and Translate:", .captureTranslate),
        ] + (OnDeviceModel.isAvailable ? [("Capture and Ask:", .captureAsk)] : [])),
        ("Record", [
            ("Record Screen:", .recordScreen),
            ("Record Region:", .recordRegion),
            ("Record GIF:", .recordGif),
            ("Record Region as GIF:", .recordRegionGif),
            ("Add Recording Marker:", .addRecordingMarker),
            ("Show or Hide Notes:", .toggleRecordingNotes),
            ("Save Instant Replay:", .saveInstantReplay),
        ]),
        ("Capture and Upload", [
            ("Capture Region:", .captureRegionForceUpload),
            ("Capture Window:", .captureWindowForceUpload),
            ("Capture Screen:", .captureScreenForceUpload),
            ("Record Screen:", .recordScreenForceUpload),
            ("Record GIF:", .recordGifForceUpload),
        ]),
        ("Other", [
            ("Open Main Menu:", .toggleMainMenu),
            ("Open Command Palette:", .openCommandPalette),
            ("Open History Window:", .openHistoryWindow),
            ("Open Editor:", .openEditor),
            ("Open most recent item:", .openMostRecentItem),
            ("Upload from Pasteboard:", .uploadPasteBoardItem),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0.localized()) {
                    ForEach(group.1, id: \.1.rawValue) { entry in
                        KeyboardShortcuts.Recorder(entry.0.localized(), name: entry.1)
                    }
                }
            }
            UploadPresetKeybindSection()
            Section {
                Button(role: .destructive) {
                    KeyboardShortcuts.reset(Self.groups.flatMap { $0.1.map(\.1) })
                    BezelNotification.show(messageText: "Reset keybinds".localized(), icon: ToastIcon)
                } label: {
                    Text("Reset All Keybinds".localized())
                }
            }
        }
        .formStyle(.grouped)
    }
}
