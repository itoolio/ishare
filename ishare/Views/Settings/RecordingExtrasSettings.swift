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
            NotesSettingsSection()
            InstantReplaySettingsSection()
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

struct AudioSourceSettingsRows: View {
    @Binding var audioSource: RecordingAudioSource
    @Default(.recordingAudioBundleIDs) private var bundleIDs
    @State private var isAppPickerPresented = false

    var body: some View {
        Picker("Audio source".localized(), selection: $audioSource) {
            ForEach(RecordingAudioSource.allCases) { Text($0.title.localized()).tag($0) }
        }
        .accessibilityIdentifier("settings.recording.audioSource")
        if audioSource == .selectedApps {
            LabeledContent("Apps".localized()) {
                HStack {
                    Text("\(bundleIDs.count)")
                        .foregroundStyle(.secondary)
                    Button("Choose…".localized()) { isAppPickerPresented = true }
                }
            }
            .help("Full-screen and region recordings only include sound from these apps. Recording a single window or app always uses that app's sound.".localized())
            .sheet(isPresented: $isAppPickerPresented) {
                AudioAppsPicker(bundleIDs: $bundleIDs)
                    .frame(width: 380, height: 460)
            }
        }
    }
}

struct AudioAppChoice: Identifiable, Hashable {
    var id: String
    var name: String
    var isRunning: Bool

    static func choices(running: [(id: String, name: String)], selected: [String]) -> [AudioAppChoice] {
        let runningIDs = Set(running.map(\.id))
        let live = running.map { AudioAppChoice(id: $0.id, name: $0.name, isRunning: true) }
        let missing = selected.filter { !runningIDs.contains($0) }.map { AudioAppChoice(id: $0, name: $0, isRunning: false) }
        var seen = Set<String>()
        return (live + missing)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func toggled(_ id: String, in selected: [String]) -> [String] {
        selected.contains(id) ? selected.filter { $0 != id } : selected + [id]
    }
}

private struct AudioAppsPicker: View {
    @Binding var bundleIDs: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [AudioAppChoice] = []

    var body: some View {
        VStack(spacing: 0) {
            List(choices) { choice in
                Toggle(isOn: Binding(
                    get: { bundleIDs.contains(choice.id) },
                    set: { _ in bundleIDs = AudioAppChoice.toggled(choice.id, in: bundleIDs) }
                )) {
                    HStack {
                        Text(choice.name)
                        if !choice.isRunning {
                            Text("Not running".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("Only apps that are open are listed.".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done".localized()) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let own = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own }
            .compactMap { app in app.bundleIdentifier.map { (id: $0, name: app.localizedName ?? $0) } }
        choices = AudioAppChoice.choices(running: running, selected: bundleIDs)
    }
}

private struct InstantReplaySettingsSection: View {
    @Default(.instantReplayEnabled) private var enabled
    @Default(.instantReplayDuration) private var duration
    @Default(.instantReplayResolution) private var resolution
    @Default(.instantReplayFrameRate) private var frameRate
    @ObservedObject private var replay = InstantReplay.shared

    var body: some View {
        Section {
            Toggle("Instant replay".localized(), isOn: $enabled)
                .accessibilityIdentifier("settings.recording.instantReplay")
            if enabled {
                Picker("Keep the last".localized(), selection: $duration) {
                    ForEach(InstantReplayDuration.allCases) { Text($0.title.localized()).tag($0) }
                }
                Picker("Resolution".localized(), selection: $resolution) {
                    ForEach(RecordingResolution.allCases) { Text($0.title.localized()).tag($0) }
                }
                Picker("Frame rate".localized(), selection: $frameRate) {
                    ForEach(RecordingFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                }
                LabeledContent("Status".localized()) {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Instant Replay".localized())
        } footer: {
            Text("Keeps recording your main display in the background and saves the last moments when you press the Save Instant Replay shortcut. The clip is kept in a few small temporary files on this Mac, never uploaded until you save it, and recording all the time uses extra CPU and battery. It pauses while the screen is locked and when the battery is below 20%.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if replay.isRunning { return "Buffering".localized() }
        if replay.isPaused { return "Paused".localized() }
        return "Not running".localized()
    }
}

private struct NotesSettingsSection: View {
    @Default(.showRecordingNotes) private var showNotes

    var body: some View {
        Section {
            Toggle("Show notes while recording".localized(), isOn: $showNotes)
            Button("Edit Notes…".localized()) { RecordingNotesController.shared.show() }
        } header: {
            Text("Notes".localized())
        } footer: {
            Text("A floating notes panel, with an optional teleprompter, that only you can see: it is left out of every recording and screenshot. Show or hide it from the recording controls or with a shortcut.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
