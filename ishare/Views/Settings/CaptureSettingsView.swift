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
    @Default(.openEditorAfterCapture) var openEditorAfterCapture
    @Default(.scrollingAutoScroll) var scrollingAutoScroll
    @State private var screenAccess = CGPreflightScreenCaptureAccess()
    @State private var eventAccess = CGPreflightPostEventAccess()

    var body: some View {
        Form {
            Section("Files".localized()) {
                Picker("Format:".localized(), selection: $fileType) {
                    ForEach(FileType.allCases) { Text($0.rawValue.uppercased()).tag($0) }
                }
                PrefixRow(key: .captureFileName)
                FolderRow(title: "Image path:", kind: .captures)
            }
            Section("Capture".localized()) {
                Toggle("Show pointer in screenshots".localized(), isOn: $showsCursor)
                Toggle("Include window shadow".localized(), isOn: $windowShadow)
                Toggle("Show magnifier while selecting".localized(), isOn: $showMagnifier)
                Toggle("Open editor after capture".localized(), isOn: $openEditorAfterCapture)
            }
            CaptureExtrasSettings()
            Section {
                Toggle("Scroll automatically".localized(), isOn: Binding(
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
                Text("With automatic scrolling, ishare scrolls the area you selected by sending scroll events to it, so long pages are captured without scrolling by hand. macOS lists this permission under Accessibility. ishare asks for it only when you turn this on and uses it for nothing else. Without it, you scroll yourself and ishare captures as you go.".localized())
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
