import Defaults
import KeyboardShortcuts
import SwiftUI

struct RecordingEffectsSettings: View {
    var body: some View {
        Group {
            AutoZoomSettingsSection()
            PointerEffectsSettingsSection()
            LiveDrawingSettingsSection()
            RecordingLimitsSettingsSection()
        }
    }
}

private struct AutoZoomSettingsSection: View {
    @Default(.autoZoomEnabled) private var enabled
    @Default(.autoZoomLevel) private var level
    @Default(.autoZoomEaseDuration) private var easeDuration
    @Default(.autoZoomHoldTime) private var holdTime
    @Default(.autoZoomFollowsPointer) private var followsPointer
    @Default(.autoZoomOnTyping) private var zoomsOnTyping
    @State private var inputMonitoringGranted = InputMonitoringPermission.isGranted

    var body: some View {
        Section {
            Toggle("Auto zoom".localized(), isOn: $enabled)
                .accessibilityIdentifier("settings.recording.autoZoom")
            if enabled {
                SliderRow(title: "Zoom level", value: $level, range: AutoZoomSettings.zoomRange, step: 0.25, format: { String(format: "%.2g×", $0) })
                SliderRow(title: "Zoom speed", value: $easeDuration, range: AutoZoomSettings.easeRange, step: 0.1, format: Self.seconds)
                SliderRow(title: "Stay zoomed for", value: $holdTime, range: AutoZoomSettings.holdRange, step: 0.25, format: Self.seconds)
                Toggle("Follow the pointer while zoomed".localized(), isOn: $followsPointer)
                Toggle("Zoom in on typing".localized(), isOn: $zoomsOnTyping)
                    .onChange(of: zoomsOnTyping) { _, enabled in
                        if enabled, !InputMonitoringPermission.isGranted {
                            InputMonitoringPermission.request()
                        }
                        inputMonitoringGranted = InputMonitoringPermission.isGranted
                    }
                if zoomsOnTyping {
                    PermissionRow(title: "Input Monitoring", granted: inputMonitoringGranted) {
                        InputMonitoringPermission.request()
                        inputMonitoringGranted = InputMonitoringPermission.isGranted
                    }
                }
            }
        } header: {
            Text("Auto Zoom".localized())
        } footer: {
            Text("After you stop recording, ishare zooms in smoothly where you click and zooms back out when you move far away or stop. With “Trim recordings before saving” on, you can preview it and turn it off in the trim window. Typing only counts when Input Monitoring is allowed, and only the time of each key press is used.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { inputMonitoringGranted = InputMonitoringPermission.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputMonitoringGranted = InputMonitoringPermission.isGranted
        }
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.1f s", value)
    }
}

private struct PointerEffectsSettingsSection: View {
    @Default(.pointerSmoothing) private var smoothing
    @Default(.pointerScale) private var scale
    @Default(.clickRipples) private var ripples
    @Default(.clickRippleColor) private var rippleColorHex
    @Default(.hidesIdlePointer) private var hidesIdle
    @Default(.pointerIdleSeconds) private var idleSeconds
    @Default(.recordPointer) private var recordPointer

    var body: some View {
        Section {
            Toggle("Smooth pointer movement".localized(), isOn: $smoothing)
                .disabled(!recordPointer)
            SliderRow(title: "Pointer size", value: $scale, range: PointerEffectSettings.scaleRange, step: 0.25, format: { String(format: "%.2g×", $0) })
                .disabled(!recordPointer)
            Toggle("Hide the pointer when idle".localized(), isOn: $hidesIdle)
                .disabled(!recordPointer)
            if hidesIdle {
                Stepper(value: $idleSeconds, in: PointerEffectSettings.idleRange, step: 1) {
                    LabeledContent("Hide after".localized(), value: String(format: "%.0f s", idleSeconds))
                }
                .disabled(!recordPointer)
            }
            Toggle("Click ripples".localized(), isOn: $ripples)
            if ripples {
                ColorPicker("Ripple color".localized(), selection: rippleColor, supportsOpacity: false)
            }
        } header: {
            Text("Pointer".localized())
        } footer: {
            Text("With any of these on, ishare draws the pointer itself after you stop recording instead of recording the system pointer, so it always appears as an arrow. Click ripples replace “Record clicks”.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rippleColor: Binding<Color> {
        Binding(
            get: { Color(cgColor: (CaptureColor(hex: rippleColorHex) ?? .defaultRipple).cgColor) },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                rippleColorHex = CaptureColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent).hex
            }
        )
    }
}

private struct LiveDrawingSettingsSection: View {
    @Default(.liveDrawingFadeDelay) private var fadeDelay

    var body: some View {
        Section {
            KeyboardShortcuts.Recorder("Draw on Screen:".localized(), name: .toggleRecordingDrawing)
            Picker("Fade marks".localized(), selection: fadeSelection) {
                ForEach(LiveDrawingFade.allCases) { Text($0.title.localized()).tag($0) }
            }
        } header: {
            Text("Draw on Screen".localized())
        } footer: {
            Text("While recording the full screen or a region, press the shortcut to draw with a pen, highlighter or arrow. Your drawing is part of the recording but never of screenshots. Press Esc or the shortcut again to go back to the app you were using.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fadeSelection: Binding<LiveDrawingFade> {
        Binding(
            get: { LiveDrawingFade(rawValue: fadeDelay) ?? .seconds3 },
            set: { fadeDelay = $0.rawValue }
        )
    }
}

private struct RecordingLimitsSettingsSection: View {
    @Default(.recordingMaxMinutes) private var maxMinutes
    @Default(.recordingMaxMegabytes) private var maxMegabytes
    @Default(.recordingLowDiskWarningMB) private var lowDiskMegabytes

    var body: some View {
        Section {
            Stepper(value: $maxMinutes, in: 0 ... 600, step: 1) {
                LabeledContent("Stop after".localized(), value: maxMinutes > 0 ? String(format: "%d min".localized(), maxMinutes) : "No limit".localized())
            }
            Stepper(value: $maxMegabytes, in: 0 ... 100_000, step: 50) {
                LabeledContent("Stop at file size".localized(), value: maxMegabytes > 0 ? "\(maxMegabytes) MB" : "No limit".localized())
            }
            Stepper(value: $lowDiskMegabytes, in: 512 ... 100_000, step: 512) {
                LabeledContent("Warn when free space is below".localized(), value: ByteCountFormatter.string(fromByteCount: Int64(lowDiskMegabytes) * RecordingLimits.megabyte, countStyle: .file))
            }
        } header: {
            Text("Limits".localized())
        } footer: {
            Text("Recordings stop on their own and are kept when a limit is reached or when less than 512 MB of disk space is left. The recording controls show the time left.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title.localized()) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 160)
                    .accessibilityLabel(Text(title.localized()))
                Text(format(value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}
