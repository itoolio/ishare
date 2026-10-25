import Defaults
import SwiftUI

struct MenuRecordPresetsRow: View {
    let recordsGIF: Bool
    @Default(.recordingPresets) private var presets
    @EnvironmentObject private var app: AppModel
    @Environment(\.menuMetrics) private var metrics

    var body: some View {
        if !presets.isEmpty {
            Menu {
                ForEach(presets) { preset in
                    Button(preset.name) {
                        app.menuActions.run { RecordingPresets.record(preset, gif: recordsGIF) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityHidden(true)
                    Text("Apply Preset".localized())
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.wideHeight)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(ActionTileStyle())
            .menuIndicator(.visible)
            .help("Record with a preset. Its settings apply only to that recording.".localized())
            .accessibilityIdentifier("menu.record.preset")
        }
    }
}

struct MenuExternalDevicesRows: View {
    @ObservedObject private var devices = ExternalScreenDevices.shared
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ForEach(devices.devices) { device in
            HStack(spacing: 8) {
                WideActionButton(symbol: device.symbol, title: device.recordTitle, help: device.name, identifier: "menu.record.device") {
                    app.menuActions.run { CaptureSession.recordDevice(device) }
                }
                WideActionButton(symbol: "camera.viewfinder", title: device.screenshotTitle, help: device.name, identifier: "menu.capture.device") {
                    app.menuActions.run { await CaptureSession.captureDeviceScreenshot(device) }
                }
            }
        }
    }
}
