@preconcurrency import AVFoundation
import Defaults
import Speech
import SwiftUI

struct RecordingExtrasSettings: View {
    var body: some View {
        Group {
            InputOverlaySettingsSection()
            WebcamSettingsSection()
            MicrophoneSettingsSection()
            AfterRecordingSettingsSection()
            CaptionsSettingsSection()
        }
    }
}

private struct InputOverlaySettingsSection: View {
    @Default(.recordClicks) private var recordClicks
    @Default(.showKeystrokes) private var showKeystrokes
    @Default(.keystrokesShortcutsOnly) private var shortcutsOnly
    @State private var inputMonitoringGranted = InputMonitoringPermission.isGranted

    var body: some View {
        Section {
            Toggle("Show keystrokes".localized(), isOn: $showKeystrokes)
                .onChange(of: showKeystrokes) { _, enabled in
                    if enabled, !InputMonitoringPermission.isGranted {
                        InputMonitoringPermission.request()
                    }
                    inputMonitoringGranted = InputMonitoringPermission.isGranted
                }
            if showKeystrokes {
                Toggle("Only show shortcuts".localized(), isOn: $shortcutsOnly)
                PermissionRow(title: "Input Monitoring", granted: inputMonitoringGranted) {
                    InputMonitoringPermission.request()
                    inputMonitoringGranted = InputMonitoringPermission.isGranted
                }
            }
        } header: {
            Text("Clicks & Keystrokes".localized())
        } footer: {
            Text("Clicks and keystrokes are drawn on screen in full-screen and region recordings. In window and app recordings they are added to the video, together with the webcam, after you stop recording. Keystrokes need Input Monitoring permission; with “Only show shortcuts” on, plain typing such as passwords is never shown.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { inputMonitoringGranted = InputMonitoringPermission.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputMonitoringGranted = InputMonitoringPermission.isGranted
        }
    }
}

private struct WebcamSettingsSection: View {
    @Default(.showWebcam) private var showWebcam
    @Default(.webcamSize) private var webcamSize
    @Default(.webcamCorner) private var webcamCorner
    @Default(.webcamDeviceID) private var webcamDeviceID
    @State private var cameras: [AVCaptureDevice] = []
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Section {
            Toggle("Show webcam".localized(), isOn: $showWebcam)
                .onChange(of: showWebcam) { _, enabled in
                    guard enabled else { return }
                    Task { @MainActor in
                        let granted = await CaptureDevices.requestAccess(for: .video)
                        authorization = AVCaptureDevice.authorizationStatus(for: .video)
                        if !granted { showWebcam = false }
                        cameras = CaptureDevices.cameras()
                    }
                }
            if showWebcam {
                Picker("Camera".localized(), selection: $webcamDeviceID) {
                    Text("System default".localized()).tag(String?.none)
                    ForEach(cameras, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                Picker("Size".localized(), selection: $webcamSize) {
                    ForEach(WebcamBubbleSize.allCases) { Text($0.title.localized()).tag($0) }
                }
                Picker("Position".localized(), selection: $webcamCorner) {
                    ForEach(WebcamCorner.allCases) { Text($0.title.localized()).tag($0) }
                }
            }
            if authorization == .denied || authorization == .restricted {
                PermissionRow(title: "Camera", granted: false) {
                    SystemSettingsLink.open("Privacy_Camera")
                }
            }
        } header: {
            Text("Webcam".localized())
        } footer: {
            Text("A round camera bubble floats over the recording. Drag it to move it while you record.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            cameras = CaptureDevices.cameras()
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }
}

private struct MicrophoneSettingsSection: View {
    @Default(.recordMic) private var recordMic
    @Default(.microphoneDeviceID) private var microphoneDeviceID
    @StateObject private var monitor = MicrophoneLevelMonitor()
    @State private var microphones: [AVCaptureDevice] = []

    var body: some View {
        Section("Microphone".localized()) {
            Picker("Microphone".localized(), selection: $microphoneDeviceID) {
                Text("System default".localized()).tag(String?.none)
                ForEach(microphones, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
            }
            .disabled(!recordMic)
            .onChange(of: microphoneDeviceID) { _, deviceID in
                guard monitor.isRunning else { return }
                Task { await monitor.start(deviceID: deviceID) }
            }
            LabeledContent("Input level".localized()) {
                HStack(spacing: 10) {
                    AudioLevelMeter(level: monitor.levels.level, peak: monitor.levels.peakLevel, width: 140, height: 6)
                    Button(monitor.isRunning ? "Stop".localized() : "Test".localized()) {
                        if monitor.isRunning {
                            monitor.stop()
                        } else {
                            Task { await monitor.start(deviceID: microphoneDeviceID) }
                        }
                    }
                }
            }
            if monitor.isDenied {
                PermissionRow(title: "Microphone", granted: false) {
                    SystemSettingsLink.open("Privacy_Microphone")
                }
            }
        }
        .onAppear { microphones = CaptureDevices.microphones() }
        .onDisappear { monitor.stop() }
    }
}

private struct AfterRecordingSettingsSection: View {
    @Default(.trimBeforeSaving) private var trimBeforeSaving
    @Default(.gifMaxSize) private var gifMaxSize

    var body: some View {
        Section("After Recording".localized()) {
            Toggle("Trim recordings before saving".localized(), isOn: $trimBeforeSaving)
            Picker("GIF size".localized(), selection: $gifMaxSize) {
                ForEach(GIFMaxSize.allCases) { Text($0.title.localized()).tag($0) }
            }
        }
    }
}

private struct CaptionsSettingsSection: View {
    @Default(.generateCaptions) private var generateCaptions
    @Default(.captionOutput) private var captionOutput
    @State private var authorized = SpeechCaptioner.isAuthorized

    var body: some View {
        Section {
            Toggle("Generate captions".localized(), isOn: $generateCaptions)
                .onChange(of: generateCaptions) { _, enabled in
                    guard enabled else { return }
                    Task { @MainActor in
                        authorized = await SpeechCaptioner.requestAuthorization()
                        if !authorized { generateCaptions = false }
                    }
                }
            if generateCaptions {
                Picker("Captions".localized(), selection: $captionOutput) {
                    ForEach(CaptionOutput.allCases) { Text($0.title.localized()).tag($0) }
                }
            }
            if !authorized, SFSpeechRecognizer.authorizationStatus() == .denied || SFSpeechRecognizer.authorizationStatus() == .restricted {
                PermissionRow(title: "Speech Recognition", granted: false) {
                    SystemSettingsLink.open("Privacy_SpeechRecognition")
                }
            }
        } header: {
            Text("Captions".localized())
        } footer: {
            Text("ishare transcribes the audio of each recording on this Mac and never sends it anywhere. Turning this on asks for Speech Recognition permission.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { authorized = SpeechCaptioner.isAuthorized }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            authorized = SpeechCaptioner.isAuthorized
        }
    }
}

private enum SystemSettingsLink {
    static func open(_ privacyAnchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
