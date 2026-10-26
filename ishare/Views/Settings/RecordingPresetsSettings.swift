import Defaults
import ishareCore
import KeyboardShortcuts
import SwiftUI

struct RecordingPresetsSettings: View {
    @Default(.recordingPresets) var presets
    @State private var editing: RecordingPreset?
    @State private var renaming: RecordingPreset?
    @State private var newName = ""
    @State private var pendingDeletion: RecordingPreset?

    var body: some View {
        Section {
            if presets.isEmpty {
                Text("You have no recording presets".localized())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(presets) { preset in
                    row(for: preset)
                }
                .onMove { RecordingPresets.move(fromOffsets: $0, toOffset: $1) }
            }
        } header: {
            Text("Recording Presets".localized())
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "A recording preset bundles video, audio, webcam, overlay, pointer, zoom and limit settings. Recording with a preset uses them only for that recording."
                        .localized()
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button {
                    editing = RecordingPreset.fromCurrentSettings(name: "")
                } label: {
                    Label("Add Preset".localized(), systemImage: "plus")
                }
                .accessibilityIdentifier("settings.recordingPresets.add")
            }
            .padding(.top, 6)
        }
        .sheet(item: $editing) { preset in
            RecordingPresetEditor(preset: preset) { saved in
                var named = saved
                named.name = RecordingPresets.uniqueName(saved.name, excluding: saved.id)
                RecordingPresets.save(named)
                editing = nil
            } onCancel: {
                editing = nil
            }
            .frame(width: 540, height: 640)
        }
        .alert(
            "Rename Preset".localized(),
            isPresented: Binding {
                renaming != nil
            } set: {
                if !$0 { renaming = nil }
            }
        ) {
            TextField("Name".localized(), text: $newName)
            Button("Rename".localized()) {
                if let renaming { RecordingPresets.rename(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel".localized(), role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            String(format: "Delete “%@”?".localized(), pendingDeletion?.name ?? ""),
            isPresented: Binding {
                pendingDeletion != nil
            } set: {
                if !$0 { pendingDeletion = nil }
            }
        ) {
            Button("Delete".localized(), role: .destructive) {
                if let pendingDeletion { RecordingPresets.delete(pendingDeletion) }
                pendingDeletion = nil
            }
        }
    }

    private func row(for preset: RecordingPreset) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle")
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.red.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                Text(RecordingPresetSummary.text(for: preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let shortcut = KeyboardShortcuts.getShortcut(for: preset.shortcutName) {
                Text(shortcut.description)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Edit…".localized()) { editing = preset }
                Button("Duplicate".localized()) { RecordingPresets.duplicate(preset) }
                Button("Rename…".localized()) {
                    newName = preset.name
                    renaming = preset
                }
                Button("Move Up".localized()) { RecordingPresets.move(preset, by: -1) }
                    .disabled(presets.first?.id == preset.id)
                Button("Move Down".localized()) { RecordingPresets.move(preset, by: 1) }
                    .disabled(presets.last?.id == preset.id)
                Divider()
                Button("Delete".localized(), role: .destructive) { pendingDeletion = preset }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .helpAndAccessibilityLabel("More".localized())
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = preset }
    }
}

extension RecordingPresetsSettings: SettingsSearchable {
    static let searchEntries: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            "Recording Presets", pane: .recording,
            keywords: ["Preset", "Recording preset", "Add Preset", "Duplicate", "Rename", "Profile", "Record with preset", "Shortcut"])
    ]
}

enum RecordingPresetSummary {
    static func text(for preset: RecordingPreset) -> String {
        var parts = [preset.resolution.title.localized(), "\(preset.frameRate.rawValue) fps"]
        if preset.useHEVC { parts.append("HEVC") }
        if preset.recordMic { parts.append("Microphone".localized()) }
        if preset.showWebcam { parts.append("Webcam".localized()) }
        if preset.autoZoomEnabled { parts.append("Auto zoom".localized()) }
        return parts.joined(separator: " · ")
    }
}

struct RecordingPresetEditor: View {
    let onSave: (RecordingPreset) -> Void
    let onCancel: () -> Void
    @State private var preset: RecordingPreset
    @State private var isAppPickerPresented = false

    init(preset: RecordingPreset, onSave: @escaping (RecordingPreset) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _preset = State(initialValue: preset)
    }

    private var trimmedName: String {
        preset.name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name".localized(), text: $preset.name, prompt: Text("Tutorial".localized()))
                        .accessibilityIdentifier("settings.recordingPresets.name")
                    Picker("Record".localized(), selection: $preset.region) {
                        Text("Screen or window".localized()).tag(false)
                        Text("Region".localized()).tag(true)
                    }
                    KeyboardShortcuts.Recorder("Shortcut:".localized(), name: preset.shortcutName)
                }
                Section("Video".localized()) {
                    Picker("Resolution".localized(), selection: $preset.resolution) {
                        ForEach(RecordingResolution.allCases) { Text($0.title.localized()).tag($0) }
                    }
                    Picker("Frame rate".localized(), selection: $preset.frameRate) {
                        ForEach(RecordingFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                    }
                    Toggle("Use HEVC".localized(), isOn: $preset.useHEVC)
                    Toggle("Use HDR".localized(), isOn: $preset.useHDR)
                }
                Section("Audio".localized()) {
                    Picker("Audio source".localized(), selection: $preset.audioSource) {
                        ForEach(RecordingAudioSource.allCases) { Text($0.title.localized()).tag($0) }
                    }
                    if preset.audioSource == .selectedApps {
                        LabeledContent("Apps".localized()) {
                            HStack {
                                Text("\(preset.audioBundleIDs.count)")
                                    .foregroundStyle(.secondary)
                                Button("Choose…".localized()) { isAppPickerPresented = true }
                            }
                        }
                    }
                    Toggle("Record microphone".localized(), isOn: $preset.recordMic)
                }
                Section("Webcam".localized()) {
                    Toggle("Show webcam".localized(), isOn: $preset.showWebcam)
                    if preset.showWebcam {
                        Picker("Size".localized(), selection: $preset.webcamSize) {
                            ForEach(WebcamBubbleSize.allCases) { Text($0.title.localized()).tag($0) }
                        }
                        Picker("Position".localized(), selection: $preset.webcamCorner) {
                            ForEach(WebcamCorner.allCases) { Text($0.title.localized()).tag($0) }
                        }
                    }
                }
                Section("Clicks & Keystrokes".localized()) {
                    Toggle("Show keystrokes".localized(), isOn: $preset.showKeystrokes)
                    if preset.showKeystrokes {
                        Toggle("Only show shortcuts".localized(), isOn: $preset.keystrokesShortcutsOnly)
                    }
                    Toggle("Record clicks".localized(), isOn: $preset.recordClicks)
                    Toggle("Click ripples".localized(), isOn: $preset.clickRipples)
                }
                Section("Pointer".localized()) {
                    Toggle("Record pointer".localized(), isOn: $preset.recordPointer)
                    Toggle("Smooth pointer movement".localized(), isOn: $preset.pointerSmoothing)
                    Stepper(value: $preset.pointerScale, in: PointerEffectSettings.scaleRange, step: 0.25) {
                        LabeledContent("Pointer size".localized(), value: String(format: "%.2g×", preset.pointerScale))
                    }
                    Toggle("Hide the pointer when idle".localized(), isOn: $preset.hidesIdlePointer)
                }
                Section("Auto Zoom".localized()) {
                    Toggle("Auto zoom".localized(), isOn: $preset.autoZoomEnabled)
                    if preset.autoZoomEnabled {
                        Stepper(value: $preset.autoZoomLevel, in: AutoZoomSettings.zoomRange, step: 0.25) {
                            LabeledContent("Zoom level".localized(), value: String(format: "%.2g×", preset.autoZoomLevel))
                        }
                    }
                }
                Section("Limits".localized()) {
                    Stepper(value: $preset.maxMinutes, in: 0 ... 600, step: 1) {
                        LabeledContent(
                            "Stop after".localized(), value: preset.maxMinutes > 0 ? String(format: "%d min".localized(), preset.maxMinutes) : "No limit".localized())
                    }
                    Stepper(value: $preset.maxMegabytes, in: 0 ... 100_000, step: 50) {
                        LabeledContent("Stop at file size".localized(), value: preset.maxMegabytes > 0 ? "\(preset.maxMegabytes) MB" : "No limit".localized())
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel".localized(), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save".localized()) {
                    var saved = preset
                    saved.name = trimmedName
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier("settings.recordingPresets.save")
            }
            .padding()
        }
        .sheet(isPresented: $isAppPickerPresented) {
            AudioAppsPicker(bundleIDs: $preset.audioBundleIDs)
                .frame(width: 380, height: 460)
        }
    }
}

struct RecordingPresetKeybindSection: View {
    @Default(.recordingPresets) var presets

    var body: some View {
        if !presets.isEmpty {
            Section("Recording Presets".localized()) {
                ForEach(presets) { preset in
                    KeyboardShortcuts.Recorder(preset.name + ":", name: preset.shortcutName)
                }
            }
        }
    }
}
